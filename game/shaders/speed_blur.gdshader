// Borrão radial nas bordas da tela + leve vinheta: sensação de velocidade.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength = 0.0;
uniform float boost = 0.0;
uniform vec2 center = vec2(0.5, 0.42);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - center;
	// Região central de 40% intacta, inclusive durante o boost.
	float m = smoothstep(0.28, 0.68, length(d * vec2(1.5, 1.0)));
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		float t = float(i) / 5.0;
		acc += textureLod(screen_tex, uv - d * strength * m * t, 0.0).rgb;
	}
	acc /= 6.0;
	// Separação cromática subpixel, apenas durante o impulso e nas bordas.
	vec2 offset = d * m * boost * 0.001;
	acc.r += texture(screen_tex, uv + offset).r - texture(screen_tex, uv).r;
	acc.b += texture(screen_tex, uv - offset).b - texture(screen_tex, uv).b;
	acc *= 1.0 - m * strength * 2.2;
	COLOR = vec4(acc, 1.0);
}
