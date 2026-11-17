extends Node
## Captura de cada zona inteira num PNG (para revisar o cenario sem jogar).
## godot --path . res://tools/render_mapas.tscn -- --out=PASTA [--zone=forest]
## Marca em vermelho os pontos de monstros, em azul as entradas/saidas, em
## amarelo NPCs e baus. Precisa de janela (nao roda com --headless).

var _out := "user://mapas"
var _only := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--zone="):
			_only = a.trim_prefix("--zone=")
	DirAccess.make_dir_recursive_absolute(_out)
	for zone: String in Zones.SCENES:
		if _only.is_empty() or zone == _only:
			await _render(zone)
	get_tree().quit()


func _render(zone: String) -> void:
	var map: Node2D = load(Zones.SCENES[zone]).instantiate()
	var vp := SubViewport.new()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(vp)
	vp.add_child(map)
	var bounds: Rect2 = map.get_bounds()
	vp.size = Vector2i(bounds.size)
	map.position = -bounds.position
	var marks := Node2D.new()
	marks.position = -bounds.position
	marks.z_index = 100
	vp.add_child(marks)
	marks.draw.connect(func() -> void:
		for p in map.get_node("MonsterSpawns").get_children():
			marks.draw_arc(p.position, p.get("radius"), 0, TAU, 24, Color.RED, 1.0)
			marks.draw_string(ThemeDB.fallback_font, p.position + Vector2(-20, -4), "%s x%d" % [p.get("monster").id, p.get("count")], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.RED)
		for group in ["Exits", "Entrances"]:
			for p in map.get_node(group).get_children():
				marks.draw_circle(p.position, 4, Color.DODGER_BLUE)
		for group in ["Npcs", "Chests"]:
			var g := map.get_node_or_null(group)
			if g:
				for p in g.get_children():
					marks.draw_circle(p.position, 3, Color.YELLOW)
		marks.draw_circle(map.get_node("SpawnPoint").position, 4, Color.MAGENTA))
	for i in 4:
		await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("%s/%s.png" % [_out, zone])
	print("salvo %s (%dx%d)" % [zone, vp.size.x, vp.size.y])
	vp.queue_free()
