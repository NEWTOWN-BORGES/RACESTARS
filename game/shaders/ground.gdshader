// Chão infinito: areia com manchas de grama, ondulações de vento e pedrinhas.
// Usa a posição no mundo, então o plano pode seguir o jogador sem "escorregar".
shader_type spatial;
render_mode specular_disabled;

uniform vec3 sand_a : source_color = vec3(0.95, 0.84, 0.64);
uniform vec3 sand_b : source_color = vec3(0.91, 0.74, 0.52);
uniform vec3 grass_a : source_color = vec3(0.62, 0.76, 0.40);
uniform vec3 grass_b : source_color = vec3(0.45, 0.62, 0.36);
uniform vec3 crystal_tint : source_color = vec3(0.80, 0.74, 0.92);
uniform float period = 1500.0;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.07; a *= 0.5; }
	return s;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float big = fbm(p * 0.012);
	float small = fbm(p * 0.09 + 11.0);
	vec3 c = mix(sand_a, sand_b, smoothstep(0.35, 0.7, small));
	float g = smoothstep(0.6, 0.63, big + small * 0.06);
	c = mix(c, mix(grass_b, grass_a, smoothstep(0.3, 0.7, small)), g);
	float rip = sin(p.x * 0.45 + p.y * 0.12 + big * 14.0) * 0.5 + 0.5;
	c *= 0.94 + 0.06 * rip * (1.0 - g);
	// bioma de cristal a cada dois períodos: chão puxa para o lilás
	float d = -wpos.z;
	float k = mod(floor(d / period), 2.0);
	float edge = smoothstep(0.0, 120.0, mod(d, period)) * (1.0 - smoothstep(period - 120.0, period, mod(d, period)));
	c = mix(c, c * crystal_tint * 1.08, k * edge * 0.85);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
