// Estruturas colossais (estátuas, esqueleto, nave, árvores e cristais gigantes): cor dos vértices
// e uma neblina própria, mais leve que a do mundo, para se verem a sair do horizonte a muitos km.
shader_type spatial;
render_mode specular_disabled;

uniform vec3 fog_col : source_color = vec3(0.93, 0.83, 0.70);
uniform float fog_start = 900.0;
uniform float fog_span = 15000.0;
uniform float fog_max = 0.86;
uniform vec3 emit_color : source_color = vec3(0.0);
uniform float emit = 0.0;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	EMISSION = emit_color * emit;
	float f = pow(clamp((length(VERTEX) - fog_start) / fog_span, 0.0, 1.0), 0.8) * fog_max;
	FOG = vec4(fog_col, f);
}
