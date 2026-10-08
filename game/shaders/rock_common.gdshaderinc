// Rocha em camadas (estratos) calculada pela posição no mundo, com a cor do bioma:
// arenito (deserto), calcário branco (prados e lago), vermelho (fenda final), musgo (selva).
uniform sampler2D biome_tex : filter_linear_mipmap, repeat_disable, hint_default_black;
global uniform float cinematic_detail;
uniform float map_size = 6144.0;
uniform vec3 rock_light : source_color = vec3(0.80, 0.65, 0.45);
uniform vec3 rock_mid : source_color = vec3(0.65, 0.43, 0.27);
uniform vec3 rock_red : source_color = vec3(0.58, 0.31, 0.20);
uniform vec3 rock_dark : source_color = vec3(0.30, 0.25, 0.22);
uniform vec3 dust : source_color = vec3(0.80, 0.68, 0.48);
uniform vec3 limestone : source_color = vec3(0.72, 0.73, 0.67);
uniform vec3 chalk : source_color = vec3(0.88, 0.86, 0.75);
uniform vec3 rock_moss : source_color = vec3(0.20, 0.32, 0.23);

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
	float s = 0.0, a = 0.5, weight = 0.0;
	for (int i = 0; i < 4; i++) {
		// Leve/equilibrado/alto: 2/3/4 oitavas; o perfil leve não avalia as restantes.
		if (i >= 2 && cinematic_detail < 0.5) break;
		if (i >= 3 && cinematic_detail < 0.85) break;
		s += a * r_noise(p);
		weight += a;
		// Rodar cada oitava evita alinhar as grelhas em todas as escalas.
		p = mat2(vec2(1.62, 1.27), vec2(-1.27, 1.62)) * p;
		a *= 0.5;
	}
	return s * (0.9375 / weight);
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

// Projeção suave nas encostas: sem costura quando muda o eixo dominante.
// O perfil leve usa só uma amostra coerente no mundo.
float r_surface_noise(vec3 p, vec3 n) {
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float resolved = 1.0 - smoothstep(0.4, 1.4, footprint);
	if (cinematic_detail < 0.5) {
		return mix(0.5, r_noise(vec2(p.x + p.z * 0.73, p.y + p.z * 0.37)), resolved);
	}
	vec3 weights = pow(abs(n), vec3(4.0));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	float value = r_noise(p.zy) * weights.x + r_noise(p.xz) * weights.y + r_noise(p.xy) * weights.z;
	return mix(0.5, value, resolved);
}

float rock_detail_fade(vec3 wp, float view_distance) {
	float footprint = max(length(dFdx(wp)), length(dFdy(wp)));
	return (1.0 - smoothstep(90.0, 480.0, view_distance)) * (1.0 - smoothstep(0.5, 2.5, footprint));
}

float rock_relief(vec3 wp, vec3 n) {
	float phase = wp.y * 0.85 + r_noise(wp.xz * 0.032) * 4.0;
	float ripple = sin(phase) * (1.0 - smoothstep(0.4, 1.8, fwidth(phase)));
	float relief = r_surface_noise(wp * vec3(0.16, 0.32, 0.16), n) * 0.60 + ripple * 0.16;
	if (cinematic_detail > 0.85) {
		float footprint = max(length(dFdx(wp)), length(dFdy(wp)));
		relief += (r_surface_noise(wp * 1.15, n) - 0.5) * 0.055 * (1.0 - smoothstep(0.18, 0.7, footprint));
	}
	return relief;
}

// Humidade contextual: a selva conserva água nas superfícies expostas e baixas.
float rock_damp(vec3 wp, vec3 n, vec4 b) {
	return b.g * (0.35 + 0.65 * smoothstep(-0.2, 0.75, n.y)) * (1.0 - smoothstep(80.0, 520.0, wp.y) * 0.55);
}

vec3 strata(vec3 wp, vec3 n, vec4 b) {
	float warp = r_fbm(wp.xz * 0.008) * 14.0 + r_noise(wp.xz * 0.035) * 2.7;
	float y = wp.y + warp + dot(wp.xz, vec2(0.006, 0.003));
	float band = r_noise(vec2(y * 0.17, 3.1));
	float big = r_noise(vec2(y * 0.026, 7.7));
	band = mix(0.5, band, 1.0 - smoothstep(0.4, 1.4, fwidth(y * 0.17)));
	big = mix(0.5, big, 1.0 - smoothstep(0.4, 1.4, fwidth(y * 0.026)));
	float phase = y * 0.24 + big * 1.8;
	float seam = (1.0 - smoothstep(0.06, 0.24, abs(sin(phase)))) * (1.0 - smoothstep(0.25, 1.25, fwidth(phase)));
	float detail = r_surface_noise(wp * vec3(0.027, 0.085, 0.027), n);
	float runoff = r_surface_noise(wp * vec3(0.085, 0.012, 0.085), n);
	float dk = seam * mix(0.08, 0.28, detail);
	if (cinematic_detail > 0.5) {
		float fine = r_noise(vec2(y * 0.74, 9.2)) - 0.5;
		band += fine * 0.20 * (1.0 - smoothstep(0.4, 1.4, fwidth(y * 0.74)));
	}
	vec3 c = mix(rock_mid, rock_light, smoothstep(0.2, 0.8, band));
	c = mix(c, rock_red, smoothstep(0.53, 0.83, big) * 0.62);
	c = mix(c, rock_dark, dk);
	// calcário branco/creme (como as falésias das imagens)
	vec3 lime = mix(limestone, chalk, smoothstep(0.2, 0.8, band));
	lime = mix(lime, dust, smoothstep(0.6, 0.8, big) * 0.24);
	lime = mix(lime, rock_dark, dk * 0.65);
	c = mix(c, lime, b.a);
	// Óxido de ferro: vermelho terroso, sem saturar as faces iluminadas.
	vec3 redr = mix(rock_red, rock_mid * vec3(1.16, 0.85, 0.72), smoothstep(0.2, 0.8, band));
	redr = mix(redr, rock_dark, dk);
	c = mix(c, redr, b.b);
	float erosion = smoothstep(0.22, 0.78, detail);
	c *= 0.79 + 0.32 * erosion;
	c = mix(c, c * vec3(0.72, 0.70, 0.66), smoothstep(0.58, 0.86, runoff) * (1.0 - smoothstep(0.35, 0.85, n.y)) * 0.42);
	// em cima: pó, relva ou musgo conforme o bioma
	vec3 top = mix(dust, rock_moss * 1.35, clamp(b.r * 1.2, 0.0, 1.0));
	top = mix(top, rock_moss, b.g);
	c = mix(c, top, smoothstep(0.65, 0.9, n.y) * 0.72);
	// Musgo só no bioma húmido, nos patamares e canais de escorrência.
	float moss = b.g * smoothstep(0.40, 0.72, detail + runoff * 0.16) * (0.35 + 0.65 * smoothstep(-0.1, 0.85, n.y));
	c = mix(c, rock_moss * mix(0.78, 1.16, runoff), moss * 0.75);
	c *= 1.0 - rock_damp(wp, n, b) * 0.12;
	return c;
}
