class_name DisplaySettings
## Resolucao da janela do cliente. Todas sao multiplos inteiros da tela do jogo
## (480x270), entao o pixel art continua nitido: 2x, 3x (padrao) e 4x (Full HD).
## Escolha salva em user://client.cfg (secao "video"). Se a resolucao nao cabe
## numa janela no monitor (ex.: 1920x1080 num monitor Full HD), vira tela cheia.

const RESOLUTIONS: Array[Vector2i] = [Vector2i(960, 540), Vector2i(1440, 810), Vector2i(1920, 1080)]
const DEFAULT_INDEX := 1
## Pacote F: a opcao depois das resolucoes e a tela cheia.
const FULLSCREEN := 3
## Pacote F: opcoes do jogador (secao "ui" do client.cfg) e o padrao de cada.
const FLAGS := {"damage_numbers": true, "screen_shake": true}
static var _flags: Dictionary = {}


static func option_count() -> int:
	return RESOLUTIONS.size() + 1


## Opcao ligada? (numeros de dano, tremor da tela). Lida 1x e guardada.
static func flag(key: String) -> bool:
	if not _flags.has(key):
		var cfg := ConfigFile.new()
		cfg.load(Session.PREFS_PATH)
		_flags[key] = bool(cfg.get_value("ui", key, FLAGS.get(key, true)))
	return _flags[key]


static func set_flag(key: String, on: bool) -> void:
	_flags[key] = on
	var cfg := ConfigFile.new()
	cfg.load(Session.PREFS_PATH)  # mantem as outras secoes
	cfg.set_value("ui", key, on)
	cfg.save(Session.PREFS_PATH)


static func label(index: int) -> String:
	if index == FULLSCREEN:
		return "Tela cheia"
	var r := RESOLUTIONS[index]
	return "%d x %d" % [r.x, r.y]


static func current_index() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(Session.PREFS_PATH) != OK:
		return DEFAULT_INDEX
	return clampi(int(cfg.get_value("video", "resolution", DEFAULT_INDEX)), 0, option_count() - 1)


## Aplica a resolucao salva (chamado no boot, so no cliente).
static func apply_saved() -> void:
	apply(current_index())


static func set_index(index: int) -> void:
	index = clampi(index, 0, option_count() - 1)
	var cfg := ConfigFile.new()
	cfg.load(Session.PREFS_PATH)  # mantem as outras secoes
	cfg.set_value("video", "resolution", index)
	cfg.save(Session.PREFS_PATH)
	apply(index)


static func apply(index: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if index == FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	var size := RESOLUTIONS[index]
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	# A janela tem barra de titulo: se nao cabe na area util, usa tela cheia
	if size.x > usable.size.x or size.y > usable.size.y - 32:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
