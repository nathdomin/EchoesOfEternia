extends Node
## Autoload "PlayerData" (E16-E18, E21): classe, nivel/XP, atributos,
## inventario, equipamento, saque e missoes de cada jogador.
##
## Tudo e decidido no servidor e fica no personagem salvo (Characters):
##   class, level, xp, inventory (lista de {id, n} ou null), equipment
##   {weapon, armor, trinket}, quests {id: {state, progress}}.
## O cliente recebe um retrato completo (`me`) a cada mudanca e so pede
## acoes por RPC (escolher classe, usar/equipar item, aceitar missao...).

signal changed                      ## cliente: `me` mudou
signal level_up(level: int)         ## cliente: subiu de nivel

const XP := preload("res://resources/progression/xp_table.tres")
const CLASS_IDS := ["guerreiro", "mago", "arqueiro"]
const DEFAULT_CLASS := "guerreiro"
const INVENTORY_SLOTS := 20
const EQUIP_SLOTS := ["weapon", "armor", "trinket"]
const STARTING_ITEMS := {"pocao": 3}
const NPC_TALK_RANGE := 40.0
## XP de quem estiver no grupo (mesma zona, perto): cada um ganha esta
## fracao do total, dividida pelo numero de membros, com bonus de grupo.
const PARTY_XP_RANGE := 320.0
const PARTY_BONUS := 0.25
## Parte do dano para contar o abate na missao (fora do time vencedor).
const CREDIT_SHARE := 0.25
## Parte do dano para ganhar XP e saque de um chefe.
const CREDIT_SHARE_BOSS := 0.05
## Pacote C: o mercador compra de volta por esta fracao do preco.
const SELL_FRACTION := 0.25
## Pacote C: XP de monstro bem abaixo do nivel do jogador (diferenca -> fracao).
const XP_GAP_HALF := 3
const XP_GAP_TINY := 5

## Cliente: retrato do proprio personagem.
var me: Dictionary = {}

# servidor: zona -> { npc_id: Vector2 }
var _npcs: Dictionary = {}
# servidor: zona -> no "Chests" da zona (baus)
var _chest_roots: Dictionary = {}
# servidor: zona -> { npc_id: [item_id que vende] } (pacote C)
var _shops: Dictionary = {}
# cliente: quando chegou o ultimo retrato (para a contagem dos baus)
var _me_at_ms := 0


func _ready() -> void:
	NetworkManager.account_logged_in.connect(_on_logged_in)
	NetworkManager.connection_ended.connect(func(_r: String) -> void: me = {})


# ---------- dados (servidor e cliente) ----------

static func class_data(cid: String) -> ClassData:
	if not cid in CLASS_IDS:
		cid = DEFAULT_CLASS
	return load("res://resources/classes/%s.tres" % cid)


static func item(item_id: String) -> ItemData:
	var path := "res://resources/items/%s.tres" % item_id
	if not item_id.is_valid_identifier() or not ResourceLoader.exists(path):
		return null
	return load(path)


static func quest(qid: String) -> QuestData:
	var path := "res://resources/quests/%s.tres" % qid
	if not qid.is_valid_identifier() or not ResourceLoader.exists(path):
		return null
	return load(path)


## Missoes que um NPC oferece ou recebe (pacote C: recado levado a outro NPC).
static func quests_for(npc_id: String) -> Array[QuestData]:
	var out: Array[QuestData] = []
	for f in DirAccess.get_files_at("res://resources/quests"):
		var fname := f.trim_suffix(".remap")
		if fname.ends_with(".tres"):
			var q := quest(fname.get_basename())
			if q and (q.giver == npc_id or q.turn_in_npc() == npc_id):
				out.append(q)
	return _chain_order(out)


## XP de um monstro conforme a diferenca de nivel (pacote C): bem abaixo do
## jogador rende pouco, para ninguem subir ate o 10 so batendo em slime.
static func xp_scale(player_level: int, monster_level: int) -> float:
	var gap := player_level - monster_level
	if gap >= XP_GAP_TINY:
		return 0.1
	if gap >= XP_GAP_HALF:
		return 0.5
	return 1.0


