extends Node
## Teste automatico do combate (revisao do combate). Roda sem janela:
##   godot --headless --path . res://tools/test_combate.tscn
## Confere a area do golpe (igual nas 4 direcoes, alcance, lados), se o
## efeito de corte cai no centro da area que acerta e a direcao do
## personagem ao andar na diagonal. Revisao das classes: mira (Targeting),
## direcao de mira em 8 sentidos, lentidao/congelamento/provocacao dos
## monstros e os kits das 3 classes. Sai com codigo 1 se algo falhar.

var _fails := 0
var _player: Player


func _ready() -> void:
	_test_hitbox()
	_test_slash_matches_hit()
	await _test_facing()
	_test_targeting()
	await _test_monster_status()
	_test_class_kits()
	print("RESULTADO: %s" % ("OK" if _fails == 0 else "%d FALHA(S)" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	print(("  ok    " if cond else "  FALHA ") + what)
	if not cond:
		_fails += 1


## Monstro com hitbox como no jogo (raio 8, no meio do sprite de 16 px).
func _monster_at(feet: Vector2) -> HitboxComponent:
	var body := Node2D.new()
	body.position = feet
	var hb := HitboxComponent.new()
	hb.radius = 8.0
	hb.position = Vector2(0, -8)
	body.add_child(hb)
	add_child(body)
	return hb


func _test_hitbox() -> void:
	print("Area do golpe (reach 20):")
	var origin := Combat.BODY  # jogador com os pes em (0,0)
	var reach := 20.0
	var dirs := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
	var far: Array[float] = []
	for d: Vector2 in dirs:
		var best := 0.0
		for i in 80:
			if _monster_at(d * i).is_hit_by(origin, d, reach):
				best = i
		far.append(best)
	_check(far.max() - far.min() <= 2.0, "alcance quase igual nas 4 direcoes %s" % [far])
	_check(far.min() >= 28.0, "alcance de pelo menos 28 px entre os pes (antes 26)")
	_check(not _monster_at(Vector2(0, 0) - Vector2.RIGHT * 24).is_hit_by(origin, Vector2.RIGHT, reach),
			"monstro 24 px atras nao leva o golpe")
	_check(_monster_at(Vector2(14, 14)).is_hit_by(origin, Vector2.RIGHT, reach),
			"monstro na diagonal da frente leva o golpe")
	_check(_monster_at(Vector2(4, 16)).is_hit_by(origin, Vector2.RIGHT, reach),
			"monstro encostado de lado leva o golpe")
	_check(_monster_at(Vector2(0, 0)).is_hit_by(origin, Vector2.UP, reach),
			"monstro em cima do jogador leva o golpe em qualquer direcao")


func _test_slash_matches_hit() -> void:
	print("Efeito do corte x area que acerta:")
	var holder := Node2D.new()
	add_child(holder)
	var frames: SpriteFrames = load("res://resources/effects/slash_frames.tres")
	var tex := frames.get_frame_texture("slash", 1).get_image()
	for d: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1, 1).normalized()]:
		Player.spawn_slash(holder, Vector2.ZERO, d)
		var fx := holder.get_child(holder.get_child_count() - 1) as AnimatedSprite2D
		# centro de massa dos pixels do arco, em coordenadas do mundo
		var sum := Vector2.ZERO
		var n := 0
		for y in tex.get_height():
			for x in tex.get_width():
				if tex.get_pixel(x, y).a > 0.0:
					sum += Vector2(x, y) - Vector2(tex.get_size()) / 2.0
					n += 1
		var local := sum / n + fx.offset
		var world := fx.position + local.rotated(fx.rotation)
		var want := HitboxComponent.arc_center(Combat.BODY, d, 20.0)
		_check(world.distance_to(want) <= 3.0, "corte %s desenhado em %s, area em %s" % [d, world.round(), want.round()])


