// Atmosfera da ilha: azul oceânico, luz dourada, cirros e um planeta com anéis.
// Tudo é analítico: sem texturas, volumetria ou pós-processamento pesado no Android.
shader_type sky;
render_mode use_debanding;

global uniform float cinematic_detail;

uniform vec3 zenith : source_color = vec3(0.09, 0.23, 0.41);
uniform vec3 mid_sky : source_color = vec3(0.32, 0.52, 0.69);
uniform vec3 horizon : source_color = vec3(0.72, 0.78, 0.79);
uniform vec3 sun_color : source_color = vec3(1.0, 0.78, 0.48);
uniform vec3 cloud_col : source_color = vec3(0.93, 0.91, 0.82);
uniform vec3 planet_color : source_color = vec3(0.75, 0.71, 0.80);
uniform vec3 moon_dir = vec3(-0.55, 0.42, -0.72);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) {
		if (i >= 3 && cinematic_detail < 0.5) { break; }
		if (i >= 4 && cinematic_detail < 0.85) { break; }
		s += a * vnoise(p);
		p = mat2(vec2(1.64, 1.19), vec2(-1.19, 1.64)) * p + vec2(3.7, 7.1);
		a *= 0.5;
	}
	return s;
}
void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon, mid_sky, smoothstep(-0.02, 0.22, h));
	col = mix(col, zenith, smoothstep(0.22, 0.9, h));

	float cs = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += sun_color * (pow(cs, 5.0) * 0.18 + pow(cs, 80.0) * 0.5);

	// Planeta distante: disco sombreado e anéis inclinados. O lado dianteiro dos
	// anéis passa sobre o disco; o resto fica oculto, sem transparência em geometria.
	vec3 md = normalize(moon_dir);
	vec3 right = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(right, md);
	vec2 planet_uv = vec2(dot(d, right), dot(d, up)) / 0.065;
	float facing = step(0.0, dot(d, md));
	float radius = length(planet_uv);
	float planet = (1.0 - smoothstep(0.97, 1.0, radius)) * facing;
	vec2 ring_uv = vec2(planet_uv.x * 0.94 + planet_uv.y * 0.34, -planet_uv.x * 0.34 + planet_uv.y * 0.94);
	float ring_radius = length(vec2(ring_uv.x, ring_uv.y * 3.0));
	float ring = smoothstep(1.24, 1.31, ring_radius) * (1.0 - smoothstep(1.94, 2.02, ring_radius));
	ring *= (0.65 + 0.35 * smoothstep(1.63, 1.67, ring_radius)) * facing;
	vec3 rings = mix(planet_color, cloud_col, 0.55);
	col = mix(col, rings, ring * 0.26 * (1.0 - planet));
	float sphere_z = sqrt(max(0.0, 1.0 - radius * radius));
	float phase = clamp(dot(vec3(planet_uv, sphere_z), normalize(vec3(-0.7, 0.3, 0.8))), 0.0, 1.0);
	float bands = sin(planet_uv.y * 22.0 + planet_uv.x * 4.0) * 0.035;
	col = mix(col, planet_color * (0.64 + phase * 0.4 + bands), planet * 0.58);
	col = mix(col, rings, ring * planet * step(ring_uv.y, 0.0) * 0.4);

	// Bancos de nuvens com volumes largos, sem as faixas paralelas dos antigos cirros.
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.08);
		float n = fbm(uv * vec2(0.64, 0.84) + vec2(4.0, 1.0));
		float c = smoothstep(0.43, 0.70, n) * smoothstep(0.02, 0.15, h) * (1.0 - smoothstep(0.5, 0.95, h));
		vec3 cloud_light = mix(mid_sky * 0.83, cloud_col, smoothstep(0.44, 0.63, n));
		col = mix(col, cloud_light + sun_color * pow(cs, 6.0) * 0.12, c * 0.78);
	}

	// Horizonte marinho aberto: o relevo distante vem da ilha real.
	if (h < 0.0) col = horizon * (1.0 + h * 0.22);

	float disk = smoothstep(0.99972, 0.99984, cs);
	COLOR = col + disk * sun_color * 3.0;
}