## Missoes que um NPC oferece (na ordem da corrente).
static func quests_of(npc_id: String) -> Array[QuestData]:
	var out: Array[QuestData] = []
	for f in DirAccess.get_files_at("res://resources/quests"):
		var fname := f.trim_suffix(".remap")
		if fname.ends_with(".tres"):
			var q := quest(fname.get_basename())
			if q and q.giver == npc_id:
				out.append(q)
	return _chain_order(out)


static func _chain_order(qs: Array[QuestData]) -> Array[QuestData]:
	var out: Array[QuestData] = []
	var prev := ""
	for i in qs.size():
		for q in qs:
			if q.requires == prev and not q in out:
				out.append(q)
				prev = q.id
				break
	for q in qs:
		if not q in out:
			out.append(q)
	return out


## Estado de uma missao para um retrato/dados: "" | "active" | "done".
static func quest_state(quests: Dictionary, qid: String) -> String:
	return String(quests.get(qid, {}).get("state", ""))


## O jogador pode aceitar `q`?
static func can_accept(data: Dictionary, q: QuestData, now := -1) -> bool:
	var quests: Dictionary = data.get("quests", {})
	var st := quest_state(quests, q.id)
	if st == "active":
		return false
	if st == "done":
		# Pacote C: repetivel depois de `repeat_hours`
		if q.repeat_hours <= 0.0:
			return false
		if now < 0:
			now = int(Time.get_unix_time_from_system())
		if now - int(quests[q.id].get("at", 0)) < q.repeat_hours * 3600.0:
			return false
	if q.requires != "" and quest_state(quests, q.requires) != "done":
		return false
	return int(data.get("level", 1)) >= q.min_level


static func count_in(inventory: Array, item_id: String) -> int:
	var n := 0
	for s in inventory:
		if s is Dictionary and s.id == item_id:
			n += int(s.n)
	return n


## Progresso atual de uma missao ativa.
static func quest_progress(data: Dictionary, q: QuestData) -> int:
	if q.kind == QuestData.Kind.TALK:
		return q.count  # recado: pronto assim que aceita; e so levar
	if q.kind == QuestData.Kind.COLLECT:
		return mini(count_in(data.get("inventory", []), q.target_id), q.count)
	return mini(int(data.get("quests", {}).get(q.id, {}).get("progress", 0)), q.count)


# ---------- servidor: login e atributos ----------

func register_zone(zone: String, map: Node) -> void:
	var npcs := {}
	var root := map.get_node_or_null("Npcs")
	if root:
		for n in root.get_children():
			if "npc_id" in n:
				npcs[n.npc_id] = n.position
				var sells: Array[String] = []
				for it: ItemData in n.get("shop_items"):
					if it:
						sells.append(it.id)
				if not sells.is_empty():
					if not _shops.has(zone):
						_shops[zone] = {}
					_shops[zone][n.npc_id] = sells
	_npcs[zone] = npcs
	var chests := map.get_node_or_null("Chests")
	if chests:
		_chest_roots[zone] = chests


func _on_logged_in(id: int, _account: String, _name: String) -> void:
	var data := Characters.data_of(id)
	if data.is_empty():
		return
	_normalize(data)
	refresh_stats(id, false)
	push(id)


## Garante os campos (personagens antigos) e corrige dados invalidos.
func _normalize(data: Dictionary) -> void:
	if not data.get("class", "") in CLASS_IDS:
		data["class"] = ""
	data.level = clampi(int(data.get("level", 1)), 1, XP.max_level())
	data.xp = maxi(int(data.get("xp", 0)), 0)
	var inv: Array = data.get("inventory", [])
	if inv.is_empty() and not data.has("inventory"):
		for item_id in STARTING_ITEMS:
			inv.append({"id": item_id, "n": STARTING_ITEMS[item_id]})
	inv.resize(INVENTORY_SLOTS)
	for i in inv.size():
		var s: Variant = inv[i]
		if not s is Dictionary or item(String(s.get("id", ""))) == null or int(s.get("n", 0)) <= 0:
			inv[i] = null
		else:
			inv[i] = {"id": String(s.id), "n": int(s.n)}
	data.inventory = inv
	var eq: Dictionary = data.get("equipment", {})
	for slot in EQUIP_SLOTS:
		var it := item(String(eq.get(slot, "")))
		eq[slot] = it.id if it and it.equip_slot() == slot else ""
	data.equipment = eq
	if not data.get("quests") is Dictionary:
		data.quests = {}
	data.gold = maxi(int(data.get("gold", 0)), 0)


