shader_type spatial;
render_mode cull_disabled;

void vertex() {
	float phase = INSTANCE_CUSTOM.r * 6.283185 + INSTANCE_CUSTOM.a * 4.0;
	float angle = TIME * (0.072 + INSTANCE_CUSTOM.g * 0.026) + phase;
	float radius = 87.0 + INSTANCE_CUSTOM.g * 76.0;
	VERTEX.y += abs(VERTEX.x) * sin(TIME * 3.5 + phase * 2.0) * 0.28;
	float ca = cos(angle);
	float sa = sin(angle);
	VERTEX.xz = mat2(vec2(-ca, -sa), vec2(sa, -ca)) * VERTEX.xz;
	VERTEX += vec3(ca * radius, INSTANCE_CUSTOM.b * 29.0 + sin(angle * 2.0) * 7.0, sa * radius);
}

void fragment() {
	ALBEDO = vec3(0.13, 0.19, 0.23);
	ROUGHNESS = 1.0;
}
