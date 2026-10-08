shader_type spatial;
global uniform float cinematic_detail;

// Reuses the existing biome map; an unbound material remains dry stone.
uniform sampler2D biome_tex : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform float map_size = 6144.0;

varying vec3 world_position;
varying vec3 world_normal;

float grain_hash(vec2 p) {
	vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float grain_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(grain_hash(cell), grain_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(grain_hash(cell + vec2(0.0, 1.0)), grain_hash(cell + vec2(1.0)), f.x), f.y);
}

vec3 stone_normal(vec3 view_pos, vec3 normal, float height) {
	vec3 dx = dFdx(view_pos), dy = dFdy(view_pos);
	vec3 rx = cross(dy, normal), ry = cross(normal, dx);
	float determinant = dot(dx, rx);
	vec3 gradient = sign(determinant) * (dFdx(height) * rx + dFdy(height) * ry);
	return normalize(max(abs(determinant), 0.000001) * normal - gradient);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 projection = world_position.xz + world_position.y * vec2(0.71, 0.37);
	float footprint = max(length(dFdx(world_position)), length(dFdy(world_position)));
	float detail = cinematic_detail * (1.0 - smoothstep(0.30, 1.5, footprint));
	float fine = cinematic_detail * (1.0 - smoothstep(0.035, 0.22, footprint));
	float erosion = mix(0.5, grain_noise(projection * 0.24), 1.0 - smoothstep(0.30, 1.5, footprint));
	float mineral = mix(0.5, grain_noise(projection * 0.047 + vec2(4.7, 11.2)),
		1.0 - smoothstep(2.0, 10.0, footprint));
	vec4 biome = texture(biome_tex, (world_position.xz + vec2(map_size * 0.5)) / map_size);
	float humid = clamp(biome.g + biome.r * 0.28, 0.0, 1.0);
	// Patches follow damp biomes and upward ledges; salt and desert stay mineral.
	float ledge = smoothstep(-0.10, 0.80, normalize(world_normal).y);
	float moss = humid * smoothstep(0.41, 0.76, erosion + ledge * 0.19);
	moss *= (0.22 + ledge * 0.46) * cinematic_detail;
	float deposit = smoothstep(0.52, 0.81, mineral) * (0.10 + ledge * 0.10) * cinematic_detail;
	float pores = 0.0;
	float crack = 0.0;
	if (cinematic_detail > 0.45) {
		pores = grain_noise(projection * 4.7) - 0.5;
		float fracture = grain_noise(projection * 0.62 + erosion * vec2(0.6, 0.3));
		float width = max(fwidth(fracture), 0.003);
		crack = (1.0 - smoothstep(0.006, 0.006 + width, abs(fracture - 0.47)));
		crack *= smoothstep(0.48, 0.68, mineral) * detail;
	}
	vec3 stone = COLOR.rgb * (1.0 + (erosion - 0.5) * 0.22 * cinematic_detail);
	stone = mix(stone, stone * vec3(1.12, 1.09, 1.01), deposit);
	stone *= 1.0 - crack * 0.23 + pores * fine * 0.035;
	vec3 moss_color = mix(vec3(0.075, 0.115, 0.045), vec3(0.17, 0.21, 0.08), mineral);
	ALBEDO = mix(stone, moss_color, moss);
	NORMAL = stone_normal(VERTEX, NORMAL, erosion * detail * 0.055 + pores * fine * 0.008 - crack * 0.022);
	ROUGHNESS = clamp(0.87 + erosion * 0.075 + moss * 0.08 - deposit * 0.10, 0.82, 0.98);
	SPECULAR = 0.24;
}
