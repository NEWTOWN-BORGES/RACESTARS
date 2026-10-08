// Costa sem leitura do depth buffer: funciona também em Compatibility/Android.
shader_type spatial;
render_mode specular_schlick_ggx;

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

void fragment() {
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
	vec2 p = world_pos.xz;
	float distance_to_eye = length(VERTEX);
	float near_wave = 1.0 - smoothstep(250.0, 1600.0, distance_to_eye);
	float swell_fade = 1.0 - smoothstep(700.0, 2800.0, distance_to_eye);
	float cross_wave = sin(dot(p, vec2(-0.012, 0.018)) + TIME * 0.4);
	vec2 ripple = vec2(0.85, 0.4) * cos(dot(p, vec2(0.032, 0.014)) + cross_wave + TIME * 0.7) * 0.045 * swell_fade;
	ripple += vec2(-0.3, 0.9) * cos(dot(p, vec2(-0.041, 0.085)) + TIME * 1.1) * 0.026 * near_wave;
	ripple += vec2(0.7, -0.5) * cos(dot(p, vec2(0.63, -0.4)) + TIME * 1.7) * 0.018 * near_wave;
	vec3 normal_world = normalize(vec3(-ripple.x, 1.0, -ripple.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 water = mix(shelf_color, deep_color, smoothstep(0.8, 28.0, depth));
	water = mix(water, horizon_color, fresnel * 0.74);
	// Faixas de espuma quebradas que seguem a profundidade real da costa.
	float breakup = sin(p.x * 0.16 + sin(p.y * 0.12)) * sin(p.y * 0.23 - TIME * 0.35);
	float shore_wave = sin(depth * 2.9 - TIME * 1.25 + breakup * 0.9) * 0.5 + 0.5;
	float foam = (1.0 - smoothstep(0.15, 2.8, depth)) * smoothstep(0.57, 0.88, shore_wave);
	foam *= mix(0.65, 1.0, near_wave);
	ALBEDO = mix(water, vec3(0.73, 0.88, 0.83), foam * 0.85);
	ROUGHNESS = mix(0.24, 0.68, foam);
	SPECULAR = 0.45;
}
