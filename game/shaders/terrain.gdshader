// Terreno do deserto: areia com ondulações nas partes planas, rocha em camadas nas encostas.
shader_type spatial;
render_mode specular_disabled;
#include "res://shaders/rock_common.gdshaderinc"

uniform vec3 sand_a : source_color = vec3(0.90, 0.76, 0.56);
uniform vec3 sand_b : source_color = vec3(0.82, 0.66, 0.46);
uniform vec3 sand_dark : source_color = vec3(0.66, 0.50, 0.36);
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = r_fbm(p * 0.004);
	float n2 = r_fbm(p * 0.05 + 3.0);
	vec3 sand = mix(sand_a, sand_b, smoothstep(0.3, 0.7, n1));
	sand = mix(sand, sand_dark, smoothstep(0.62, 0.8, n2) * 0.35);
	float rip = sin(p.x * 0.55 + p.y * 0.25 + n1 * 25.0) * 0.5 + 0.5;
	sand *= 0.93 + 0.07 * rip;
	float pebbles = step(0.93, r_noise(p * 1.7)) * 0.12;
	sand *= 1.0 - pebbles;
	float slope = 1.0 - wnrm.y;
	vec3 rock = strata(wpos, wnrm);
	float rk = smoothstep(0.18, 0.38, slope + (n2 - 0.5) * 0.12);
	vec3 c = mix(sand, rock, rk);
	c *= mix(0.55, 1.0, smoothstep(-40.0, 0.0, wpos.y));  // fundo do abismo mais escuro
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
