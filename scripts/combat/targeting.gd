class_name Targeting
extends RefCounted
## Mira do combate (revisao das classes): estilo MMO, com alvo selecionado,
## mas sem travar.
## - O alvo selecionado vale enquanto estiver ao alcance e nao ficar atras do
##   personagem (`keeps_target`).
## - Fora disso, o alvo passa a ser o monstro mais perto a frente
##   (`best_in_front`). Sem nenhum, o golpe sai na direcao em que o personagem
##   anda/olha.
## - Projeteis (golpe basico do Arqueiro/Mago, Tiro Perfurante, Bola de Fogo)
##   acertam o primeiro monstro na linha (`ray_hits`).
## Funcoes puras (so contas): usadas pelo cliente para escolher o alvo e pelo
## servidor para decidir o acerto. Testadas em tools/test_combate.gd.

## Encostado: vale mesmo de lado ou atras.
const CLOSE := 12.0
## "A frente" = ate 60 graus para cada lado da direcao do personagem.
const FRONT_DOT := 0.5
## O alvo selecionado so e trocado quando passa de ~100 graus (fica atras).
const BEHIND_DOT := -0.2
## Folga lateral da linha do projetil, alem do corpo do monstro.
const RAY_WIDTH := 4.0


## O alvo atual continua valendo? Ao alcance e nao atras de quem ataca.
static func keeps_target(origin: Vector2, forward: Vector2, center: Vector2, radius: float, reach: float) -> bool:
	var to := center - origin
	var d := to.length()
	if d > reach + radius:
		return false
	return d <= CLOSE or forward.dot(to / d) >= BEHIND_DOT


## Indice do hitbox mais perto a frente ao alcance, ou -1.
static func best_in_front(origin: Vector2, forward: Vector2, hitboxes: Array, reach: float) -> int:
	var best := -1
	var best_d := INF
	for i in hitboxes.size():
		var hb: HitboxComponent = hitboxes[i]
		var to := hb.center() - origin
		var d := to.length()
		if d > reach + hb.radius or d >= best_d:
			continue
		if d <= CLOSE or forward.dot(to / d) >= FRONT_DOT:
			best = i
			best_d = d
	return best


## Indices dos hitboxes que a linha de `origin` na direcao `dir`
## (normalizada), com `length` px, atravessa; do mais perto ao mais longe.
static func ray_hits(origin: Vector2, dir: Vector2, length: float, hitboxes: Array) -> Array[int]:
	var found: Array = []
	for i in hitboxes.size():
		var hb: HitboxComponent = hitboxes[i]
		var to := hb.center() - origin
		var along := to.dot(dir)
		if along < -hb.radius or along > length + hb.radius:
			continue
		if absf(to.cross(dir)) <= hb.radius + RAY_WIDTH:
			found.append([along, i])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array[int] = []
	for f in found:
		out.append(f[1])
	return out
