extends Node
## Cena inicial: decide se o jogo abre como servidor dedicado ou como cliente.

const SERVER_SCENE := "res://scenes/server/server_main.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"


func _ready() -> void:
	if not Session.is_server_mode():
		DisplaySettings.apply_saved()
	var scene := SERVER_SCENE if Session.is_server_mode() else MENU_SCENE
	get_tree().change_scene_to_file.call_deferred(scene)
