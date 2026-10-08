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
uniform vec4 water_rects[24];   // centro x, z, meia-largura x, z (rodado por water_rots)
uniform vec4 water_rots[24];    // cos, sen da rotação, altura da água
uniform vec3 sand_a : source_color = vec3(0.82, 0.70, 0.50);
uniform vec3 sand_b : source_color = vec3(0.71, 0.56, 0.37);
uniform vec3 sand_dark : source_color = vec3(0.54, 0.42, 0.31);
uniform vec3 grass_a : source_color = vec3(0.33, 0.49, 0.25);
uniform vec3 grass_b : source_color = vec3(0.56, 0.62, 0.32);
uniform vec3 jungle_a : source_color = vec3(0.14, 0.31, 0.22);
uniform vec3 jungle_b : source_color = vec3(0.29, 0.43, 0.25);
uniform vec3 red_sand : source_color = vec3(0.71, 0.38, 0.24);
uniform vec3 salt : source_color = vec3(0.88, 0.87, 0.79);
uniform vec3 savanna : source_color = vec3(0.65, 0.57, 0.31);
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
	sand = mix(sand, salt, b.a * (1.0 - b.r) * 0.85);   // praias de areia branca e planície de sal
	float detail_fade = 1.0 - smoothstep(60.0, 280.0, length(VERTEX));
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float grain_fade = detail_fade * (1.0 - smoothstep(0.24, 0.75, footprint));
	float rip = sin(p.x * 0.55 + p.y * 0.25 + n1 * 25.0) * 0.5 + 0.5;
	sand *= 1.0 - (1.0 - rip) * 0.045 * detail_fade;
	float grit = r_noise(p * 1.1);
	sand *= 1.0 - smoothstep(0.73, 0.92, grit) * 0.06 * grain_fade;
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.3, 0.7, r_fbm(p * 0.02)));
	grass = mix(grass, savanna, clamp(b.b * 2.5, 0.0, 1.0) * step(0.2, b.r));   // savana: relva dourada
	grass *= 0.93 + 0.09 * (grit - 0.5) * grain_fade;
	vec3 jung = mix(jungle_a, jungle_b, smoothstep(0.3, 0.7, r_fbm(p * 0.03 + 5.0)));
	jung *= 0.93 + 0.09 * (grit - 0.5) * grain_fade;
	float slope = 1.0 - wnrm.y;
	float flat_k = 1.0 - smoothstep(0.14, 0.32, slope);
	float gr = clamp(b.r * 1.4 - 0.25 + (n2 - 0.5) * 0.6, 0.0, 1.0) * flat_k;
	vec3 ground = mix(sand, grass, gr);
	ground = mix(ground, jung, clamp(b.g * 1.3 - 0.15 + (n1 - 0.5) * 0.5, 0.0, 1.0) * flat_k);
	vec3 rock = strata(wpos, wnrm, b);
	float rk = smoothstep(0.2, 0.42, slope + (n2 - 0.5) * 0.12);
	vec3 c = mix(ground, rock, rk);
	// debaixo de água: mais escuro e esverdeado
	float wet = 0.0;
	float shoreline = 0.0;
	for (int i = 0; i < 24; i++) {
		vec4 r = water_rects[i];
		if (r.z < 0.0) break;
		vec2 d = p - r.xy;
		vec2 q = vec2(d.x * water_rots[i].x - d.y * water_rots[i].y, d.x * water_rots[i].y + d.y * water_rots[i].x);
		float inside_water = step(abs(q.x), r.z) * step(abs(q.y), r.w);
		float water_height = water_rots[i].z;
		wet = max(wet, inside_water * (1.0 - smoothstep(water_height - 6.0, water_height + 0.3, wpos.y)));
		shoreline = max(shoreline, inside_water * (1.0 - smoothstep(water_height, water_height + 2.0, wpos.y)));
	}
	c = mix(c, c * vec3(0.55, 0.72, 0.72), wet);
	c *= 1.0 - shoreline * 0.12;
	c *= mix(0.5, 1.0, smoothstep(-46.0, -24.0, wpos.y));   // fundo do abismo
	ALBEDO = c;
	float ground_relief = rip * 0.035 * (1.0 - gr) + grit * 0.02;
	float relief = mix(ground_relief, rock_relief(wpos, wnrm), rk);
	NORMAL = relief_normal(VERTEX, NORMAL, relief, grain_fade * 0.4);
	ROUGHNESS = mix(1.0, 0.74, shoreline);
}
