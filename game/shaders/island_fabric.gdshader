shader_type spatial;
render_mode cull_disabled;

void vertex() {
	float phase = TIME * 1.55 + NODE_POSITION_WORLD.x * 0.07 + VERTEX.x * 3.7;
	float edge = UV.y * UV.y;
	VERTEX.z += (sin(phase) * 0.075 + sin(phase * 1.83) * 0.025) * edge;
}

void fragment() {
	float hem = smoothstep(0.07, 0.095, abs(UV.y - 0.64));
	ALBEDO = COLOR.rgb * mix(1.38, 0.90, hem);
	ROUGHNESS = 0.95;
	BACKLIGHT = COLOR.rgb * 0.20;
}
