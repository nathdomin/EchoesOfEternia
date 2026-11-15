class_name Zones
extends RefCounted
## Zonas do mundo (E23/E24). O servidor carrega todas (afastadas no espaco,
## para a fisica de uma nao bater na outra); cada cliente carrega so a sua,
## na origem. Toda a logica usa coordenadas locais da zona.

const SCENES := {
	"village": "res://scenes/maps/village.tscn",
	"forest": "res://scenes/maps/forest.tscn",
	"dungeon": "res://scenes/maps/dungeon.tscn",
}
const NAMES := {"village": "Vila de Eternia", "forest": "Floresta Sombria", "dungeon": "Caverna do Rei Slime"}
## Afastamento de cada zona no servidor.
const SERVER_SPACING := 20000.0


## Nome do no da zona dentro de World (igual no servidor e no cliente).
static func node_name(zone: String) -> String:
	return zone.to_pascal_case()


static func display_name(zone: String) -> String:
	return NAMES.get(zone, zone)