## Atributos finais: classe + nivel + equipamento.
func stats_of(id: int) -> Dictionary:
	var data := Characters.data_of(id)
	var c := class_data(String(data.get("class", "")))
	var level := int(data.get("level", 1))
	var st := {"max_hp": c.max_hp_at(level), "damage": c.damage_at(level),
			"attack_cooldown": c.attack_cooldown, "reach": c.reach, "class": c}
	for slot in EQUIP_SLOTS:
		var it := item(String(data.get("equipment", {}).get(slot, "")))
		if it:
			st.max_hp += it.bonus_hp
			st.damage += it.bonus_damage
	return st


## Aplica os atributos na vida oficial (RemotePlayer) e avisa o dono.
func refresh_stats(id: int, notify := true) -> void:
	var avatar := Characters.avatar_of(id)
	if avatar == null:
		return
	var st := stats_of(id)
	var data := Characters.data_of(id)
	avatar.health.max_hp = st.max_hp
	avatar.health.hp = mini(avatar.health.hp, st.max_hp)
	avatar.level = int(data.level)
	avatar.skin = st["class"].skin if String(data.get("class", "")) != "" else String(data.skin)
	avatar.outfit = int(data.get("outfit", 0))
	avatar.sync_health()
	if notify:
		Combat.push_health(id)


## Retrato completo para o dono.
func push(id: int) -> void:
	var data := Characters.data_of(id)
	if data.is_empty():
		return
	var st := stats_of(id)
	var progress := {}
	for qid: String in data.quests:
		var q := quest(qid)
		if q:
			progress[qid] = quest_progress(data, q)
	_self_state.rpc_id(id, {
		"class": data["class"], "level": data.level, "xp": data.xp, "xp_next": XP.needed(data.level),
		"max_level": XP.max_level(), "inventory": data.inventory, "equipment": data.equipment,
		"quests": data.quests, "quest_progress": progress, "max_hp": st.max_hp, "damage": st.damage,
		"name": data.name, "skin": data.skin, "chests": _chest_timers(data),
		"gold": int(data.get("gold", 0)), "now": int(Time.get_unix_time_from_system()),
		"outfit": int(data.get("outfit", 0)), "tutorial_seen": bool(data.get("tutorial_seen", false)),
	})


## Baus ainda vazios para o jogador: { "zona/Bau": segundos que faltam }.
## Tira os que ja voltaram a encher.
func _chest_timers(data: Dictionary) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var out := {}
	var saved: Dictionary = data.get("chests", {})
	for key: String in saved.keys():
		var left := int(saved[key]) - now
		if left > 0:
			out[key] = left
		else:
			saved.erase(key)
	return out


func _changed(id: int) -> void:
	Characters.mark_dirty(id)
	push(id)


# ---------- servidor: XP, saque e missoes ----------

