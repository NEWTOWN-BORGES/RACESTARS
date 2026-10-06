// Terreno: a altura vem de uma textura (a malha é uma grelha plana reaproveitada),
// por isso nada é reconstruído durante o jogo (sem engasgos).
// Cores: areia, relva, selva, areia vermelha e calcário conforme o mapa de biomas;
// rocha em camadas nas encostas; mais escuro debaixo de água e no fundo do abismo.
shader_type spatial;
render_mode specular_disabled;
#include "res://shaders/rock_common.gdshaderinc"

uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform float cell = 4.0;
uniform float half_size = 3072.0;
uniform int res = 1537;
uniform float skirt = 30.0;
uniform float water_y = 0.0;
uniform vec3 lake = vec3(0.0, 0.0, -1.0);   // centro x, z e raio do lago
uniform vec3 sand_a : source_color = vec3(0.90, 0.76, 0.56);
uniform vec3 sand_b : source_color = vec3(0.82, 0.66, 0.46);
uniform vec3 sand_dark : source_color = vec3(0.66, 0.50, 0.36);
uniform vec3 grass_a : source_color = vec3(0.45, 0.64, 0.28);
uniform vec3 grass_b : source_color = vec3(0.66, 0.76, 0.34);
uniform vec3 jungle_a : source_color = vec3(0.18, 0.38, 0.19);
uniform vec3 jungle_b : source_color = vec3(0.30, 0.52, 0.25);
uniform vec3 red_sand : source_color = vec3(0.80, 0.47, 0.31);
varying vec3 wpos;
varying vec3 wnrm;

float hgt(ivec2 ij) {
	ij = clamp(ij, ivec2(0), ivec2(res - 1));
	return texelFetch(heightmap, ij, 0).r * cell;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ivec2 ij = ivec2(round((w.xz + vec2(half_size)) / cell));
	int s = int(UV.x + 0.5);
	float h = hgt(ij);
	vec3 n = normalize(vec3(hgt(ij - ivec2(s, 0)) - hgt(ij + ivec2(s, 0)), 2.0 * float(s) * cell,
			hgt(ij - ivec2(0, s)) - hgt(ij + ivec2(0, s))));
	VERTEX.y = h - UV.y * skirt;
	NORMAL = n;
	wpos = vec3(w.x, VERTEX.y, w.z);
	wnrm = n;
}

void fragment() {
	vec2 p = wpos.xz;
	vec4 b = biome_at(p);
	float n1 = r_fbm(p * 0.004);
	float n2 = r_fbm(p * 0.05 + 3.0);
	vec3 sand = mix(sand_a, sand_b, smoothstep(0.3, 0.7, n1));
	sand = mix(sand, sand_dark, smoothstep(0.62, 0.8, n2) * 0.35);
	sand = mix(sand, red_sand, b.b * 0.85);
	sand = mix(sand, vec3(0.90, 0.86, 0.76), b.a * 0.3);
	float rip = sin(p.x * 0.55 + p.y * 0.25 + n1 * 25.0) * 0.5 + 0.5;
	sand *= 0.93 + 0.07 * rip;
	sand *= 1.0 - step(0.93, r_noise(p * 1.7)) * 0.12;
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.3, 0.7, r_fbm(p * 0.02)));
	grass *= 0.88 + 0.22 * r_noise(p * 0.7);
	vec3 jung = mix(jungle_a, jungle_b, smoothstep(0.3, 0.7, r_fbm(p * 0.03 + 5.0)));
	jung *= 0.85 + 0.25 * r_noise(p * 0.5);
	float slope = 1.0 - wnrm.y;
	float flat_k = 1.0 - smoothstep(0.14, 0.32, slope);
	float gr = clamp(b.r * 1.4 - 0.25 + (n2 - 0.5) * 0.6, 0.0, 1.0) * flat_k;
	vec3 ground = mix(sand, grass, gr);
	ground = mix(ground, jung, clamp(b.g * 1.3 - 0.15 + (n1 - 0.5) * 0.5, 0.0, 1.0) * flat_k);
	vec3 rock = strata(wpos, wnrm, b);
	float rk = smoothstep(0.2, 0.42, slope + (n2 - 0.5) * 0.12);
	vec3 c = mix(ground, rock, rk);
	// debaixo de água: mais escuro e esverdeado
	float under = 1.0 - smoothstep(water_y - 6.0, water_y + 0.3, wpos.y);
	c = mix(c, c * vec3(0.45, 0.62, 0.62), under * step(distance(p, lake.xy), lake.z));
	c *= mix(0.5, 1.0, smoothstep(-46.0, -24.0, wpos.y));   // fundo do abismo
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
