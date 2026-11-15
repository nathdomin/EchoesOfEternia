class_name ItemData
extends Resource
## Item (E18). Um .tres por item em resources/items/.

enum Kind { CONSUMABLE, WEAPON, ARMOR, TRINKET, MATERIAL }

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var kind: Kind = Kind.MATERIAL
@export var max_stack := 20
## Consumivel: vida recuperada.
@export var heal := 0
## Equipamento: bonus.
@export var bonus_damage := 0
@export var bonus_hp := 0


## Espaco de equipamento ("" se nao equipa).
func equip_slot() -> String:
	match kind:
		Kind.WEAPON:
			return "weapon"
		Kind.ARMOR:
			return "armor"
		Kind.TRINKET:
			return "trinket"
	return ""


func stat_text() -> String:
	var parts: PackedStringArray = []
	if heal > 0:
		parts.append("Recupera %d de vida" % heal)
	if bonus_damage > 0:
		parts.append("+%d de ataque" % bonus_damage)
	if bonus_hp > 0:
		parts.append("+%d de vida" % bonus_hp)
	return ", ".join(parts)
