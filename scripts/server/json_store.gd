class_name JsonStore
extends RefCounted
## Leitura e gravacao de JSON no disco do servidor (contas, personagens).
##
## A gravacao e atomica: escreve num arquivo .tmp e so depois troca pelo
## original. Se a VM cair no meio, o arquivo antigo continua inteiro.


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("JsonStore: arquivo vazio ou ilegivel: %s" % path)
		return null
	var data: Variant = JSON.parse_string(text)
	if data == null:
		push_error("JsonStore: JSON invalido em %s" % path)
	return data


static func save_json(path: String, data: Variant) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("JsonStore: nao foi possivel gravar %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	f.flush()
	f.close()
	# No Linux o rename substitui o arquivo de forma atomica. No Windows ele
	# falha se o destino existir, entao o original e removido antes.
	if OS.get_name() == "Windows" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("JsonStore: nao foi possivel substituir %s (%s)" % [path, error_string(err)])
	return err


## Garante que a pasta existe. Na VM, as permissoes (so o usuario do
## servidor le) vem do systemd: StateDirectoryMode=0700.
static func ensure_dir(path: String) -> Error:
	return DirAccess.make_dir_recursive_absolute(path)
