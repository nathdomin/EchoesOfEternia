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
	if not (multiplayer.has_multiplayer_peer() and multiplayer.is_server()):
		_add_marker()


const ARROW := preload("res://assets/ui/ninja/Theme/Theme Wood/arrow_right.png")
const SIGN_FONT := preload("res://resources/ui/name_label.tres")
var _arrow: Sprite2D
var _t := 0.0


## Cliente: placa com o nome da zona e uma seta que balanca, apontando para
## fora do mapa (revisao do cenario: as passagens nao eram vistas).
func _add_marker() -> void:
	var points_left := position.x < 200.0
	var dir := -1.0 if points_left else 1.0
	_arrow = Sprite2D.new()
	_arrow.texture = ARROW
	_arrow.flip_h = points_left
	_arrow.position = Vector2(-dir * 14.0, -6)
	_arrow.z_index = 5
	add_child(_arrow)
	var sign_label := Label.new()
	sign_label.text = Zones.display_name(target_zone)
	sign_label.label_settings = SIGN_FONT
	sign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign_label.size = Vector2(120, 10)
	sign_label.position = Vector2(-60 - dir * 44.0, -size.y / 2.0 - 12.0)
	sign_label.z_index = 5
	add_child(sign_label)


func _process(delta: float) -> void:
	if _arrow:
		_t += delta
		_arrow.offset.x = sin(_t * 4.0) * 2.0 * (-1.0 if _arrow.flip_h else 1.0)
		_arrow.modulate.a = 0.75 + 0.25 * sin(_t * 4.0)


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
