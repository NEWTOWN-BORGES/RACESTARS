// Material das rochas, arcos, pontes, túneis e ruínas: estratos com a cor do bioma.
shader_type spatial;
render_mode specular_disabled;
#include "res://shaders/rock_common.gdshaderinc"

uniform float darken = 1.0;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = strata(wpos, wnrm, biome_at(wpos.xz)) * darken;
	ROUGHNESS = 1.0;
}