## Credito do abate (revisao MMO): o dano de cada jogador e somado por
## "time" (o grupo, ou o jogador sozinho). O time que mais bateu leva XP,
## saque e missao, e divide a XP como antes (membros perto, +25% cada).
## Quem nao e desse time mas causou CREDIT_SHARE do dano ainda conta para a
## missao. Chefe: todo time com CREDIT_SHARE_BOSS do dano ganha, e cada
## jogador rola o proprio saque.
func award_kill(killer_id: int, monster: Monster, damage_by: Dictionary = {}) -> void:
	if damage_by.is_empty() and killer_id != 0:
		damage_by = {killer_id: 1}
	var total := 0
	var teams: Dictionary = {}  ## chave -> {"damage": int, "top": peer, "top_dmg": int, "hitters": [peer]}
	for pid: int in damage_by:
		if Characters.data_of(pid).is_empty():
			continue  # saiu do jogo
		var dmg := int(damage_by[pid])
		total += dmg
		var key := _team_key(pid)
		var t: Dictionary = teams.get(key, {"damage": 0, "top": pid, "top_dmg": -1, "hitters": []})
		t.damage += dmg
		t.hitters.append(pid)
		if dmg > t.top_dmg:
			t.top = pid
			t.top_dmg = dmg
		teams[key] = t
	if teams.is_empty() or total <= 0:
		return
	var credited: Array = []
	if monster.data.is_boss:
		for key in teams:
			if float(teams[key].damage) / total >= CREDIT_SHARE_BOSS:
				credited.append(teams[key])
	else:
		var best: Dictionary = {}
		for key in teams:
			if best.is_empty() or teams[key].damage > best.damage:
				best = teams[key]
		credited.append(best)
	var rewarded: Dictionary = {}
	for t: Dictionary in credited:
		var sharers := _sharers(t, monster)
		var xp_total := monster.data.xp_reward * (1.0 + PARTY_BONUS * (sharers.size() - 1))
		var each := float(xp_total) / sharers.size()
		for pid in sharers:
			rewarded[pid] = true
			_count_kill(pid, monster.monster_id)
			var lvl := int(Characters.data_of(pid).get("level", 1))
			add_xp(pid, maxi(1, roundi(each * xp_scale(lvl, monster.data.level))), false)
			if monster.data.gold_max > 0:
				var gold := randi_range(monster.data.gold_min, monster.data.gold_max)
				add_gold(pid, ceili(float(gold) / sharers.size()), false)
			_changed(pid)  # um retrato so com XP, ouro e missao
		if monster.data.is_boss:
			for pid in sharers:
				_roll_loot(pid, monster.data)
		else:
			_roll_loot(t.top, monster.data)
	# Ajudou bastante mas o abate foi de outro time: conta para a missao
	for pid: int in damage_by:
		if not rewarded.has(pid) and not Characters.data_of(pid).is_empty() \
				and float(damage_by[pid]) / total >= CREDIT_SHARE:
			_count_kill(pid, monster.monster_id)
			_changed(pid)


## Grupo do jogador ("p<menor id>") ou ele sozinho ("s<id>").
func _team_key(pid: int) -> String:
	var members := Social.party_members(pid)
	if members.is_empty():
		return "s%d" % pid
	members.sort()
	return "p%d" % members[0]


## Quem do time recebe: quem bateu e os membros vivos perto do monstro.
func _sharers(team: Dictionary, monster: Monster) -> Array[int]:
	var zone := Characters.zone_of(team.top)
	var out: Array[int] = []
	for pid: int in team.hitters:
		out.append(pid)
	for pid in Social.party_members(team.top):
		if not pid in out and Characters.zone_of(pid) == zone and not Combat.is_dead(pid) \
				and Characters.position_of(pid).distance_to(monster.position) <= PARTY_XP_RANGE:
			out.append(pid)
	return out


## `notify` = false: quem chama manda o retrato depois (evita dois envios).
func add_xp(id: int, amount: int, notify := true) -> void:
	var data := Characters.data_of(id)
	if data.is_empty() or amount <= 0:
		return
	if data.level >= XP.max_level():
		return
	data.xp += amount
	var leveled := false
	while data.level < XP.max_level() and data.xp >= XP.needed(data.level):
		data.xp -= XP.needed(data.level)
		data.level += 1
		leveled = true
	if data.level >= XP.max_level():
		data.xp = 0
	if leveled:
		refresh_stats(id, false)
		var avatar := Characters.avatar_of(id)
		if avatar:
			avatar.health.reset()  # sobe de nivel com a vida cheia
			avatar.sync_health()
		Combat.push_health(id)
		_announce_level(id, data)
		Combat.play_effect_in_zone(Characters.zone_of(id), "levelup", Characters.position_of(id) + Vector2(0, -10))
		_level_up.rpc_id(id, int(data.level))
	if notify:
		_changed(id)


