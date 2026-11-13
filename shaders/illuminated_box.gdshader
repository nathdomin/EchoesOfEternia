shader_type canvas_item;
// Caixa de letra capitular iluminada: moldura de ouro, fundo azul com
// trelica e pontos dourados, e uma janela em arco transparente (onde aparece
// a cena viva da vila, desenhada por baixo).

uniform vec2 size = vec2(136.0, 176.0);
uniform vec4 window_rect = vec4(30.0, 26.0, 92.0, 136.0); // x, y, largura, altura
uniform vec4 ink : source_color = vec4(0.14, 0.06, 0.06, 1.0);
uniform vec4 gold : source_color = vec4(0.85, 0.64, 0.24, 1.0);
uniform vec4 gold_light : source_color = vec4(0.99, 0.86, 0.46, 1.0);
uniform vec4 gold_dark : source_color = vec4(0.58, 0.38, 0.13, 1.0);
uniform vec4 blue : source_color = vec4(0.13, 0.22, 0.5, 1.0);
uniform vec4 blue_light : source_color = vec4(0.22, 0.36, 0.68, 1.0);
uniform vec4 red : source_color = vec4(0.62, 0.1, 0.1, 1.0);

// distancia "por dentro" de um retangulo com topo em arco (negativa = dentro)
float arch_dist(vec2 p, vec4 r) {
	float rad = r.z * 0.5;
	vec2 c = vec2(r.x + rad, r.y + rad);
	if (p.y < c.y) {
		return length(p - c) - rad;
	}
	float dx = max(r.x - p.x, p.x - (r.x + r.z));
	float dy = p.y - (r.y + r.w);
	return max(dx, dy);
}

void fragment() {
	vec2 px = floor(UV * size);
	float d = min(min(px.x, size.x - 1.0 - px.x), min(px.y, size.y - 1.0 - px.y));
	vec4 col;

	// fundo azul com trelica diagonal e pontos de ouro
	col = blue;
	if (mod(px.x + px.y, 8.0) == 0.0 || mod(px.x - px.y + 400.0, 8.0) == 0.0) col = blue_light;
	if (mod(px.x, 8.0) == 4.0 && mod(px.y, 8.0) == 0.0) col = gold;

	// moldura externa: tinta, ouro com brilho, tinta, filete vermelho
	if (d < 1.0) col = ink;
	else if (d < 5.0) {
		bool lit = (px.x < size.x * 0.5 && px.y < size.y * 0.5);
		col = (d < 2.0) ? (lit ? gold_light : gold) : (d < 4.0 ? gold : gold_dark);
		if (mod(px.x + px.y, 6.0) == 0.0 && d >= 2.0 && d < 4.0) col = gold_light;
	}
	else if (d < 6.0) col = ink;
	else if (d < 8.0) col = red;
	else if (d < 9.0) col = ink;

	// janela em arco: borda de ouro e interior transparente
	float a = arch_dist(px + vec2(0.5), window_rect);
	if (a < 4.0 && a >= 3.0) col = ink;
	else if (a < 3.0 && a >= 1.0) col = (a < 2.0) ? gold : gold_light;
	else if (a < 1.0 && a >= 0.0) col = ink;
	else if (a < 0.0) col = vec4(0.0);

	// joias nos cantos da moldura
	vec2 q = vec2(min(px.x, size.x - 1.0 - px.x), min(px.y, size.y - 1.0 - px.y));
	float j = length(q - vec2(3.5, 3.5));
	if (j < 4.5) col = ink;
	if (j < 3.5) col = red;
	if (j < 1.5) col = gold_light;

	COLOR = col;
}
