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
## Musica de cada zona (cliente).
const MUSIC := {
	"village": "res://audio/music/36 - Village.ogg",
	"forest": "res://audio/music/37 - Dark Forest.ogg",
	"dungeon": "res://audio/music/21 - Dungeon.ogg",
}
## Som de fundo de cada zona (cliente, Gate 5): um som continuo (`loop`, em
## audio/sfx) e sons soltos sorteados a cada `every` segundos (min, max).
const AMBIENCE := {
	"village": {"loop": "amb_wind", "db": -8.0, "oneshots": ["bird0", "bird1", "bird2"], "every": Vector2(6, 14)},
	"forest": {"loop": "amb_wind", "db": -2.0, "oneshots": ["bird0", "bird1", "bird2"], "every": Vector2(3, 8)},
	"dungeon": {"loop": "amb_cave", "db": 0.0, "oneshots": ["drip"], "every": Vector2(1.5, 4.5)},
}
## Musica de luta contra chefe.
const BOSS_MUSIC := "res://audio/music/17 - Fight.ogg"
## Clima de cada zona (cliente): cor geral, folhas, vaga-lumes, vinheta e
## luz em volta do jogador (caverna escura).
const LOOK := {
	"village": {"tint": Color(1.0, 0.96, 0.9), "leaves": true, "fireflies": 40, "vignette": 0.35, "light": false},
	"forest": {"tint": Color(0.8, 0.9, 0.82), "leaves": true, "fireflies": 70, "vignette": 0.5, "light": false},
	"dungeon": {"tint": Color(0.3, 0.28, 0.4), "leaves": false, "fireflies": 0, "vignette": 0.6, "light": true},
}
## Afastamento de cada zona no servidor.
const SERVER_SPACING := 20000.0


## Nome do no da zona dentro de World (igual no servidor e no cliente).
static func node_name(zone: String) -> String:
	return zone.to_pascal_case()


static func look(zone: String) -> Dictionary:
	return LOOK.get(zone, LOOK.village)


static func display_name(zone: String) -> String:
	return NAMES.get(zone, zone)
