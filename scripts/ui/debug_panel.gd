class_name DebugPanel
extends PanelContainer
## Painel F3 (Fase 6): FPS, ping, zona, posicao, entidades e memoria.
## Atualiza 4x por segundo so enquanto esta aberto.

var _label: Label
var _timer := 0.0


func _ready() -> void:
	theme_type_variation = &"DarkPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(162, 82)  # abaixo do aviso de zona/nivel (y 52-76)
	visible = false
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_constant_override("line_spacing", -3)
	add_child(_label)


func toggle() -> void:
	visible = not visible
	_timer = 0.0
	if visible:
		_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer += delta
	if _timer >= 0.25:
		_timer = 0.0
		_refresh()


func _refresh() -> void:
	var scene := get_tree().current_scene
	var player := scene.get_node_or_null("World/Player") as Node2D if scene else null
	var map: Node = scene.get("_map") if scene else null
	var lines: Array[String] = []
	lines.append("Echoes of Eternia v%s" % GameVersion.VERSION)
	lines.append("FPS %d  |  ping %s" % [Engine.get_frames_per_second(), _ping_text()])
	if map and player:
		lines.append("Zona %s  (%d, %d)" % [String(map.name), player.global_position.x, player.global_position.y])
		lines.append("Jogadores na zona %d  |  online %d" % [map.get_node("Players").get_child_count() + 1, NetworkManager.players.size()])
		var alive := 0
		for m in map.get_node("Monsters").get_children():
			if m is Monster and not m.is_dead():
				alive += 1
		lines.append("Monstros vivos %d / %d" % [alive, map.get_node("Monsters").get_child_count()])
	lines.append("Nós %d  |  memória %.0f MB" % [get_tree().get_node_count(), OS.get_static_memory_usage() / 1048576.0])
	_label.text = "\n".join(lines)


func _ping_text() -> String:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return "-"
	var server := peer.get_peer(1)
	if server == null:
		return "-"
	return "%d ms" % int(server.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
