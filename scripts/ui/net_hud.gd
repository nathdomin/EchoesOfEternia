class_name NetHud
extends CanvasLayer
## HUD de rede (E5): status (online e jogadores conectados) no canto
## superior e mensagens de sistema estilo MMO no canto inferior, que somem
## sozinhas depois de alguns segundos.

const MESSAGE_TIME := 6.0
const MAX_MESSAGES := 6

@onready var _status: Label = %Status
@onready var _log: VBoxContainer = %Log
@onready var _banner: Control = %Banner
@onready var _banner_text: Label = %BannerText


func _ready() -> void:
	NetworkManager.players_changed.connect(_update_status)
	NetworkManager.connection_ready.connect(_update_status)
	NetworkManager.system_message.connect(add_message)
	_update_status()


func add_message(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	_log.add_child(l)
	while _log.get_child_count() > MAX_MESSAGES:
		_log.get_child(0).free()
	var t := l.create_tween()
	t.tween_interval(MESSAGE_TIME)
	t.tween_property(l, "modulate:a", 0.0, 1.0)
	t.tween_callback(l.queue_free)


## Aviso fixo no topo (ex.: "Reconectando..."). Texto vazio esconde.
func show_banner(text: String) -> void:
	_banner_text.text = text
	_banner.visible = not text.is_empty()
	_update_status()


func _update_status() -> void:
	if not NetworkManager.is_online:
		_status.text = "Offline"
		return
	_status.text = "Online  -  %d/%d jogadores" % [NetworkManager.players.size(), NetworkManager.max_players]
