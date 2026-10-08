// Rochas colossais (agulhas, arcos, anéis, mesas gigantes): os mesmos estratos das rochas,
// com a neblina leve das estruturas colossais (vêem-se de muito longe).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/rock_common.gdshaderinc"

uniform vec3 fog_col : source_color = vec3(0.64, 0.75, 0.80);
uniform float fog_start = 900.0;
uniform float fog_span = 15000.0;
uniform float fog_max = 0.86;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 surface_normal = normalize(wnrm);
	vec4 biome = biome_at(wpos.xz);
	ALBEDO = strata(wpos, surface_normal, biome);
	float detail_fade = rock_detail_fade(wpos, length(VERTEX));
	NORMAL = relief_normal(VERTEX, NORMAL, rock_relief(wpos, surface_normal), detail_fade * 0.85);
	float damp = rock_damp(wpos, surface_normal, biome);
	ROUGHNESS = mix(0.91, 0.56, damp);
	SPECULAR = mix(0.23, 0.38, damp);
	float f = pow(clamp((length(VERTEX) - fog_start) / fog_span, 0.0, 1.0), 0.8) * fog_max;
	FOG = vec4(fog_col, f);
}
