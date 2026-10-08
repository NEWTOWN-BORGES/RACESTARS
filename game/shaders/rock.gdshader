// Material das rochas, arcos, pontes, túneis e ruínas: estratos com a cor do bioma.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/rock_common.gdshaderinc"

uniform float darken = 1.0;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 surface_normal = normalize(wnrm);
	vec4 biome = biome_at(wpos.xz);
	ALBEDO = strata(wpos, surface_normal, biome) * darken;
	float detail_fade = rock_detail_fade(wpos, length(VERTEX));
	NORMAL = relief_normal(VERTEX, NORMAL, rock_relief(wpos, surface_normal), detail_fade * 0.85);
	float damp = rock_damp(wpos, surface_normal, biome);
	ROUGHNESS = mix(0.91, 0.56, damp);
	SPECULAR = mix(0.23, 0.38, damp);
}