## Pacote B: morrer custa `frac` da XP que o nivel pede (sem descer de
## nivel; no nivel maximo nao ha o que perder). Retorna quanto perdeu.
func death_penalty(id: int, frac: float) -> int:
	var data := Characters.data_of(id)
	if data.is_empty() or int(data.level) >= XP.max_level():
		return 0
	var lost := mini(int(data.xp), roundi(XP.needed(int(data.level)) * frac))
	if lost <= 0:
		return 0
	data.xp = int(data.xp) - lost
	_changed(id)
	return lost


## Nivel maximo: aviso para todos. Os outros: so o grupo e quem esta na zona
## (com 16 jogadores o chat virava uma lista de "subiu de nivel").
func _announce_level(id: int, data: Dictionary) -> void:
	if int(data.level) >= XP.max_level():
		NetworkManager.broadcast_system_message("%s alcançou o nível máximo (%d)!" % [data.name, data.level])
		return
	var text := "%s alcançou o nível %d!" % [data.name, data.level]
	var told: Dictionary = {}
	for pid in Characters.players_in_zone(Characters.zone_of(id)) + Social.party_members(id):
		if not told.has(pid):
			told[pid] = true
			NetworkManager.send_system_message(pid, text)


func _roll_loot(id: int, md: MonsterData) -> void:
	var cls := String(Characters.data_of(id).get("class", ""))
	for i in md.loot_items.size():
		var it: ItemData = md.loot_items[i]
		if it == null or not it.usable_by(cls):
			continue  # arma de outra classe: so cai para quem pode usar
		if i < md.loot_chances.size() and randf() < md.loot_chances[i]:
			if add_item(id, it.id, 1) == 0:
				NetworkManager.send_system_message(id, "Você recebeu: %s" % it.display_name)
			else:
				NetworkManager.send_system_message(id, "Inventário cheio: %s ficou para trás." % it.display_name)


func _count_kill(id: int, monster_id: String) -> void:
	var data := Characters.data_of(id)
	for qid: String in data.quests:
		var st: Dictionary = data.quests[qid]
		var q := quest(qid)
		if q and st.state == "active" and q.kind == QuestData.Kind.KILL and q.target_id == monster_id \
				and int(st.get("progress", 0)) < q.count:
			st.progress = int(st.get("progress", 0)) + 1
			if st.progress >= q.count:
				NetworkManager.send_system_message(id, "Missão pronta: %s. Volte para entregar." % q.title)


## Quantos `item_id` ainda cabem no inventario.
static func room_for(inventory: Array, it: ItemData) -> int:
	var n := 0
	for s in inventory:
		if s == null:
			n += it.max_stack
		elif s is Dictionary and s.id == it.id:
			n += maxi(it.max_stack - int(s.n), 0)
	return n


## Coloca itens no inventario. Retorna quantos NAO couberam.
func add_item(id: int, item_id: String, n: int) -> int:
	var it := item(item_id)
	var data := Characters.data_of(id)
	if it == null or data.is_empty():
		return n
	var inv: Array = data.inventory
	for i in inv.size():  # completa pilhas
		if n <= 0:
			break
		var s: Variant = inv[i]
		if s is Dictionary and s.id == item_id and s.n < it.max_stack:
			var put := mini(n, it.max_stack - int(s.n))
			s.n += put
			n -= put
	for i in inv.size():  # espacos vazios
		if n <= 0:
			break
		if inv[i] == null:
			var put := mini(n, it.max_stack)
			inv[i] = {"id": item_id, "n": put}
			n -= put
	_changed(id)
	return n


func remove_item(id: int, item_id: String, n: int) -> bool:
	var data := Characters.data_of(id)
	if count_in(data.inventory, item_id) < n:
		return false
	var inv: Array = data.inventory
	for i in inv.size():
		var s: Variant = inv[i]
		if n > 0 and s is Dictionary and s.id == item_id:
			var take := mini(n, int(s.n))
			s.n -= take
			n -= take
			if s.n <= 0:
				inv[i] = null
	_changed(id)
	return true


## Pacote C: ouro (cai dos monstros, recompensa de missao, venda).
func add_gold(id: int, n: int, notify := true) -> void:
	var data := Characters.data_of(id)
	if data.is_empty() or n <= 0:
		return
	data.gold = int(data.get("gold", 0)) + n
	if notify:
		_changed(id)


