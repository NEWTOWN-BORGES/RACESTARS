shader_type spatial;

varying vec3 world_position;

float grain_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float grain_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(grain_hash(cell), grain_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(grain_hash(cell + vec2(0.0, 1.0)), grain_hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 projection = world_position.xz + world_position.y * vec2(0.71, 0.37);
	float erosion = grain_noise(projection * 0.31);
	float mineral = grain_noise(projection * 0.052);
	float strata = sin(world_position.y * 1.35 + erosion * 1.6);
	float grain = mix(0.86, 1.10, erosion) * mix(0.88, 1.08, mineral);
	grain *= 0.96 + strata * 0.04;
	ALBEDO = COLOR.rgb * grain;
	ROUGHNESS = 0.88 + erosion * 0.10;
	SPECULAR = 0.20;
}
