shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.95, 0.82, 0.56, 0.15);
void vertex() {
	// Billboard com a escala de cada partícula, sem uma textura radial alocada.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}
void fragment() {
	float alpha = 1.0 - smoothstep(0.05, 0.5, length(UV - 0.5));
	ALBEDO = tint.rgb;
	ALPHA = alpha * tint.a * COLOR.a;
}
