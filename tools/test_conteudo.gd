extends Node
## Teste do conteudo da 1.0 (pacotes B e C), sem rede:
##   godot --headless --path . res://tools/test_conteudo.tscn
## Confere que tudo o que um .tres cita existe (monstros, itens, NPCs dos
## mapas, missoes da corrente) e imprime as tabelas de equilibrio: dano por
## segundo das classes, tempo para matar os monstros e o chefe, XP das
## missoes contra a XP ate o nivel maximo. Sai com codigo 1 se algo falhar.

var _fails := 0


func _ready() -> void:
	var npcs := _map_npcs()
	_test_items()
	_test_monsters()
	_test_quests(npcs)
	_test_shops()
	_test_rules()
	_balance()
	print("RESULTADO: %s" % ("OK" if _fails == 0 else "%d FALHA(S)" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	print(("  ok    " if cond else "  FALHA ") + what)
	if not cond:
		_fails += 1


func _ids(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for f in DirAccess.get_files_at(dir):
		f = f.trim_suffix(".remap")
		if f.ends_with(".tres") and not f.ends_with("_frames.tres"):
			out.append(f.get_basename())
	return out


## npc_id -> {zona, no} de todos os NPCs dos mapas.
func _map_npcs() -> Dictionary:
	var out := {}
	for zone: String in Zones.SCENES:
		var map: Node = load(Zones.SCENES[zone]).instantiate()
		for n in map.get_node("Npcs").get_children():
			out[n.get("npc_id")] = {"zone": zone, "shop": n.get("shop_items")}
		map.free()
	return out


func _test_items() -> void:
	print("Itens:")
	var bad: PackedStringArray = []
	for id in _ids("res://resources/items"):
		var it := PlayerData.item(id)
		if it == null or it.icon == null or it.id != id or it.display_name.is_empty():
			bad.append(id)
		elif it.class_only != "" and not it.class_only in PlayerData.CLASS_IDS:
			bad.append(id + " (classe)")
	_check(bad.is_empty(), "%d itens com icone, nome e classe valida %s" % [_ids("res://resources/items").size(), bad])
	for tier in [["espada_ferro", "arco_curto", "cajado_aprendiz"], ["espada_aco", "arco_longo", "cajado_runico"], ["lamina_do_rei", "arco_do_rei", "cetro_do_rei"]]:
		var classes := []
		for id: String in tier:
			classes.append(PlayerData.item(id).class_only)
		classes.sort()
		_check(classes == ["arqueiro", "guerreiro", "mago"], "arma de cada classe no nivel de %s" % tier[0])


func _test_monsters() -> void:
	print("Monstros:")
	var by_zone := {}
	for zone: String in Zones.SCENES:
		var map: Node = load(Zones.SCENES[zone]).instantiate()
		var total := 0
		var levels: Array[int] = []
		for p in map.get_node("MonsterSpawns").get_children():
			var md: MonsterData = p.get("monster")
			_check(md != null and Monster.data_for(md.id) != null, "%s/%s: monstro existe" % [zone, p.name])
			if md:
				total += int(p.get("count"))
				if not md.is_boss:
					levels.append(md.level)
				for it in md.loot_items:
					if it == null:
						_check(false, "%s: item de saque vazio" % md.id)
		by_zone[zone] = total
		levels.sort()
		print("        %s: %d monstros, niveis %s" % [zone, total, levels])
		map.free()
	var sum := 0
	for z in by_zone:
		sum += by_zone[z]
	_check(sum >= 40, "mundo com pelo menos 40 monstros (%d; eram 21)" % sum)
	var boss := Monster.data_for("giant_slime")
	_check(boss.slow_immune and Monster.data_for(boss.summon_id) != null, "chefe imune a lentidao e com reforcos validos")
	# Dificuldade sobe com as zonas (antes: caveira forte na vila)
	var max_village := 0
	var map: Node = load(Zones.SCENES.village).instantiate()
	for p in map.get_node("MonsterSpawns").get_children():
		max_village = maxi(max_village, (p.get("monster") as MonsterData).level)
	map.free()
	_check(max_village <= 3, "vila so tem monstros ate o nivel 3 (%d)" % max_village)


func _test_quests(npcs: Dictionary) -> void:
	print("Missoes:")
	var ids := _ids("res://resources/quests")
	_check(ids.size() >= 14, "%d missoes (eram 5)" % ids.size())
	for id in ids:
		var q := PlayerData.quest(id)
		var problems: PackedStringArray = []
		if q.id != id:
			problems.append("id")
		if not npcs.has(q.giver):
			problems.append("quem da (%s) nao esta em nenhum mapa" % q.giver)
		if not npcs.has(q.turn_in_npc()):
			problems.append("quem recebe (%s) nao esta em nenhum mapa" % q.turn_in_npc())
		if q.turn_in_npc_name().is_empty():
			problems.append("sem nome de quem recebe")
		match q.kind:
			QuestData.Kind.KILL:
				if Monster.data_for(q.target_id) == null:
					problems.append("monstro %s" % q.target_id)
			QuestData.Kind.COLLECT:
				if PlayerData.item(q.target_id) == null:
					problems.append("item %s" % q.target_id)
			QuestData.Kind.TALK:
				if q.turn_in_to.is_empty():
					problems.append("recado sem destinatario")
		if q.requires != "" and PlayerData.quest(q.requires) == null:
			problems.append("requer %s" % q.requires)
		if not q.class_rewards.is_empty():
			for cid: String in PlayerData.CLASS_IDS:
				if q.class_reward(cid) == null:
					problems.append("sem recompensa para %s" % cid)
		_check(problems.is_empty(), "%s %s" % [id, problems if not problems.is_empty() else ""])


func _test_shops() -> void:
	print("Mercadores:")
	var found := 0
	for zone: String in Zones.SCENES:
		var map: Node = load(Zones.SCENES[zone]).instantiate()
		for n in map.get_node("Npcs").get_children():
			var items: Array = n.get("shop_items")
			if items.is_empty():
				continue
			found += 1
			for it: ItemData in items:
				_check(it != null and it.price > 0, "%s vende %s com preco" % [n.get("npc_id"), it.id if it else "?"])
		map.free()
	_check(found >= 1, "ha mercador (%d)" % found)
	for id in ["gosma", "esporo", "osso"]:
		_check(PlayerData.sell_price(PlayerData.item(id)) > 0, "%s vale ouro no mercador" % id)


func _test_rules() -> void:
	print("Regras:")
	_check(PlayerData.xp_scale(5, 5) == 1.0 and PlayerData.xp_scale(6, 3) == 0.5 and PlayerData.xp_scale(9, 1) == 0.1,
			"XP menor para monstro bem abaixo do nivel")
	var daily := PlayerData.quest("rei_slime_diario")
	var data := {"level": 10, "quests": {"o_rei_slime": {"state": "done"}, "rei_slime_diario": {"state": "done", "at": 1000}}}
	_check(not PlayerData.can_accept(data, daily, 1000 + 3600), "repetivel: nao aceita antes do tempo")
	_check(PlayerData.can_accept(data, daily, 1000 + 21 * 3600), "repetivel: aceita depois de 20 h")
	var talk := PlayerData.quest("carta_ao_guarda")
	_check(PlayerData.quest_progress({"quests": {"carta_ao_guarda": {"state": "active"}}}, talk) >= talk.count,
			"recado fica pronto assim que aceito")
	_check(PlayerData.quests_for("guarda").has(talk), "o Guarda recebe a carta do Anciao")


## Tabelas de equilibrio (pacote B): impressas para conferir no PR.
func _balance() -> void:
	print("Equilibrio (dano por segundo do golpe basico, combo do Guerreiro na media):")
	var dps := {}
	for lvl in [1, 10]:
		for cid: String in PlayerData.CLASS_IDS:
			var c := PlayerData.class_data(cid)
			var dmg := float(c.damage_at(lvl)) * (c.basic_power if c.is_ranged() else (2.0 + 1.6) / 3.0)
			dps["%s%d" % [cid, lvl]] = dmg / c.attack_cooldown
		print("        Nv%d: Guerreiro %.1f  Arqueiro %.1f  Mago %.1f" % [lvl, dps["guerreiro%d" % lvl], dps["arqueiro%d" % lvl], dps["mago%d" % lvl]])
	var top := maxf(dps.guerreiro1, maxf(dps.arqueiro1, dps.mago1))
	var low := minf(dps.guerreiro1, minf(dps.arqueiro1, dps.mago1))
	_check(low / top >= 0.75, "classes com dano parecido no Nv1 (menor/maior = %.2f; antes 0,45)" % (low / top))
	var boss := Monster.data_for("giant_slime")
	var solo: float = boss.max_hp / dps.guerreiro10
	var group: float = boss.max_hp * (1.0 + boss.hp_per_extra_player * 3) / (dps.guerreiro10 + dps.arqueiro10 + dps.mago10 + dps.guerreiro10)
	print("        Rei Slime: Guerreiro Nv10 sozinho %.0f s; grupo de 4 Nv10 %.0f s (antes ~14 s e ~5 s)" % [solo, group])
	_check(solo >= 30.0 and group >= 20.0, "chefe nao cai em segundos")
	print("Progressao (XP das missoes x XP ate o nivel maximo):")
	var quest_xp := 0
	for id in _ids("res://resources/quests"):
		var q := PlayerData.quest(id)
		if q.repeat_hours <= 0.0:
			quest_xp += q.reward_xp
	var need := 0
	for lvl in range(1, PlayerData.XP.max_level()):
		need += PlayerData.XP.needed(lvl)
	print("        missoes %d XP de %d (%.0f%%); o resto vem dos monstros" % [quest_xp, need, 100.0 * quest_xp / need])
	_check(float(quest_xp) / need >= 0.6, "missoes levam boa parte do caminho ate o nivel maximo")
