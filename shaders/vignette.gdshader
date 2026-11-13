shader_type canvas_item;
// Escurece levemente as bordas da tela para dar profundidade.

uniform float strength : hint_range(0.0, 1.0) = 0.35;
uniform float radius : hint_range(0.0, 1.5) = 0.55;
uniform float softness : hint_range(0.01, 1.0) = 0.45;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	uv.x *= 16.0 / 9.0;
	float d = length(uv);
	float a = smoothstep(radius, radius + softness, d) * strength;
	COLOR = vec4(0.05, 0.03, 0.08, a);
}