## Preco que o mercador paga por um item.
static func sell_price(it: ItemData) -> int:
	return floori(it.price * SELL_FRACTION) if it else 0


func _near_npc(id: int, npc_id: String) -> bool:
	var zone := Characters.zone_of(id)
	var npcs: Dictionary = _npcs.get(zone, {})
	return npcs.has(npc_id) and Characters.position_of(id).distance_to(npcs[npc_id]) <= NPC_TALK_RANGE


# ---------- baus (revisao do cenario) ----------

## Cliente: hora unix do servidor agora (o retrato traz a hora; soma o que
## passou desde entao). Para missoes repetiveis.
func server_now() -> int:
	return int(me.get("now", Time.get_unix_time_from_system())) + int((Time.get_ticks_msec() - _me_at_ms) / 1000.0)


## Cliente: segundos ate o bau encher de novo para mim (0 = cheio).
func chest_seconds_left(zone: String, chest_name: String) -> float:
	var timers: Dictionary = me.get("chests", {})
	var key := Chest.key_of(zone, chest_name)
	if not timers.has(key):
		return 0.0
	return maxf(float(timers[key]) - (Time.get_ticks_msec() - _me_at_ms) / 1000.0, 0.0)


func open_chest(chest_name: String) -> void:
	_open_chest.rpc_id(1, chest_name)


