class_name Hotbar
extends HBoxContainer
## Barra de habilidades (E17/E22): teclas 1-3 = habilidades da classe,
## 4 = pocao (com a quantidade). Escurece o slot durante a recarga.
## A recarga aqui e so visual; quem manda e o servidor.

signal slot_clicked(index: int)

const SLOT := 24.0
const KEY_FONT := preload("res://resources/ui/name_label.tres")
const POTION_COOLDOWN := 1.0
const POTION_ICON := preload("res://assets/ui/ninja/Skill Icon/Job & Action/Potion.png")

var _slots: Array[Panel] = []
var _shades: Array[ColorRect] = []
var _ready_at: Array[int] = [0, 0, 0, 0]
var _durations: Array[float] = [1.0, 1.0, 1.0, POTION_COOLDOWN]
var _abilities: Array[AbilityData] = []


func _ready() -> void:
	add_theme_constant_override("separation", 3)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 4:
		var s := UiKit.slot(SLOT)
		s.mouse_filter = Control.MOUSE_FILTER_PASS
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.6)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.size = Vector2(SLOT, 0)
		s.add_child(shade)
		# Numero da tecla pequeno no canto (nao cobre mais o icone)
		var key := Label.new()
		key.text = str(i + 1)
		key.label_settings = KEY_FONT
		key.position = Vector2(2, SLOT - 11)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.add_child(key)
		s.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				slot_clicked.emit(i)
				s.accept_event())
		add_child(s)
		_slots.append(s)
		_shades.append(shade)
	PlayerData.changed.connect(refresh)
	refresh()


func refresh() -> void:
	var me := PlayerData.me
	# Copia: o array e do recurso ClassData (compartilhado); limpar o
	# original apagaria as habilidades da classe para o jogo todo.
	_abilities = []
	if not me.is_empty() and String(me.get("class", "")) != "":
		_abilities = PlayerData.class_data(me["class"]).abilities.duplicate()
	for i in 3:
		var icon: TextureRect = _slots[i].get_node("Icon")
		icon.texture = _abilities[i].icon if i < _abilities.size() else null
		_slots[i].tooltip_text = "%s\n%s\nRecarga: %.1f s" % [_abilities[i].display_name, _abilities[i].description, _abilities[i].cooldown] if i < _abilities.size() else ""
		if i < _abilities.size():
			_durations[i] = _abilities[i].cooldown
	var potions := 0
	for s in me.get("inventory", []):
		if s is Dictionary:
			var it := PlayerData.item(s.id)
			if it and it.kind == ItemData.Kind.CONSUMABLE:
				potions += int(s.n)
	(_slots[3].get_node("Icon") as TextureRect).texture = POTION_ICON
	(_slots[3].get_node("Count") as Label).text = str(potions)
	_slots[3].tooltip_text = "Poção de Vida (%d)" % potions
	_slots[3].modulate = Color.WHITE if potions > 0 else Color(1, 1, 1, 0.4)


func ability(index: int) -> AbilityData:
	return _abilities[index] if index < _abilities.size() else null


## Pode usar o slot agora? Se sim, comeca a recarga visual.
func try_use(index: int) -> bool:
	var now := Time.get_ticks_msec()
	if now < _ready_at[index] or (index < 3 and ability(index) == null):
		return false
	_ready_at[index] = now + int(_durations[index] * 1000.0)
	return true


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for i in 4:
		var left := maxf((_ready_at[i] - now) / 1000.0, 0.0)
		var frac := clampf(left / maxf(_durations[i], 0.01), 0.0, 1.0)
		_shades[i].size = Vector2(SLOT, SLOT * frac)
		_shades[i].position = Vector2(0, SLOT * (1.0 - frac))
