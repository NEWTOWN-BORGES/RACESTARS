// Rochas colossais (agulhas, arcos, anéis, mesas gigantes): os mesmos estratos das rochas,
// com a neblina leve das estruturas colossais (vêem-se de muito longe).
shader_type spatial;
render_mode specular_disabled;
#include "res://shaders/rock_common.gdshaderinc"

uniform vec3 fog_col : source_color = vec3(0.93, 0.83, 0.70);
uniform float fog_start = 900.0;
uniform float fog_span = 15000.0;
uniform float fog_max = 0.86;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = strata(wpos, wnrm, biome_at(wpos.xz));
	ROUGHNESS = 1.0;
	float f = pow(clamp((length(VERTEX) - fog_start) / fog_span, 0.0, 1.0), 0.8) * fog_max;
	FOG = vec4(fog_col, f);
}
