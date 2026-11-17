class_name ItemData
extends Resource
## Item (E18). Um .tres por item em resources/items/.

enum Kind { CONSUMABLE, WEAPON, ARMOR, TRINKET, MATERIAL }
enum Rarity { COMMON, RARE, EPIC }

## Cor do nome por raridade: no pergaminho (tinta) e sobre fundo escuro.
const RARITY_INK := [Color(0.2, 0.11, 0.08), Color(0.12, 0.28, 0.68), Color(0.5, 0.12, 0.58)]
const RARITY_LIGHT := [Color(1, 0.96, 0.88), Color(0.45, 0.7, 1.0), Color(0.85, 0.5, 1.0)]
const RARITY_NAMES := ["Comum", "Raro", "Épico"]

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var kind: Kind = Kind.MATERIAL
@export var max_stack := 20
## Consumivel: vida recuperada.
@export var heal := 0
## Consumivel: recarga em segundos (conferida no servidor).
@export var cooldown := 1.0
## Equipamento: bonus.
@export var bonus_damage := 0
@export var bonus_hp := 0
## Pacote C: raridade (cor do nome), classe que pode equipar ("" = todas),
## preco no mercador (ele paga uma fracao ao comprar de volta) e cor do
## icone (variantes do mesmo desenho).
@export var rarity: Rarity = Rarity.COMMON
@export var class_only := ""
@export var price := 0
@export var tint := Color.WHITE


func name_color(ink := true) -> Color:
	return (RARITY_INK if ink else RARITY_LIGHT)[rarity]


## Esta classe pode usar/equipar?
func usable_by(class_id: String) -> bool:
	return class_only.is_empty() or class_only == class_id


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
