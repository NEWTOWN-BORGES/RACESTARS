// Borrão radial nas bordas da tela + leve vinheta: sensação de velocidade.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;
uniform vec2 center = vec2(0.5, 0.42);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - center;
	float m = smoothstep(0.12, 0.62, length(d * vec2(1.5, 1.0)));
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		float t = float(i) / 5.0;
		acc += textureLod(screen_tex, uv - d * strength * m * t, 0.0).rgb;
	}
	acc /= 6.0;
	acc *= 1.0 - m * strength * 2.2;
	COLOR = vec4(acc, 1.0);
}
