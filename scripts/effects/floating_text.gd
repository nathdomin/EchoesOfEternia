class_name FloatingText
extends Label
## Numero de dano/cura que sobe e some (Fase 6). So no cliente.
## Vai no mapa da zona (nunca nos containers de rede).

const DAMAGE := Color(1.0, 0.95, 0.85)
const HURT := Color(1.0, 0.35, 0.3)
const HEAL := Color(0.45, 1.0, 0.45)
const XP := Color(0.75, 0.6, 1.0)

static var _settings: Dictionary = {}


static func spawn(parent: Node, pos: Vector2, text: String, color: Color, big := false) -> void:
	# Pacote F: opcao na pausa (os avisos em texto, como "esquivou", continuam)
	if color in [DAMAGE, HURT, HEAL] and not DisplaySettings.flag("damage_numbers"):
		return
	if parent == null or not is_instance_valid(parent):
		return
	var l := FloatingText.new()
	l.text = text
	l.label_settings = _label_settings(color, big)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(48, 14)
	l.position = pos + Vector2(-24 + randf_range(-4, 4), -30)
	l.z_index = 20
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	var t := l.create_tween()
	t.set_parallel()
	t.tween_property(l, "position:y", l.position.y - 14.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	l.scale = Vector2(1.6, 1.6) if big else Vector2(1.25, 1.25)
	l.pivot_offset = l.size / 2.0
	t.tween_property(l, "scale", Vector2.ONE, 0.15)
	t.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.5)
	t.chain().tween_callback(l.queue_free)


static func _label_settings(color: Color, big: bool) -> LabelSettings:
	var key := "%s%s" % [color.to_html(), big]
	if not _settings.has(key):
		var ls := LabelSettings.new()
		ls.font = preload("res://assets/ui/fonts/pixelify_sans.ttf")
		ls.font_size = 11
		ls.font_color = color
		ls.outline_size = 3
		ls.outline_color = Color(0.08, 0.04, 0.04)
		_settings[key] = ls
	return _settings[key]
