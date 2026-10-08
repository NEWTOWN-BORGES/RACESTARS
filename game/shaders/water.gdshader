// Água do lago: ondulação animada, cor mais clara de lado (fresnel) e brilho do sol.
shader_type spatial;
render_mode specular_schlick_ggx;

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

vec2 wave_grad(vec2 p, float t) {
	vec2 g = vec2(0.0);
	g += vec2(0.9, 0.4) * cos(dot(p, vec2(0.9, 0.4)) * 0.12 + t * 1.3) * 0.5;
	g += vec2(-0.3, 1.0) * cos(dot(p, vec2(-0.3, 1.0)) * 0.21 + t * 1.9) * 0.35;
	g += vec2(0.7, -0.7) * cos(dot(p, vec2(0.7, -0.7)) * 0.47 + t * 2.7) * 0.2;
	g += vec2(-0.8, -0.5) * cos(dot(p, vec2(-0.8, -0.5)) * 0.93 + t * 3.4) * 0.12;
	return g;
}

void fragment() {
	vec2 g = wave_grad(wpos.xz, TIME);
	float wave_fade = 1.0 - smoothstep(250.0, 2200.0, length(VERTEX));
	vec3 nw = normalize(vec3(-g.x * 0.10 * wave_fade, 1.0, -g.y * 0.10 * wave_fade));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec2 resolution = vec2(textureSize(heightmap, 0));
	vec2 uv = ((wpos.xz / map_size + vec2(0.5)) * (resolution - vec2(1.0)) + vec2(0.5)) / resolution;
	float depth = max(0.0, wpos.y - texture(heightmap, uv).r * height_cell);
	vec3 c = mix(shallow, deep, smoothstep(0.5, 18.0, depth));
	c = mix(c, sky_tint, fres * 0.45);
	float foam = (1.0 - smoothstep(0.0, 1.7, depth)) * smoothstep(0.50, 0.95, sin(depth * 3.0 - TIME + g.x) * 0.5 + 0.5);
	c = mix(c, vec3(0.70, 0.83, 0.77), foam * 0.45);
	ALBEDO = c;
	ROUGHNESS = 0.3;
	SPECULAR = 0.25;
	METALLIC = 0.0;
}
