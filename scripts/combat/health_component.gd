class_name HealthComponent
extends Node
## Vida de um personagem ou monstro (E11). So o servidor altera a vida; os
## clientes recebem `hp`/`max_hp` pelo MultiplayerSynchronizer do dono do no.

signal damaged(amount: int, source_id: int)
signal healed(amount: int)
signal died(source_id: int)

@export var max_hp := 100
var hp := 100
## Horario (ms) do ultimo dano, para a regeneracao fora de combate.
var last_damage_ms := -100000


func _ready() -> void:
	hp = max_hp


func is_dead() -> bool:
	return hp <= 0


## Aplica dano e retorna quanto tirou de fato. `source_id` = peer do
## atacante (0 = monstro/ambiente).
func take_damage(amount: int, source_id := 0) -> int:
	if is_dead() or amount <= 0:
		return 0
	var dealt := mini(amount, hp)
	hp -= dealt
	last_damage_ms = Time.get_ticks_msec()
	damaged.emit(dealt, source_id)
	if hp <= 0:
		died.emit(source_id)
	return dealt


func heal(amount: int) -> int:
	if is_dead() or amount <= 0:
		return 0
	var got := mini(amount, max_hp - hp)
	hp += got
	if got > 0:
		healed.emit(got)
	return got


## Volta com a vida cheia (respawn) ou com um valor salvo.
func reset(value := -1) -> void:
	hp = max_hp if value <= 0 else mini(value, max_hp)
	last_damage_ms = -100000


func seconds_since_damage() -> float:
	return (Time.get_ticks_msec() - last_damage_ms) / 1000.0
