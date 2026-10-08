// Material das rochas, arcos, pontes, túneis e ruínas: estratos com a cor do bioma.
shader_type spatial;
render_mode specular_disabled;
#include "res://shaders/rock_common.gdshaderinc"

uniform float darken = 1.0;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	ALBEDO = strata(wpos, wnrm, biome_at(wpos.xz)) * darken;
	float detail_fade = 1.0 - smoothstep(100.0, 450.0, length(VERTEX));
	NORMAL = relief_normal(VERTEX, NORMAL, rock_relief(wpos, wnrm), detail_fade * 0.65);
	ROUGHNESS = 1.0;
}
