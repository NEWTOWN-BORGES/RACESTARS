// Ondas apenas nas normais: a superfície, a margem e a colisão mantêm a mesma altura.
shader_type spatial;
render_mode specular_schlick_ggx;

global uniform float cinematic_detail;

uniform vec3 deep : source_color = vec3(0.04, 0.20, 0.32);
uniform vec3 shallow : source_color = vec3(0.10, 0.42, 0.50);
uniform vec3 sky_tint : source_color = vec3(0.45, 0.66, 0.82);
uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform float map_size = 24576.0;
uniform float height_cell = 8.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float resolved_wave(float phase, float footprint) {
	return cos(phase) * (1.0 - smoothstep(0.6, 2.6, footprint));
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 footprint = abs(dFdx(p)) + abs(dFdy(p));
	float distance_to_eye = length(VERTEX);
	float swell_fade = 1.0 - smoothstep(700.0, 2600.0, distance_to_eye);
	float ripple_fade = 1.0 - smoothstep(180.0, 950.0, distance_to_eye);
	// Duas ondas coerentes; as ondulações finas só são calculadas nos perfis superiores.
	vec2 g = vec2(0.91, 0.41) * resolved_wave(dot(p, vec2(0.078, 0.035)) - TIME * 0.72,
		dot(footprint, vec2(0.078, 0.035))) * 0.048;
	g += vec2(-0.32, 0.95) * resolved_wave(dot(p, vec2(-0.060, 0.180)) - TIME * 1.05,
		dot(footprint, vec2(0.060, 0.180))) * 0.028;
	g *= swell_fade;
	if (cinematic_detail > 0.5 && ripple_fade > 0.01) {
		g += vec2(0.77, -0.64) * resolved_wave(dot(p, vec2(0.43, -0.36)) - TIME * 1.7,
			dot(footprint, vec2(0.43, 0.36))) * 0.016 * ripple_fade;
		if (cinematic_detail > 0.85) {
			g += vec2(-0.82, -0.57) * resolved_wave(dot(p, vec2(-1.28, -0.90)) - TIME * 2.6,
				dot(footprint, vec2(1.28, 0.90))) * 0.009 * ripple_fade;
		}
	}
	vec3 nw = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	vec2 resolution = vec2(textureSize(heightmap, 0));
	vec2 uv = ((wpos.xz / map_size + vec2(0.5)) * (resolution - vec2(1.0)) + vec2(0.5)) / resolution;
	float depth = max(0.0, wpos.y - texture(heightmap, uv).r * height_cell);
	vec3 c = mix(deep, shallow, exp(-depth * 0.14));
	c = mix(c, sky_tint, 0.025 + fres * 0.58);
	// A espuma segue exclusivamente a profundidade da margem existente.
	float shore_phase = depth * 3.0 - TIME * 0.85;
	float shore_filter = 1.0 - smoothstep(0.8, 3.0, fwidth(depth) * 3.0);
	float shore_wave = sin(shore_phase + g.x * 3.0) * 0.5 + 0.5;
	float breakup = 0.78 + sin(dot(p, vec2(0.12, 0.09)) - TIME * 0.2) * 0.22;
	float foam = (1.0 - smoothstep(0.0, 1.7, depth)) *
		mix(0.24, smoothstep(0.54, 0.92, shore_wave), shore_filter) * breakup;
	c = mix(c, vec3(0.75, 0.84, 0.78), foam * 0.62);
	ALBEDO = c;
	// A rugosidade suaviza os reflexos quando as ondulações já não ocupam um pixel.
	ROUGHNESS = mix(0.19 + (1.0 - ripple_fade) * 0.09, 0.64, foam);
	SPECULAR = mix(0.35, 0.18, foam);
	METALLIC = 0.0;
}
