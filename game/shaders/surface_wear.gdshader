// Marcas suaves em malha conformada ao terreno: funciona também em Compatibility.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = 1.0 - smoothstep(0.3, 1.0, length(p));
	float grain = 0.55 + 0.45 * sin(p.x * 29.0 + sin(p.y * 19.0)) * sin(p.y * 23.0);
	float cracks = pow(0.5 + 0.5 * sin(p.x * 12.0 + sin(p.y * 9.0) * 2.0), 14.0);
	ALBEDO = vec3(0.20, 0.145, 0.085);
	ROUGHNESS = 0.96;
	ALPHA = edge * (0.05 + grain * 0.07 + cracks * 0.10);
}
