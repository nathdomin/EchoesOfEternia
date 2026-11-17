extends Node
## Conteudo e cenario das zonas para a 1.0 (pacotes C e D), aplicado nas
## cenas pelo proprio Godot (abre, muda, salva). Pode rodar de novo: acha os
## nos pelo nome e o sorteio do cenario usa semente fixa (mesmo resultado).
##   godot --headless --path . res://tools/decorar_mapas.tscn
## Depois confira com tools/render_mapas.tscn.

const NPC_SCENE := preload("res://scenes/npc/npc.tscn")
const SPAWN_SCRIPT := preload("res://scripts/combat/monster_spawn_point.gd")
const FLOOR := 0
const NATURE := 1
const WATER := 3
const DETAIL := 4
## Grama da floresta (a mesma familia da vila, 11 colunas a direita).
const FOREST_GRASS := Vector2i(11, 12)
const FOREST_GRASS_VARIANTS := [Vector2i(12, 12), Vector2i(13, 12), Vector2i(14, 12), Vector2i(15, 12)]
## Grama clara (a da vila): a borda do desenho da agua e desta cor, entao o
## lago da floresta fica numa clareira dela.
const MEADOW := Vector2i(0, 12)
const MEADOW_VARIANTS := [Vector2i(1, 12), Vector2i(2, 12), Vector2i(3, 12), Vector2i(4, 12)]
## Florzinhas e tufos (os mesmos que a vila usa).
const DETAILS := [Vector2i(7, 2), Vector2i(2, 2), Vector2i(1, 2), Vector2i(2, 0), Vector2i(3, 2), Vector2i(5, 2), Vector2i(6, 2), Vector2i(0, 0), Vector2i(0, 2)]

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1010
	_village()
	_forest()
	_dungeon()
	print("RESULTADO: OK")
	get_tree().quit()


# ---------- zonas ----------

func _village() -> void:
	var root := _open("village")
	_spawn(root, "Skulls", "skull_lake", Vector2.INF, 3, -1.0)
	_spawn(root, "SlimesDoSul", "slime", _free_spot(root, Vector2(300, 520)), 3, 28.0)
	_spawn(root, "CogumelosDoLeste", "mushroom", _free_spot(root, Vector2(840, 440)), 2, 26.0)
	_npc(root, "Anciao", {
		"idle_lines": PackedStringArray([
			"Dizem que o Rei Slime nasceu da gosma de mil slimes.",
			"A floresta fica a leste. Siga a estrada de terra.",
			"Na minha idade, até os cogumelos me assustam.",
		]),
	})
	_npc(root, "Mercador", {
		"position": Vector2(520, 232), "npc_id": "mercador", "display_name": "Mercador",
		"frames": load("res://resources/characters/noble_frames.tres"),
		"faceset": load("res://assets/characters/ninja/Noble/Faceset.png"),
		"tint": Color(1.0, 0.92, 0.75),
		"greeting": "Poções, armas, tudo honesto! Quase tudo.",
		"idle_lines": PackedStringArray([
			"Compro gosma, esporo e osso. Não pergunte por quê.",
			"Ouro de monstro também é ouro, viajante.",
		]),
		"shop_items": _items(["pocao", "pocao_grande", "espada_ferro", "arco_curto", "cajado_aprendiz", "kunai", "armadura"]),
	})
	_save("village", root)


func _forest() -> void:
	var root := _open("forest")
	_spawn(root, "Mushrooms", "mushroom_dark", Vector2.INF, 3, -1.0)
	_spawn(root, "MorcegosDaTrilha", "bat", Vector2(640, 168), 3, 36.0)
	_spawn(root, "MorcegosDoCaminho", "bat", Vector2(360, 330), 2, 30.0)
	_spawn(root, "VenenoDoSul", "slime2", Vector2(490, 430), 3, 30.0)
	_spawn(root, "CogumelosDoNorte", "mushroom_dark", Vector2(490, 225), 2, 28.0)
	_npc(root, "Guarda", {
		"idle_lines": PackedStringArray([
			"Os morcegos odeiam luz. Pena que a mata é escura.",
			"A caverna fica no fim da trilha norte, a leste.",
			"Esporo de cogumelo cura veneno. Quase sempre.",
		]),
	})
	var ground := root.get_node("Ground") as TileMapLayer
	var detail := root.get_node("GroundDetail") as TileMapLayer
	var objects := root.get_node("Objects") as TileMapLayer
	# Arvores fora do mapa (desenho cortado na borda)
	for c in objects.get_used_cells():
		if c.x >= 60 or c.y >= 40 or c.x < 0 or c.y < 0:
			objects.erase_cell(c)
	# Lago a sudoeste: tira as arvores de perto e poe a agua (mesmo desenho do lago da vila)
	var pond := Rect2i(4, 27, 6, 4)
	for c in objects.get_used_cells():
		if pond.grow(2).has_point(c):
			objects.erase_cell(c)
	for c in detail.get_used_cells():
		if pond.grow(1).has_point(c):
			detail.erase_cell(c)
	var center := Vector2(pond.position) + Vector2(pond.size) / 2.0
	for c in ground.get_used_cells():
		var d := (Vector2(c) + Vector2(0.5, 0.5) - center) / (Vector2(pond.size) / 2.0 + Vector2(2.2, 1.8))
		if d.length() <= 1.0 and ground.get_cell_source_id(c) == FLOOR:
			ground.set_cell(c, FLOOR, MEADOW if _rng.randf() > 0.2 else MEADOW_VARIANTS[_rng.randi() % MEADOW_VARIANTS.size()])
	for y in pond.size.y:
		for x in pond.size.x:
			var ax := 0 if x == 0 else (2 if x == pond.size.x - 1 else 1)
			var ay := 6 if y == 0 else (8 if y == pond.size.y - 1 else 7)
			ground.set_cell(pond.position + Vector2i(x, y), WATER, Vector2i(ax, ay))
	# Chao variado e florzinhas (antes: 85% um tile so)
	for c in ground.get_used_cells():
		if ground.get_cell_source_id(c) != FLOOR or ground.get_cell_atlas_coords(c) != FOREST_GRASS:
			continue
		if _rng.randf() < 0.14:
			ground.set_cell(c, FLOOR, FOREST_GRASS_VARIANTS[_rng.randi() % FOREST_GRASS_VARIANTS.size()])
		if objects.get_cell_source_id(c) == -1 and detail.get_cell_source_id(c) == -1 \
				and not pond.grow(1).has_point(c) and _rng.randf() < 0.06:
			detail.set_cell(c, DETAIL, DETAILS[_rng.randi() % DETAILS.size()])
	_save("forest", root)


