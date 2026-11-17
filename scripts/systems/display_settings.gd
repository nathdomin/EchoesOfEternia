class_name DisplaySettings
## Resolucao da janela do cliente. Todas sao multiplos inteiros da tela do jogo
## (480x270), entao o pixel art continua nitido: 2x, 3x (padrao) e 4x (Full HD).
## Escolha salva em user://client.cfg (secao "video"). Se a resolucao nao cabe
## numa janela no monitor (ex.: 1920x1080 num monitor Full HD), vira tela cheia.

const RESOLUTIONS: Array[Vector2i] = [Vector2i(960, 540), Vector2i(1440, 810), Vector2i(1920, 1080)]
const DEFAULT_INDEX := 1


static func label(index: int) -> String:
	var r := RESOLUTIONS[index]
	return "%d x %d" % [r.x, r.y]


static func current_index() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(Session.PREFS_PATH) != OK:
		return DEFAULT_INDEX
	return clampi(int(cfg.get_value("video", "resolution", DEFAULT_INDEX)), 0, RESOLUTIONS.size() - 1)


## Aplica a resolucao salva (chamado no boot, so no cliente).
static func apply_saved() -> void:
	apply(current_index())


static func set_index(index: int) -> void:
	index = clampi(index, 0, RESOLUTIONS.size() - 1)
	var cfg := ConfigFile.new()
	cfg.load(Session.PREFS_PATH)  # mantem as outras secoes
	cfg.set_value("video", "resolution", index)
	cfg.save(Session.PREFS_PATH)
	apply(index)


static func apply(index: int) -> void:
	if DisplayServer.get_name() == "headless":
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
