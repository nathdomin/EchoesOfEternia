class_name ClientUpdater
extends Node
## Atualizacao automatica do cliente (Fase 7).
##
## Ao abrir o menu, o .exe exportado le o `latest.json` da ultima versao
## publicada no repositorio publico de downloads (so o jogo, sem codigo):
##   {"version": "0.6.0", "zip": "<url do zip do cliente>", "sha256": "...", "size": N}
## Se for mais nova: baixa o zip, confere o SHA-256, tira o .exe de dentro,
## troca pelo atual (o Windows deixa renomear um .exe em uso: o antigo vira
## `.old.exe` e e apagado na proxima abertura) e reabre o jogo.
## Qualquer falha (sem internet, pasta sem permissao, arquivo corrompido)
## so avisa: o menu continua funcionando com a versao atual.
## Nao roda no editor, no servidor nem com `--no-update`.
## Publicar uma versao: tools/publicar.ps1.

signal status(text: String, busy: bool)

const REPO := "nathdomin/EchoesOfEternia-releases"
const MANIFEST_URL := "https://github.com/%s/releases/latest/download/latest.json" % REPO
const DOWNLOAD_PAGE := "github.com/%s" % REPO
const CHECK_TIMEOUT := 8.0
const DOWNLOAD_TIMEOUT := 600.0
const ZIP_PATH := "user://update/cliente.zip"

var _http: HTTPRequest
var _manifest: Dictionary = {}
var _downloading := false


static func enabled() -> bool:
	if not OS.has_feature("template") or not OS.has_feature("windows"):
		return false
	return not ("--no-update" in OS.get_cmdline_user_args() or "--no-update" in OS.get_cmdline_args())


## true se `a` for uma versao mais nova que `b` ("0.10.0" > "0.9.3").
static func is_newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false


func _ready() -> void:
	_remove_old_exe()
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = CHECK_TIMEOUT
	_http.request_completed.connect(_on_manifest)
	add_child(_http)
	if _http.request(MANIFEST_URL) != OK:
		print("[Atualizacao] Nao foi possivel verificar")


func _process(_delta: float) -> void:
	if _downloading and _http.get_body_size() > 0:
		var pct := 100 * _http.get_downloaded_bytes() / _http.get_body_size()
		status.emit("Baixando a versão %s... %d%%" % [_manifest.version, pct], true)


func _on_manifest(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http.request_completed.disconnect(_on_manifest)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[Atualizacao] Sem resposta (%d/%d): seguindo com a %s" % [result, code, GameVersion.VERSION])
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary and data.has("version") and data.has("zip") and data.has("sha256")):
		print("[Atualizacao] latest.json invalido")
		return
	_manifest = data
	if not is_newer(String(_manifest.version), GameVersion.VERSION):
		print("[Atualizacao] Ja na ultima versao (%s)" % GameVersion.VERSION)
		return
	if not _exe_dir_writable():
		_fail("Versão %s disponível: baixe em %s" % [_manifest.version, DOWNLOAD_PAGE])
		return
	print("[Atualizacao] Baixando a %s" % _manifest.version)
	DirAccess.make_dir_recursive_absolute(ZIP_PATH.get_base_dir())
	_http.timeout = DOWNLOAD_TIMEOUT
	_http.download_file = ZIP_PATH
	_http.request_completed.connect(_on_downloaded)
	if _http.request(String(_manifest.zip)) != OK:
		_fail("Não foi possível baixar a atualização.")
		return
	_downloading = true
	status.emit("Baixando a versão %s..." % _manifest.version, true)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_downloading = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("Falha ao baixar a atualização (%d/%d)." % [result, code])
		return
	if FileAccess.get_sha256(ZIP_PATH) != String(_manifest.sha256).to_lower():
		_fail("Atualização corrompida: tente reabrir o jogo.")
		return
	status.emit("Instalando a versão %s..." % _manifest.version, true)
	var exe := OS.get_executable_path()
	var fresh := exe.get_basename() + ".new.exe"
	if not _extract_exe(fresh):
		_fail("Não foi possível instalar a atualização.")
		return
	var old := exe.get_basename() + ".old.exe"
	DirAccess.remove_absolute(old)
	if DirAccess.rename_absolute(exe, old) != OK:
		DirAccess.remove_absolute(fresh)
		_fail("Não foi possível instalar a atualização.")
		return
	if DirAccess.rename_absolute(fresh, exe) != OK:
		DirAccess.rename_absolute(old, exe)  # desfaz: continua com a versao atual
		_fail("Não foi possível instalar a atualização.")
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ZIP_PATH))
	print("[Atualizacao] Instalada a %s; reabrindo" % _manifest.version)
	status.emit("Versão %s instalada. Reabrindo..." % _manifest.version, true)
	await get_tree().create_timer(0.8).timeout
	OS.create_process(exe, OS.get_cmdline_args())
	get_tree().quit()


## Tira o .exe de dentro do zip baixado e grava em `dest`.
func _extract_exe(dest: String) -> bool:
	var zip := ZIPReader.new()
	if zip.open(ZIP_PATH) != OK:
		return false
	var ok := false
	for f in zip.get_files():
		if f.get_extension().to_lower() == "exe":
			var bytes := zip.read_file(f)
			var out := FileAccess.open(dest, FileAccess.WRITE)
			if out and not bytes.is_empty():
				out.store_buffer(bytes)
				out.close()
				ok = FileAccess.get_size(dest) == bytes.size()
			break
	zip.close()
	return ok


func _exe_dir_writable() -> bool:
	var probe := OS.get_executable_path().get_base_dir().path_join(".echoes_update_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


func _remove_old_exe() -> void:
	var old := OS.get_executable_path().get_basename() + ".old.exe"
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)


func _fail(msg: String) -> void:
	print("[Atualizacao] ", msg)
	status.emit(msg, false)