func _dungeon() -> void:
	var root := _open("dungeon")
	for p in root.get_node("MonsterSpawns").get_children():
		if p.get("monster") and (p.get("monster") as MonsterData).id == "bat":
			_spawn(root, p.name, "cave_bat", Vector2.INF, 3, -1.0)
	_spawn(root, "CaveirasDoMeio", "skull", Vector2(390, 172), 2, 24.0)
	_spawn(root, "CaveirasAntigasNorte", "skull_ancient", Vector2(520, 104), 2, 22.0)
	_spawn(root, "CaveirasAntigasSul", "skull_ancient", Vector2(510, 300), 2, 22.0)
	# O bau colado na entrada dava pocao sem risco: vai para a sala dos morcegos
	var chest := root.get_node_or_null("Chests/BauDaEntrada") as Node2D
	if chest:
		chest.position = Vector2(286, 316)
	_npc(root, "Explorador", {
		"position": Vector2(120, 196), "npc_id": "explorador", "display_name": "Explorador",
		"frames": load("res://resources/characters/knight_frames.tres"),
		"faceset": load("res://assets/characters/ninja/Knight/Faceset.png"),
		"tint": Color(1.0, 0.82, 0.62),
		"greeting": "Cuidado onde pisa: esta caverna está viva.",
		"idle_lines": PackedStringArray([
			"Mapeei metade da caverna. A outra metade tentou me comer.",
			"O Rei Slime se refaz da própria gosma. Fascinante e nojento.",
		]),
		"shop_items": _items(["pocao", "pocao_grande"]),
	})
	_save("dungeon", root)


# ---------- pecas ----------

func _open(zone: String) -> Node:
	return (load(Zones.SCENES[zone]) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)


func _save(zone: String, root: Node) -> void:
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, Zones.SCENES[zone])
	print("%s: %s" % [zone, "salvo" if err == OK else "ERRO %d" % err])
	root.free()


## Ponto de monstros (cria se nao existe). Vector2.INF / radius < 0 = mantem.
func _spawn(root: Node, node_name: String, monster_id: String, pos: Vector2, count: int, radius: float) -> void:
	var parent := root.get_node("MonsterSpawns")
	var p := parent.get_node_or_null(NodePath(node_name)) as Marker2D
	if p == null:
		p = Marker2D.new()
		p.name = node_name
		p.set_script(SPAWN_SCRIPT)
		parent.add_child(p)
		p.owner = root
	if pos != Vector2.INF:
		p.position = pos
	p.set("monster", load("res://resources/monsters/%s.tres" % monster_id))
	p.set("count", count)
	if radius >= 0.0:
		p.set("radius", radius)


func _npc(root: Node, node_name: String, props: Dictionary) -> void:
	var parent := root.get_node("Npcs")
	var n := parent.get_node_or_null(NodePath(node_name))
	if n == null:
		n = NPC_SCENE.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		n.name = node_name
		parent.add_child(n)
		n.owner = root
	for k: String in props:
		n.set(k, props[k])


func _items(ids: Array) -> Array[ItemData]:
	var out: Array[ItemData] = []
	for id: String in ids:
		out.append(load("res://resources/items/%s.tres" % id))
	return out


## Lugar livre perto de `center` (grama sem arvore/casa num quadrado de 3x3 tiles).
func _free_spot(root: Node, center: Vector2) -> Vector2:
	var objects := root.get_node("Objects") as TileMapLayer
	var ground := root.get_node("Ground") as TileMapLayer
	var base := Vector2i(center / 16.0)
	for r in 9:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := base + Vector2i(dx, dy)
				var ok := true
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var cc := c + Vector2i(ox, oy)
						if objects.get_cell_source_id(cc) != -1 or ground.get_cell_source_id(cc) != FLOOR:
							ok = false  # arvore/casa, agua ou fora do mapa
				if ok:
					return Vector2(c) * 16.0 + Vector2(8, 8)
	push_warning("sem lugar livre perto de %s" % center)
	return center