@rpc("any_peer", "call_remote", "reliable")
func _open_chest(chest_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var data := Characters.data_of(id)
	var zone := Characters.zone_of(id)
	if data.is_empty() or Combat.is_dead(id) or not _chest_roots.has(zone) \
			or chest_name.is_empty() or chest_name.validate_node_name() != chest_name:
		return
	var chest := (_chest_roots[zone] as Node).get_node_or_null(NodePath(chest_name)) as Chest
	if chest == null or chest.loot == null:
		return
	if Characters.position_of(id).distance_to(chest.position) > Chest.OPEN_RANGE + 10.0:
		return  # longe demais (o cliente confere antes; aqui e a regra)
	var key := Chest.key_of(zone, chest_name)
	var now := int(Time.get_unix_time_from_system())
	if not data.get("chests") is Dictionary:
		data.chests = {}
	if int(data.chests.get(key, 0)) > now:
		var minutes := ceili((int(data.chests[key]) - now) / 60.0)
		NetworkManager.send_system_message(id, "O baú está vazio. Volte em %d min." % minutes)
		return
	var got: Array[String] = []
	var lost: Array[String] = []
	var drops := chest.loot.roll()
	var cls := String(data.get("class", ""))
	drops = drops.filter(func(d: Dictionary) -> bool: return (d.item as ItemData).usable_by(cls))
	if drops.is_empty() and chest.loot.guaranteed:
		drops = [{"item": chest.loot.guaranteed, "n": 1}]
	for drop: Dictionary in drops:
		var it: ItemData = drop.item
		var left := add_item(id, it.id, int(drop.n))
		if left < int(drop.n):
			got.append("%s x%d" % [it.display_name, int(drop.n) - left] if int(drop.n) - left > 1 else it.display_name)
		if left > 0:
			lost.append(it.display_name)
	if got.is_empty() and not drops.is_empty():
		# Nada coube: o bau continua cheio para este jogador (nao gasta a vez)
		NetworkManager.send_system_message(id, "Inventário cheio: libere espaço para abrir o baú.")
		return
	data.chests[key] = now + chest.loot.respawn_seconds
	if not got.is_empty():
		NetworkManager.send_system_message(id, "Baú aberto: %s." % ", ".join(got))
	if not lost.is_empty():
		NetworkManager.send_system_message(id, "Inventário cheio: %s ficou para trás." % ", ".join(lost))
	Combat.play_effect_for(id, "spark", chest.position + Vector2(0, -10))
	_changed(id)


# ---------- mercador (pacote C) ----------

func buy(npc_id: String, item_id: String) -> void:
	_buy.rpc_id(1, npc_id, item_id)


func sell(slot: int) -> void:
	_sell.rpc_id(1, slot)


@rpc("any_peer", "call_remote", "reliable")
func _buy(npc_id: String, item_id: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var data := Characters.data_of(id)
	var zone := Characters.zone_of(id)
	if data.is_empty() or Combat.is_dead(id) or not _near_npc(id, npc_id):
		return
	if not item_id in _shops.get(zone, {}).get(npc_id, []):
		return
	var it := item(item_id)
	if it == null or it.price <= 0:
		return
	if int(data.gold) < it.price:
		NetworkManager.send_system_message(id, "Ouro insuficiente para %s." % it.display_name)
		return
	if room_for(data.inventory, it) < 1:
		NetworkManager.send_system_message(id, "Inventário cheio.")
		return
	data.gold = int(data.gold) - it.price
	add_item(id, it.id, 1)  # ja manda o retrato


## Vende 1 unidade do item no espaco `slot` (perto de um mercador).
@rpc("any_peer", "call_remote", "reliable")
func _sell(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var data := Characters.data_of(id)
	var zone := Characters.zone_of(id)
	if data.is_empty() or Combat.is_dead(id) or slot < 0 or slot >= INVENTORY_SLOTS:
		return
	var near_shop := false
	for npc_id: String in _shops.get(zone, {}):
		if _near_npc(id, npc_id):
			near_shop = true
	var s: Variant = data.inventory[slot]
	if not near_shop or not s is Dictionary:
		return
	var it := item(s.id)
	if it == null or sell_price(it) <= 0:
		return
	s.n = int(s.n) - 1
	if s.n <= 0:
		data.inventory[slot] = null
	data.gold = int(data.gold) + sell_price(it)
	_changed(id)


# ---------- API do cliente ----------

## `outfit` = cor da roupa (pacote E, Player.OUTFIT_SHIFTS).
func choose_class(cid: String, outfit := 0) -> void:
	_choose_class.rpc_id(1, cid, outfit)


func use_slot(slot: int) -> void:
	_use_slot.rpc_id(1, slot)


func unequip(slot: String) -> void:
	_unequip.rpc_id(1, slot)


func discard(slot: int) -> void:
	_discard.rpc_id(1, slot)


func use_potion() -> void:
	var inv: Array = me.get("inventory", [])
	for i in inv.size():
		var s: Variant = inv[i]
		if s is Dictionary:
			var it := item(s.id)
			if it and it.kind == ItemData.Kind.CONSUMABLE:
				use_slot(i)
				return


func accept_quest(qid: String) -> void:
	_accept_quest.rpc_id(1, qid)


func turn_in_quest(qid: String) -> void:
	_turn_in_quest.rpc_id(1, qid)


# ---------- RPCs ----------

@rpc("authority", "call_remote", "reliable")
func _self_state(state: Dictionary) -> void:
	me = state
	_me_at_ms = Time.get_ticks_msec()
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _level_up(level: int) -> void:
	level_up.emit(level)


@rpc("any_peer", "call_remote", "reliable")
func _choose_class(cid: String, outfit: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	var data := Characters.data_of(id)
	if data.is_empty() or data["class"] != "" or not cid in CLASS_IDS:
		return
	data["class"] = cid
	data.outfit = clampi(outfit, 0, Player.OUTFIT_SHIFTS.size() - 1)
	data.skin = class_data(cid).skin
	refresh_stats(id)
	var avatar := Characters.avatar_of(id)
	if avatar:
		avatar.health.reset()
		avatar.sync_health()
	Combat.push_health(id)
	NetworkManager.send_system_message(id, "Você agora é %s." % class_data(cid).display_name)
	_changed(id)


@rpc("any_peer", "call_remote", "reliable")
func _use_slot(slot: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	var data := Characters.data_of(id)
	if data.is_empty() or slot < 0 or slot >= INVENTORY_SLOTS or Combat.is_dead(id):
		return
	var s: Variant = data.inventory[slot]
	if not s is Dictionary:
		return
	var it := item(s.id)
	if it == null:
		return
	if it.kind == ItemData.Kind.CONSUMABLE:
		var avatar := Characters.avatar_of(id)
		if avatar == null or avatar.health.hp >= avatar.health.max_hp:
			return
		if not Combat.use_cooldown(id, "item:" + it.id, it.cooldown):
			return  # recarga da pocao (antes so existia no cliente)
		avatar.health.heal(it.heal)
		s.n -= 1
		if s.n <= 0:
			data.inventory[slot] = null
		Combat.play_effect_in_zone(Characters.zone_of(id), "spark", Characters.position_of(id) + Vector2(0, -8))
		_changed(id)
	elif it.equip_slot() != "":
		if not it.usable_by(String(data.get("class", ""))):
			NetworkManager.send_system_message(id, "Só %s pode usar %s." % [
					class_data(it.class_only).display_name, it.display_name])
			return
		# troca com o que estava equipado
		var eslot := it.equip_slot()
		var old := String(data.equipment[eslot])
		data.equipment[eslot] = it.id
		data.inventory[slot] = {"id": old, "n": 1} if old != "" else null
		refresh_stats(id)
		_changed(id)


@rpc("any_peer", "call_remote", "reliable")
func _unequip(eslot: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	var data := Characters.data_of(id)
	if data.is_empty() or not eslot in EQUIP_SLOTS or String(data.equipment[eslot]) == "":
		return
	var free: int = data.inventory.find(null)
	if free == -1:
		NetworkManager.send_system_message(id, "Inventário cheio.")
		return
	data.inventory[free] = {"id": data.equipment[eslot], "n": 1}
	data.equipment[eslot] = ""
	refresh_stats(id)
	_changed(id)


@rpc("any_peer", "call_remote", "reliable")
func _discard(slot: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	var data := Characters.data_of(id)
	if data.is_empty() or slot < 0 or slot >= INVENTORY_SLOTS or data.inventory[slot] == null:
		return
	data.inventory[slot] = null
	_changed(id)


@rpc("any_peer", "call_remote", "reliable")
func _accept_quest(qid: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	var data := Characters.data_of(id)
	var q := quest(qid)
	if data.is_empty() or q == null or not can_accept(data, q) or not _near_npc(id, q.giver):
		return
	data.quests[qid] = {"state": "active", "progress": 0}
	if q.kind == QuestData.Kind.TALK:
		NetworkManager.send_system_message(id, "Leve o recado a %s." % q.turn_in_npc_name())
	NetworkManager.send_system_message(id, "Nova missão: %s" % q.title)
	_changed(id)


@rpc("any_peer", "call_remote", "reliable")
func _turn_in_quest(qid: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	var data := Characters.data_of(id)
	var q := quest(qid)
	if data.is_empty() or q == null or quest_state(data.quests, qid) != "active" or not _near_npc(id, q.turn_in_npc()):
		return
	if quest_progress(data, q) < q.count:
		return
	# Recompensa que nao cabe se perderia: pede espaco antes de entregar
	var class_item := q.class_reward(String(data.get("class", "")))
	var free_slots: int = data.inventory.count(null)
	if (q.reward_item and room_for(data.inventory, q.reward_item) < q.reward_count) \
			or (class_item and free_slots < (2 if q.reward_item else 1)):
		NetworkManager.send_system_message(id, "Inventário cheio: libere espaço para receber a recompensa.")
		return
	if q.kind == QuestData.Kind.COLLECT and not remove_item(id, q.target_id, q.count):
		return
	data.quests[qid] = {"state": "done", "progress": q.count, "at": int(Time.get_unix_time_from_system())}
	NetworkManager.send_system_message(id, "Missão concluída: %s" % q.title)
	if q.reward_item:
		if add_item(id, q.reward_item.id, q.reward_count) == 0:
			NetworkManager.send_system_message(id, "Você recebeu: %s x%d" % [q.reward_item.display_name, q.reward_count])
	if class_item and add_item(id, class_item.id, 1) == 0:
		NetworkManager.send_system_message(id, "Você recebeu: %s" % class_item.display_name)
	if q.reward_gold > 0:
		add_gold(id, q.reward_gold, false)
		NetworkManager.send_system_message(id, "Você recebeu %d de ouro." % q.reward_gold)
	add_xp(id, q.reward_xp, false)
	_changed(id)
