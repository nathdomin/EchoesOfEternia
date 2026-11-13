shader_type canvas_item;
// Pagina de manuscrito em pixel art: pergaminho manchado, bordas queimadas,
// moldura dourada, vinha com folhas nas bordas e flores vermelhas nos cantos.
// Calculado por pixel da tela (480x270), entao fica nitido.

uniform vec2 size = vec2(480.0, 270.0);
uniform float frame_margin = 16.0;      // distancia da borda ate a moldura dourada
uniform vec4 paper_light : source_color = vec4(0.94, 0.86, 0.68, 1.0);
uniform vec4 paper_mid : source_color = vec4(0.88, 0.77, 0.56, 1.0);
uniform vec4 paper_dark : source_color = vec4(0.78, 0.64, 0.43, 1.0);
uniform vec4 burnt : source_color = vec4(0.42, 0.25, 0.14, 1.0);
uniform vec4 outside : source_color = vec4(0.09, 0.05, 0.05, 1.0);
uniform vec4 gold : source_color = vec4(0.85, 0.64, 0.24, 1.0);
uniform vec4 gold_light : source_color = vec4(0.98, 0.84, 0.45, 1.0);
uniform vec4 ink : source_color = vec4(0.2, 0.11, 0.08, 1.0);
uniform vec4 vine : source_color = vec4(0.2, 0.36, 0.17, 1.0);
uniform vec4 leaf : source_color = vec4(0.42, 0.6, 0.26, 1.0);
uniform vec4 flower : source_color = vec4(0.72, 0.13, 0.12, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
			mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 px = floor(UV * size);
	float w = size.x;
	float h = size.y;

	// distancia ate cada borda e coordenada "ao longo" da borda mais proxima
	float dl = px.x, dr = w - 1.0 - px.x, dt = px.y, db = h - 1.0 - px.y;
	float d = min(min(dl, dr), min(dt, db));
	float t = (d == dt || d == db) ? px.x : px.y;

	// papel: manchas suaves posterizadas em 3 tons + fibras
	float n = vnoise(px * 0.035) * 0.65 + vnoise(px * 0.11) * 0.35;
	vec4 col = paper_light;
	if (n > 0.68) col = paper_mid;
	if (n > 0.84) col = paper_dark;
	if (hash(px) > 0.985) col = paper_dark;

	// escurecimento perto da borda (envelhecido)
	float edge_noise = vnoise(vec2(t * 0.15, d * 0.1)) * 6.0;
	if (d < 10.0 + edge_noise) col = mix(col, paper_dark, 0.6);
	// borda queimada irregular
	float tear = 3.0 + vnoise(vec2(t * 0.22, 3.7)) * 5.0;
	if (d < tear) col = burnt;
	if (d < tear - 2.0) col = outside;

	// moldura dourada dupla
	float m = frame_margin;
	bool inside_corner = (min(dl, dr) < m + 10.0) && (min(dt, db) < m + 10.0);
	if (d >= m && d < m + 1.0) col = ink;
	if (d >= m + 1.0 && d < m + 3.0) col = (d < m + 2.0) ? gold_light : gold;
	if (d >= m + 3.0 && d < m + 4.0) col = ink;
	if (d >= m + 6.0 && d < m + 7.0) col = gold;

	// vinha ondulada entre a borda queimada e a moldura
	float band = m - 5.0;
	float wave = round(2.0 * sin(t * 0.21));
	if (!inside_corner && d > tear && d < m) {
		if (abs(d - (band + wave)) < 0.6) col = vine;
		// folhas alternadas a cada 14 px
		float k = mod(t, 14.0);
		float side = mod(floor(t / 14.0), 2.0) < 1.0 ? 1.0 : -1.0;
		vec2 lp = vec2(k - 7.0, d - (band + wave + side * 2.5));
		if (length(lp * vec2(0.5, 1.0)) < 1.6) col = leaf;
		if (length(lp * vec2(0.5, 1.0)) < 1.6 && lp.y * side > 0.8) col = vine;
	}

	// flores vermelhas nos cantos com miolo dourado
	vec2 cpos = vec2(min(dl, dr), min(dt, db));
	vec2 fc = vec2(m + 1.5, m + 1.5);
	float r = length(cpos - fc);
	if (r < 8.0) col = ink;
	if (r < 7.0) col = flower;
	if (r < 7.0 && mod(atan(cpos.y - fc.y, cpos.x - fc.x) * 5.0 / 3.14159, 2.0) < 0.35) col = vec4(0.5, 0.07, 0.08, 1.0);
	if (r < 3.0) col = gold;
	if (r < 1.5) col = gold_light;
	// folhas ao lado da flor
	vec2 l1 = cpos - (fc + vec2(10.0, -1.0));
	vec2 l2 = cpos - (fc + vec2(-1.0, 10.0));
	if (r >= 8.0 && (length(l1 * vec2(0.6, 1.2)) < 2.6 || length(l2 * vec2(1.2, 0.6)) < 2.6)) col = leaf;

	COLOR = col;
}
