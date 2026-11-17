class_name StatusBar
extends HBoxContainer
## Barra de efeitos do proprio personagem (pacote B): icone + segundos que
## faltam de cada efeito que o servidor mandou (Combat.my_status). Fica
## embaixo do quadro do jogador. A contagem anda sozinha no cliente; o
## servidor manda de novo quando algo muda.

const SLOT := 16.0
const INFO := {
	"guard": {"icon": preload("res://assets/ui/ninja/Skill Icon/Items & Weapon/Guard.png"),
			"tip": "Grito de Guerra: 30% menos dano"},
	"poison": {"icon": preload("res://assets/enemies/ninja/Slime2/Faceset.png"),
			"tip": "Envenenado: perde vida a cada segundo"},
}

var _left: Dictionary = {}  ## efeito -> segundos


func _ready() -> void:
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Combat.own_status_changed.connect(_on_status)
	_on_status(Combat.my_status)


func _on_status(statuses: Dictionary) -> void:
	_left = statuses.duplicate()
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for key: String in _left:
		if not INFO.has(key):
			continue
		var s := UiKit.slot(SLOT)
		s.name = key
		s.mouse_filter = Control.MOUSE_FILTER_PASS
		s.tooltip_text = INFO[key].tip
		(s.get_node("Icon") as TextureRect).texture = INFO[key].icon
		add_child(s)
	_process(0.0)


func _process(delta: float) -> void:
	var expired := false
	for key: String in _left.keys():
		_left[key] = float(_left[key]) - delta
		if _left[key] <= 0.0:
			_left.erase(key)
			expired = true
			continue
		var s := get_node_or_null(NodePath(key))
		if s:
			(s.get_node("Count") as Label).text = str(ceili(_left[key]))
	if expired:
		_rebuild()


## Algum efeito ativo com este nome? (o personagem fica esverdeado no veneno)
func has_status(key: String) -> bool:
	return _left.has(key)
