// Céu do deserto: azul profundo no alto, horizonte quente e empoeirado, sol forte,
// fiapos de nuvem alta, uma lua pálida e mesas/serras distantes na neblina.
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.20, 0.40, 0.76);
uniform vec3 mid_sky : source_color = vec3(0.50, 0.68, 0.90);
uniform vec3 horizon : source_color = vec3(0.95, 0.85, 0.71);
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.78);
uniform vec3 cloud_col : source_color = vec3(1.0, 0.97, 0.93);
uniform vec3 ridge_far : source_color = vec3(0.86, 0.73, 0.62);
uniform vec3 ridge_near : source_color = vec3(0.74, 0.55, 0.42);
uniform vec3 moon_dir = vec3(-0.55, 0.42, -0.72);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return s;
}
// silhueta de mesas: patamares planos com encostas íngremes
float mesas(float az, float seed, float base, float amp) {
	float n = vnoise(vec2(az * 9.0 + seed, seed));
	float m = smoothstep(0.42, 0.5, n) * amp;
	return base + m + vnoise(vec2(az * 60.0, seed + 3.0)) * amp * 0.12;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon, mid_sky, smoothstep(-0.02, 0.22, h));
	col = mix(col, zenith, smoothstep(0.22, 0.9, h));

	float cs = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += sun_color * (pow(cs, 4.0) * 0.22 + pow(cs, 60.0) * 0.6);

	// lua pálida de dia
	vec3 md = normalize(moon_dir);
	float cm = dot(d, md);
	float moon = smoothstep(0.99955, 0.99965, cm);
	float crater = vnoise(d.xy * 900.0) * 0.12;
	col = mix(col, vec3(0.93, 0.93, 0.98) - crater, moon * 0.45);

	// nuvens altas finas (cirros)
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.08);
		float n = fbm(uv * vec2(0.5, 2.2) + vec2(4.0, 1.0));
		float c = smoothstep(0.56, 0.78, n) * smoothstep(0.02, 0.15, h) * (1.0 - smoothstep(0.5, 0.95, h));
		col = mix(col, cloud_col + sun_color * pow(cs, 6.0) * 0.3, c * 0.55);
	}

	// mesas e serras distantes, apagadas pela poeira
	float az = atan(d.x, -d.z);
	float r1 = mesas(az, 1.3, 0.012, 0.028) + 0.01 * sin(az * 3.0 + 0.5);
	float r2 = mesas(az, 7.9, 0.004, 0.016);
	vec3 haze = mix(horizon, ridge_far, 0.55) + sun_color * pow(cs, 8.0) * 0.15;
	col = mix(col, haze, smoothstep(0.0015, 0.0, h - r1) * 0.75);
	col = mix(col, mix(ridge_near, horizon, 0.35), smoothstep(0.0015, 0.0, h - r2) * 0.85);
	if (h < 0.0) col = mix(ridge_near, horizon, 0.55);

	float disk = smoothstep(0.9993, 0.9996, cs);
	COLOR = col + disk * sun_color * 3.0;
}
