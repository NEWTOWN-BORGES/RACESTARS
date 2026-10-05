// Céu pintado: degradê, sol baixo à frente, nuvens estilizadas, planeta anelado
// e cordilheiras distantes no horizonte (ficam "no infinito", nunca se aproximam).
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.24, 0.42, 0.80);
uniform vec3 mid_sky : source_color = vec3(0.58, 0.74, 0.93);
uniform vec3 horizon : source_color = vec3(1.0, 0.86, 0.68);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.72);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 cloud_shade : source_color = vec3(0.80, 0.76, 0.90);
uniform vec3 mountain_far : source_color = vec3(0.86, 0.76, 0.82);
uniform vec3 mountain_near : source_color = vec3(0.74, 0.62, 0.74);
uniform vec3 planet_dir = vec3(-0.62, 0.40, -0.68);
uniform vec3 planet_color : source_color = vec3(0.88, 0.80, 0.95);

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

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon, mid_sky, smoothstep(0.0, 0.2, h));
	col = mix(col, zenith, smoothstep(0.2, 0.8, h));

	// sol
	float cs = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += sun_color * (pow(cs, 5.0) * 0.32 + pow(cs, 48.0) * 0.55);

	// planeta anelado
	vec3 pd = normalize(planet_dir);
	float cp = dot(d, pd);
	vec3 side = normalize(cross(pd, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(side, pd);
	vec2 pl = vec2(dot(d, side), dot(d, up)) / 0.075;
	float pr = length(pl);
	if (cp > 0.0) {
		vec2 rl = mat2(vec2(0.94, -0.34), vec2(0.34, 0.94)) * pl;
		float ring = smoothstep(0.06, 0.0, abs(length(rl * vec2(1.0, 4.2)) - 1.75)) * step(0.0, cp);
		float behind = step(0.0, rl.y) * step(pr, 1.0);
		float body = smoothstep(1.0, 0.97, pr);
		float shade = smoothstep(-0.2, 0.9, dot(normalize(pl + vec2(0.0001)), vec2(0.6, 0.7)) * pr);
		vec3 pc = mix(planet_color * 0.72, planet_color, shade);
		pc = mix(pc, pc * vec3(0.93, 0.9, 1.0), step(0.5, fract(pl.y * 2.2 + pl.x * 0.7)) * 0.5);
		col = mix(col, pc, body * 0.82);
		col = mix(col, planet_color * 1.05, ring * (1.0 - behind) * 0.75);
	}

	// nuvens
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.1) * 0.9;
		float n = fbm(uv + vec2(3.1, 1.7));
		float c = smoothstep(0.5, 0.68, n) * smoothstep(0.0, 0.1, h) * (1.0 - smoothstep(0.45, 0.85, h));
		float sh = fbm(uv * 1.6 + 7.0);
		vec3 cc = mix(cloud_shade, cloud_lit, smoothstep(0.35, 0.65, sh + cs * 0.3));
		cc += sun_color * pow(cs, 6.0) * 0.4;
		col = mix(col, cc, c * 0.92);
	}

	// cordilheiras distantes
	float az = atan(d.x, -d.z);
	float m1 = 0.045 + 0.028 * sin(az * 3.0 + 1.0) + 0.02 * sin(az * 7.0 + 2.3) + 0.009 * sin(az * 19.0 + 0.5) + 0.004 * sin(az * 41.0);
	float m2 = 0.018 + 0.018 * sin(az * 5.0 + 0.4) + 0.011 * sin(az * 13.0 + 1.7) + 0.005 * sin(az * 31.0 + 2.0);
	vec3 mf = mix(mountain_far, horizon, 0.25) + sun_color * pow(cs, 8.0) * 0.25;
	col = mix(col, mf, smoothstep(0.002, 0.0, h - m1) * 0.9);
	col = mix(col, mountain_near + sun_color * pow(cs, 8.0) * 0.2, smoothstep(0.002, 0.0, h - m2) * 0.92);
	if (h < 0.0) col = mix(mountain_near, horizon, 0.5);

	// disco do sol por cima de tudo
	float disk = smoothstep(0.9994, 0.9997, cs);
	COLOR = col + disk * sun_color * 2.5;
}
