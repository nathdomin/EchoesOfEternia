class_name ShopWindow
extends Control
## Comercio com um NPC mercador (pacote C), em pergaminho como o dialogo.
## Esquerda: o que ele vende (preco). Direita: o que o jogador pode vender
## (1 unidade por vez, PlayerData.sell_price). Setas + Enter ou mouse; Esc
## fecha. Quem decide e o servidor (distancia, ouro, espaco).

signal closed

const SIZE := Vector2(330, 196)
const LIST_H := 112.0

var _npc: Npc
var _gold: Label
var _buy_list: VBoxContainer
var _sell_list: VBoxContainer
var _info: Label
var _title: Label


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dimmer())
	var origin := ((Vector2(480, 270) - SIZE) / 2.0).round()
	var page := UiKit.parchment(SIZE, 6.0)
	page.position = origin
	add_child(page)
	_title = UiKit.gothic("Comércio", 24, UiKit.RUBRIC)
	_title.position = origin + Vector2(16, 4)
	add_child(_title)
	_gold = UiKit.ink_text("")
	_gold.position = origin + Vector2(SIZE.x - 120, 12)
	_gold.custom_minimum_size.x = 104
	_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_gold)
	for col in 2:
		var head := UiKit.ink_text(["COMPRAR", "VENDER"][col])
		head.add_theme_color_override("font_color", UiKit.RUBRIC)
		head.position = origin + Vector2(18 + col * 156, 34)
		add_child(head)
		var scroll := ScrollContainer.new()
		scroll.position = origin + Vector2(14 + col * 156, 48)
		scroll.size = Vector2(150, LIST_H)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		add_child(scroll)
		var list := VBoxContainer.new()
		list.custom_minimum_size.x = 140
		list.add_theme_constant_override("separation", -3)
		scroll.add_child(list)
		if col == 0:
			_buy_list = list
		else:
			_sell_list = list
	var rule := ColorRect.new()
	rule.color = Color(UiKit.INK, 0.35)
	rule.position = origin + Vector2(164, 36)
	rule.size = Vector2(1, LIST_H + 10)
	add_child(rule)
	_info = UiKit.ink_text("", SIZE.x - 32)
	_info.position = origin + Vector2(16, SIZE.y - 34)
	_info.modulate.a = 0.85
	add_child(_info)
	PlayerData.changed.connect(func() -> void:
		if visible:
			_refresh())


func open(npc: Npc) -> void:
	_npc = npc
	visible = true
	GameAudio.play("open")
	_title.text = "Comércio"
	_refresh(true)


func close() -> void:
	if visible:
		GameAudio.play("close")
	visible = false
	_npc = null
	closed.emit()


func _refresh(focus_first := false) -> void:
	if _npc == null:
		return
	var me := PlayerData.me
	_gold.text = "Ouro: %d" % int(me.get("gold", 0))
	# Lembra onde estava o foco (a lista se refaz a cada compra/venda)
	var was := get_viewport().gui_get_focus_owner()
	var was_col := 0 if was and _buy_list.is_ancestor_of(was) else 1
	var was_idx := was.get_index() if was and (_buy_list.is_ancestor_of(was) or _sell_list.is_ancestor_of(was)) else -1
	for list in [_buy_list, _sell_list]:
		for c in list.get_children():
			list.remove_child(c)
			c.queue_free()
	var all: Array[Button] = []
	for it in _npc.shop_items:
		if it == null:
			continue
		var b := _row(_buy_list, "%s — %d" % [it.display_name, it.price], it)
		b.disabled = int(me.get("gold", 0)) < it.price
		b.pressed.connect(func() -> void:
			GameAudio.play("pickup")
			PlayerData.buy(_npc.npc_id, it.id))
		all.append(b)
	var inv: Array = me.get("inventory", [])
	for i in inv.size():
		var s: Variant = inv[i]
		if not s is Dictionary:
			continue
		var it := PlayerData.item(s.id)
		if it == null or PlayerData.sell_price(it) <= 0:
			continue
		var label := "%s%s — %d" % [it.display_name, " x%d" % int(s.n) if int(s.n) > 1 else "", PlayerData.sell_price(it)]
		var b := _row(_sell_list, label, it)
		b.pressed.connect(func() -> void:
			GameAudio.play("drop")
			PlayerData.sell(i))
		all.append(b)
	if _sell_list.get_child_count() == 0:
		_sell_list.add_child(UiKit.ink_text("Nada para vender."))
	UiKit.choices(all, false, false)
	var target: Control = null
	if not focus_first and was_idx >= 0:
		var list := _buy_list if was_col == 0 else _sell_list
		if list.get_child_count() > 0:
			target = list.get_child(mini(was_idx, list.get_child_count() - 1)) as Control
	if target == null and not all.is_empty():
		target = all[0]
	if target and target.focus_mode != Control.FOCUS_NONE:
		target.grab_focus.call_deferred()


func _row(list: VBoxContainer, text: String, it: ItemData) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"InkFlatButton"
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.custom_minimum_size = Vector2(140, 14)
	b.add_theme_color_override("font_color", it.name_color(true))
	b.focus_entered.connect(func() -> void: _info.text = _describe(it))
	list.add_child(b)
	return b


static func _describe(it: ItemData) -> String:
	var parts: PackedStringArray = [it.description]
	var st := it.stat_text()
	if st != "":
		parts.append(st)
	if it.class_only != "":
		parts.append("Só " + PlayerData.class_data(it.class_only).display_name)
	return "  ·  ".join(parts)
