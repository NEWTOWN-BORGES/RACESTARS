// Chama aditiva para Compatibility: brilho próprio sem depender de bloom.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float thrust : hint_range(0.0, 1.5) = 0.0;
uniform float boost : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float longitudinal = clamp(UV.y, 0.0, 1.0);
	float wobble = sin(longitudinal * 22.0 - TIME * 19.0) * 0.012 * longitudinal;
	float radial = abs(UV.x - 0.5 + wobble);
	float radius = mix(0.47, 0.025, pow(longitudinal, 0.72));
	float halo = 1.0 - smoothstep(radius * 0.28, radius, radial);
	float core = 1.0 - smoothstep(radius * 0.05, radius * 0.45, radial);
	float tail = 1.0 - smoothstep(0.6, 1.0, longitudinal);
	float root = smoothstep(0.0, 0.035, longitudinal);
	vec3 outer_color = mix(vec3(1.0, 0.3, 0.06), vec3(0.35, 0.7, 1.0), boost * 0.6);
	vec3 core_color = mix(vec3(1.0, 0.9, 0.6), vec3(0.82, 0.95, 1.0), boost);
	ALBEDO = mix(outer_color, core_color, core);
	ALPHA = halo * tail * root * clamp(thrust, 0.0, 1.0) * 0.75;
}
