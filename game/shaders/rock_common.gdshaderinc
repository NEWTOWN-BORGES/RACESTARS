// Rocha em camadas (estratos) calculada pela posição no mundo, com a cor do bioma:
// arenito (deserto), calcário branco (prados e lago), vermelho (fenda final), musgo (selva).
uniform sampler2D biome_tex : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform float map_size = 6144.0;
uniform vec3 rock_light : source_color = vec3(0.80, 0.66, 0.46);
uniform vec3 rock_mid : source_color = vec3(0.64, 0.43, 0.28);
uniform vec3 rock_red : source_color = vec3(0.57, 0.29, 0.18);
uniform vec3 rock_dark : source_color = vec3(0.29, 0.24, 0.23);
uniform vec3 dust : source_color = vec3(0.79, 0.67, 0.46);
uniform vec3 limestone : source_color = vec3(0.72, 0.73, 0.67);
uniform vec3 chalk : source_color = vec3(0.88, 0.86, 0.75);
uniform vec3 rock_moss : source_color = vec3(0.24, 0.36, 0.23);

// Hash sem seno nem multiplicadores enormes: evita perder precisão nos km da ilha.
float r_hash(vec2 p) {
	vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
float r_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(r_hash(i), r_hash(i + vec2(1.0, 0.0)), u.x), mix(r_hash(i + vec2(0.0, 1.0)), r_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float r_fbm(vec2 p) {
	float s = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * r_noise(p);
		// Rodar cada oitava evita alinhar as grelhas em todas as escalas.
		p = mat2(vec2(1.62, 1.27), vec2(-1.27, 1.62)) * p;
		a *= 0.5;
	}
	return s;
}
// R = relva, G = selva/musgo, B = rocha vermelha, A = calcário branco
vec4 biome_at(vec2 xz) {
	return texture(biome_tex, (xz + vec2(map_size * 0.5)) / map_size);
}
// Relevo superficial sem texturas ou malhas extra. As derivadas mantêm os detalhes
// presos à superfície; a distância reduz o grão para evitar cintilação a alta velocidade.
vec3 relief_normal(vec3 view_pos, vec3 normal, float relief, float strength) {
	vec3 dx = dFdx(view_pos);
	vec3 dy = dFdy(view_pos);
	vec3 rx = cross(dy, normal);
	vec3 ry = cross(normal, dx);
	float determinant = dot(dx, rx);
	vec3 gradient = sign(determinant) * (dFdx(relief) * rx + dFdy(relief) * ry);
	return normalize(max(abs(determinant), 0.000001) * normal - gradient * strength);
}

float rock_relief(vec3 wp, vec3 n) {
	float side = abs(n.x) > abs(n.z) ? wp.z : wp.x;
	float ripple = sin(wp.y * 0.85 + r_noise(wp.xz * 0.032) * 4.0);
	return r_noise(vec2(side * 0.16, wp.y * 0.32)) * 0.55 + ripple * 0.12;
}

vec3 strata(vec3 wp, vec3 n, vec4 b) {
	float warp = r_fbm(wp.xz * 0.008) * 11.0 + r_noise(wp.xz * 0.05) * 1.5;
	float y = wp.y + warp;
	float band = r_noise(vec2(y * 0.19, 3.1));
	float big = r_noise(vec2(y * 0.035, 7.7));
	float seam = 1.0 - smoothstep(0.035, 0.12, abs(sin(y * 0.31)));
	float dk = seam * 0.17;
	vec3 c = mix(rock_mid, rock_light, smoothstep(0.2, 0.8, band));
	c = mix(c, rock_red, smoothstep(0.53, 0.83, big) * 0.55);
	c = mix(c, rock_dark, dk);
	// calcário branco/creme (como as falésias das imagens)
	vec3 lime = mix(limestone, chalk, smoothstep(0.2, 0.8, band));
	lime = mix(lime, dust, smoothstep(0.6, 0.8, big) * 0.24);
	lime = mix(lime, rock_dark, dk * 0.65);
	c = mix(c, lime, b.a);
	// vermelho vivo
	vec3 redr = mix(rock_red, rock_mid * vec3(1.16, 0.85, 0.72), smoothstep(0.2, 0.8, band));
	redr = mix(redr, rock_dark, dk);
	c = mix(c, redr, b.b);
	float side = abs(n.x) > abs(n.z) ? wp.z : wp.x;
	float detail = r_noise(vec2(side * 0.045, wp.y * 0.13));
	float erosion = smoothstep(0.22, 0.78, detail);
	c *= 0.83 + 0.24 * erosion;
	// em cima: pó, relva ou musgo conforme o bioma
	vec3 top = mix(dust, rock_moss * 1.35, clamp(b.r * 1.2, 0.0, 1.0));
	top = mix(top, rock_moss, b.g);
	c = mix(c, top, smoothstep(0.65, 0.9, n.y) * 0.72);
	// musgo a escorrer na selva
	c = mix(c, rock_moss, b.g * smoothstep(0.38, 0.78, detail) * 0.55);
	return c;
}
