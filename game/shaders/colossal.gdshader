// Estruturas colossais (estátuas, esqueleto, nave, árvores e cristais gigantes): cor dos vértices
// e uma neblina própria, mais leve que a do mundo, para se verem a sair do horizonte a muitos km.
shader_type spatial;
global uniform float cinematic_detail;

uniform vec3 fog_col : source_color = vec3(0.64, 0.75, 0.80);
uniform float fog_start = 900.0;
uniform float fog_span = 15000.0;
uniform float fog_max = 0.86;
uniform vec3 emit_color : source_color = vec3(0.0);
uniform float emit = 0.0;
uniform sampler2D biome_tex : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform float map_size = 6144.0;

varying vec3 world_position;
varying vec3 world_normal;

float monument_hash(vec2 p) {
	vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float monument_noise(vec2 p) {
	vec2 cell = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(monument_hash(cell), monument_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(monument_hash(cell + vec2(0.0, 1.0)), monument_hash(cell + vec2(1.0)), f.x), f.y);
}

vec3 monument_normal(vec3 view_pos, vec3 normal, float height) {
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
	vec3 base = COLOR.rgb;
	float hi = max(base.r, max(base.g, base.b));
	float foliage = smoothstep(0.015, 0.08, base.g - max(base.r, base.b));
	float hull = smoothstep(0.008, 0.04, base.b - base.r) * (1.0 - foliage);
	float mineral_surface = (1.0 - foliage) * (1.0 - hull) * smoothstep(0.10, 0.26, hi);
	// Leave original crystal/rune/lamp surfaces and their emission intact.
	float weatherable = 1.0 - step(0.01, emit);
	float footprint = max(length(dFdx(world_position)), length(dFdy(world_position)));
	float detail = cinematic_detail * (1.0 - smoothstep(0.6, 3.0, footprint)) * weatherable;
	float fine = cinematic_detail * (1.0 - smoothstep(0.06, 0.35, footprint)) * weatherable;
	vec2 p = world_position.xz + world_position.y * vec2(0.57, 0.31);
	float erosion = mix(0.5, monument_noise(p * 0.15), 1.0 - smoothstep(0.6, 3.0, footprint));
	float mineral = mix(0.5, monument_noise(p * 0.028 + vec2(6.1, 3.7)),
		1.0 - smoothstep(3.0, 18.0, footprint));
	vec4 biome = texture(biome_tex, (world_position.xz + vec2(map_size * 0.5)) / map_size);
	float ledge = smoothstep(-0.05, 0.82, normalize(world_normal).y);
	float damp = clamp(biome.g + biome.r * 0.23, 0.0, 1.0);
	float moss = damp * mineral_surface * smoothstep(0.42, 0.77, erosion + ledge * 0.20);
	moss *= (0.18 + ledge * 0.44) * cinematic_detail * weatherable;
	float crack = 0.0;
	float pores = 0.0;
	if (cinematic_detail > 0.45) {
		pores = monument_noise(p * 3.1) - 0.5;
		float fracture = monument_noise(p * 0.38 + erosion * vec2(0.5, 0.7));
		float width = max(fwidth(fracture), 0.003);
		crack = (1.0 - smoothstep(0.005, 0.005 + width, abs(fracture - 0.49)));
		crack *= smoothstep(0.45, 0.73, mineral) * detail * mineral_surface;
	}
	float weathering = cinematic_detail * weatherable;
	vec3 surface = base * (1.0 + (mineral - 0.5) * weathering * 0.17
		+ (erosion - 0.5) * detail * 0.12 - crack * 0.24 + pores * fine * 0.025);
	vec3 moss_color = mix(vec3(0.065, 0.11, 0.045), vec3(0.15, 0.20, 0.07), mineral);
	ALBEDO = mix(surface, moss_color, moss);
	NORMAL = monument_normal(VERTEX, NORMAL,
		(erosion * detail * 0.065 + pores * fine * 0.012 - crack * 0.03) * mineral_surface);
	METALLIC = hull * 0.45 * weatherable;
	ROUGHNESS = mix(0.91, 0.53, hull) + (erosion - 0.5) * detail * 0.065;
	SPECULAR = mix(0.22, 0.42, hull);
	EMISSION = emit_color * emit;
	float f = pow(clamp((length(VERTEX) - fog_start) / fog_span, 0.0, 1.0), 0.8) * fog_max;
	FOG = vec4(fog_col, f);
}
