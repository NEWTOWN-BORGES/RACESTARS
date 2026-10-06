// Rocha de deserto em camadas (estratos), calculada pela posição no mundo.
uniform vec3 rock_light : source_color = vec3(0.86, 0.72, 0.54);
uniform vec3 rock_mid : source_color = vec3(0.76, 0.56, 0.38);
uniform vec3 rock_red : source_color = vec3(0.64, 0.36, 0.22);
uniform vec3 rock_dark : source_color = vec3(0.42, 0.28, 0.20);
uniform vec3 dust : source_color = vec3(0.88, 0.76, 0.58);

float r_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float r_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(r_hash(i), r_hash(i + vec2(1.0, 0.0)), u.x), mix(r_hash(i + vec2(0.0, 1.0)), r_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float r_fbm(vec2 p) {
	float s = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { s += a * r_noise(p); p *= 2.07; a *= 0.5; }
	return s;
}
vec3 strata(vec3 wp, vec3 n) {
	float warp = r_fbm(wp.xz * 0.008) * 9.0 + r_fbm(wp.xz * 0.05) * 1.5;
	float y = wp.y + warp;
	float band = r_fbm(vec2(y * 0.35, 3.1));
	float big = r_fbm(vec2(y * 0.06, 7.7));
	vec3 c = mix(rock_mid, rock_light, smoothstep(0.35, 0.65, band));
	c = mix(c, rock_red, smoothstep(0.55, 0.75, big) * 0.75);
	c = mix(c, rock_dark, smoothstep(0.62, 0.8, r_fbm(vec2(y * 1.4, 1.3))) * 0.45);
	float side = abs(n.x) > abs(n.z) ? wp.z : wp.x;
	float detail = r_fbm(vec2(side * 0.35, wp.y * 0.9));
	c *= 0.82 + 0.3 * detail;
	c = mix(c, dust, smoothstep(0.65, 0.9, n.y) * 0.85);
	return c;
}