func _test_facing() -> void:
	print("Direcao do personagem:")
	_player = (load("res://scenes/characters/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	await _hold(["move_up"], 6)
	await _hold(["move_up", "move_left"], 6)
	_check(_player.facing == Vector2i.UP, "andando para cima e apertando esquerda continua olhando para cima")
	await _hold([], 6)
	_check(_player.facing == Vector2i.UP, "soltando as duas juntas fica olhando para cima")
	await _hold(["move_left"], 6)
	await _hold(["move_left", "move_down"], 6)
	await _hold(["move_down"], 2)
	await _hold([], 6)
	_check(_player.facing == Vector2i.DOWN, "soltando a esquerda antes fica olhando para baixo")
	await _hold(["move_right"], 6)
	await _hold([], 6)
	_check(_player.facing == Vector2i.RIGHT, "parado depois de andar para a direita olha para a direita")


func _hold(actions: Array, frames: int) -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	for a in actions:
		Input.action_press(a)
	for i in frames:
		await get_tree().physics_frame


func _test_targeting() -> void:
	print("Mira (alvo sem travar):")
	var o := Vector2.ZERO
	var right := Vector2.RIGHT
	_check(Targeting.keeps_target(o, right, Vector2(60, 10), 8.0, 100.0), "alvo a frente ao alcance continua")
	_check(not Targeting.keeps_target(o, right, Vector2(-60, 0), 8.0, 100.0), "alvo atras e trocado")
	_check(not Targeting.keeps_target(o, right, Vector2(150, 0), 8.0, 100.0), "alvo longe demais e trocado")
	_check(Targeting.keeps_target(o, right, Vector2(-8, 0), 8.0, 100.0), "alvo encostado atras continua")
	var behind := _monster_at(Vector2(-20, 7))
	var front_far := _monster_at(Vector2(80, 7))
	var front_near := _monster_at(Vector2(40, 17))
	var side := _monster_at(Vector2(5, 90))
	var boxes := [behind, front_far, front_near, side]
	_check(Targeting.best_in_front(o, right, boxes, 100.0) == 2, "escolhe o mais perto a frente (nao o de tras)")
	_check(Targeting.best_in_front(o, Vector2.LEFT, boxes, 100.0) == 0, "virado para tras escolhe o de tras")
	_check(Targeting.best_in_front(o, right, boxes, 20.0) == -1, "nada a frente ao alcance = sem alvo")
	var line := [_monster_at(Vector2(90, 8)), _monster_at(Vector2(30, 8)), _monster_at(Vector2(60, 40))]
	var hits := Targeting.ray_hits(o, right, 120.0, line)
	_check(hits == [1, 0], "projetil acerta na ordem da linha e ignora quem esta fora %s" % [hits])
	_check(Targeting.ray_hits(o, right, 50.0, line) == [1], "projetil para no alcance")


func _test_monster_status() -> void:
	print("Efeitos nos monstros:")
	var root := Node2D.new()
	add_child(root)
	var m: Monster = (load("res://scenes/combat/monster.tscn") as PackedScene).instantiate()
	m.monster_id = "slime"
	root.add_child(m)
	m.apply_slow(0.5, 0.3)
	_check(m.status == Monster.Status.SLOW and is_equal_approx(m._speed_mult(), 0.5), "lentidao deixa a velocidade pela metade")
	m.apply_stun(0.3)
	_check(m.status == Monster.Status.FROZEN, "congelado")
	m.taunt(77)
	_check(m._target == 77 and m.is_fighting(77), "provocacao faz o monstro perseguir quem gritou")
	await get_tree().create_timer(0.7).timeout
	_check(m.status == Monster.Status.NONE, "efeitos acabam no tempo certo (status %d)" % m.status)
	var boss: Monster = (load("res://scenes/combat/monster.tscn") as PackedScene).instantiate()
	boss.monster_id = "giant_slime"
	root.add_child(boss)
	boss.apply_stun(1.0)
	_check(boss.status != Monster.Status.FROZEN, "chefe nao congela")
	root.queue_free()


func _test_class_kits() -> void:
	print("Classes:")
	for cid in PlayerData.CLASS_IDS:
		var c := PlayerData.class_data(cid)
		var ok := c.abilities.size() == 3
		for ab in c.abilities:
			ok = ok and ab != null and ab.icon != null and ab.effect != null and ab.id != "" 					and ResourceLoader.exists("res://resources/abilities/%s.tres" % ab.id)
		_check(ok, "%s: 3 habilidades com icone, efeito e id do arquivo" % c.display_name)
		if c.is_ranged():
			_check(c.basic_projectile != null and c.basic_range >= 80.0, "%s: golpe basico de longe (%d px)" % [c.display_name, c.basic_range])
	_check(not PlayerData.class_data("guerreiro").is_ranged(), "Guerreiro: golpe basico de perto")
