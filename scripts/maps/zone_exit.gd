@tool
class_name ZoneExit
extends Area2D
## Passagem para outra zona (E23). Fica em "Exits" na cena da zona. Quando o
## player encosta, o cliente pede a viagem; o servidor confere se ele esta
## mesmo na passagem e o leva para `target_entrance` (um Marker2D em
## "Entrances") da zona `target_zone`.

@export var target_zone := "forest"
@export var target_entrance := "FromVillage"
@export var size := Vector2(16, 48):
	set(v):
		size = v
		_update_shape()


func _ready() -> void:
	_update_shape()
	if Engine.is_editor_hint():
		return
	body_entered.connect(func(body: Node) -> void:
		if body is Player:
			Characters.request_travel(name))


## Retangulo da passagem em coordenadas locais da zona.
func rect() -> Rect2:
	return Rect2(position - size / 2.0, size)


func _update_shape() -> void:
	var shape := get_node_or_null("Shape") as CollisionShape2D
	if shape == null:
		shape = CollisionShape2D.new()
		shape.name = "Shape"
		add_child(shape)
	var r := RectangleShape2D.new()
	r.size = size
	shape.shape = r
