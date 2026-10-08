// Costa sem leitura do depth buffer: funciona também em Compatibility/Android.
shader_type spatial;
render_mode specular_schlick_ggx;

global uniform float cinematic_detail;

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D sea_mask : filter_linear, repeat_disable;
uniform float map_size = 24576.0;
uniform float height_cell = 8.0;
uniform float sea_y = 0.0;
uniform vec3 deep_color : source_color = vec3(0.025, 0.13, 0.20);
uniform vec3 shelf_color : source_color = vec3(0.07, 0.43, 0.43);
uniform vec3 horizon_color : source_color = vec3(0.50, 0.66, 0.73);
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float resolved_wave(float phase, float footprint) {
	return cos(phase) * (1.0 - smoothstep(0.6, 2.6, footprint));
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 footprint = abs(dFdx(p)) + abs(dFdy(p));
	vec2 uv = world_pos.xz / map_size + vec2(0.5);
	bool inside = all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)));
	float depth = 80.0;
	if (inside) {
		// Preserva túneis e ravinas, mesmo abaixo do nível do mar.
		if (texture(sea_mask, uv).r < 0.5) discard;
		vec2 resolution = vec2(textureSize(heightmap, 0));
		vec2 height_uv = (uv * (resolution - vec2(1.0)) + vec2(0.5)) / resolution;
		depth = max(0.0, sea_y - texture(heightmap, height_uv).r * height_cell);
	}
	float distance_to_eye = length(VERTEX);
	float near_wave = 1.0 - smoothstep(220.0, 1500.0, distance_to_eye);
	float swell_fade = 1.0 - smoothstep(1200.0, 4200.0, distance_to_eye);
	// Ondulação longa em todos os perfis, sem deslocar vértices nem alterar a costa.
	vec2 ripple = vec2(0.92, 0.39) * resolved_wave(dot(p, vec2(0.032, 0.014)) - TIME * 0.58,
		dot(footprint, vec2(0.032, 0.014))) * 0.065 * swell_fade;
	ripple += vec2(-0.43, 0.90) * resolved_wave(dot(p, vec2(-0.041, 0.085)) - TIME * 0.94,
		dot(footprint, vec2(0.041, 0.085))) * 0.035 * swell_fade;
	if (cinematic_detail > 0.5 && near_wave > 0.01) {
		ripple += vec2(0.84, -0.54) * resolved_wave(dot(p, vec2(0.63, -0.40)) - TIME * 1.7,
			dot(footprint, vec2(0.63, 0.40))) * 0.018 * near_wave;
		if (cinematic_detail > 0.85) {
			ripple += vec2(-0.60, -0.80) * resolved_wave(dot(p, vec2(-1.17, -1.56)) - TIME * 2.8,
				dot(footprint, vec2(1.17, 1.56))) * 0.010 * near_wave;
		}
	}
	vec3 normal_world = normalize(vec3(-ripple.x, 1.0, -ripple.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	vec3 water = mix(deep_color, shelf_color, exp(-depth * 0.095));
	water = mix(water, horizon_color, 0.025 + fresnel * 0.72);
	// Faixas de espuma quebradas que seguem a profundidade real da costa.
	float breakup = sin(dot(p, vec2(0.13, 0.09)) - TIME * 0.25);
	if (cinematic_detail > 0.85 && near_wave > 0.01) {
		breakup *= sin(dot(p, vec2(-0.21, 0.31)) + TIME * 0.31);
	}
	float shore_wave = sin(depth * 2.9 - TIME * 1.15 + breakup * 0.8) * 0.5 + 0.5;
	float shore_filter = 1.0 - smoothstep(0.8, 3.0, fwidth(depth) * 2.9);
	float foam_band = mix(0.3, smoothstep(0.53, 0.88, shore_wave), shore_filter);
	float foam = (1.0 - smoothstep(0.15, 2.8, depth)) * foam_band * (0.82 + breakup * 0.18);
	ALBEDO = mix(water, vec3(0.79, 0.88, 0.82), foam * 0.88);
	ROUGHNESS = mix(0.18 + (1.0 - near_wave) * 0.10, 0.7, foam);
	SPECULAR = mix(0.35, 0.18, foam);
	METALLIC = 0.0;
}
