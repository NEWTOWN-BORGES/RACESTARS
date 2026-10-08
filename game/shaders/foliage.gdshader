// Variação de copa e vento suave em instâncias; troncos e colisões ficam estáveis.
shader_type spatial;
render_mode specular_disabled;

global uniform float cinematic_detail;

varying vec3 local_pos;
varying float leaf;
varying float tree_tint;
varying float canopy_height;

void vertex() {
	local_pos = VERTEX;
	leaf = smoothstep(0.01, 0.10, COLOR.g - COLOR.r * 0.83);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tree_tint = sin(dot(MODEL_MATRIX[3].xz, vec2(0.13, 0.17))) * 0.5 + 0.5;
	canopy_height = smoothstep(0.5, 9.0, VERTEX.y);
	float top = smoothstep(1.0, 8.0, VERTEX.y) * leaf;
	float breeze = sin(TIME * 0.72 + world.x * 0.025 + world.z * 0.017);
	float sway = sin(TIME * 1.1 + world.z * 0.031 + tree_tint * 3.0);
	// Menos de 20 cm no modelo: perceptível de perto, estável durante a corrida.
	VERTEX.x += top * (breeze * 0.12 + sway * 0.035);
	VERTEX.z += top * (breeze * 0.055 - sway * 0.045);
	if (cinematic_detail > 0.85) {
		float flutter = sin(TIME * 2.4 + local_pos.z * 1.7 + local_pos.y + tree_tint * 6.0);
		VERTEX.x += top * flutter * 0.018;
	}
}

void fragment() {
	float mottling = 0.0;
	float footprint = length(fwidth(local_pos));
	// O detalhe desaparece antes de ocupar menos de um pixel; o perfil móvel evita estes senos.
	if (cinematic_detail > 0.5 && footprint < 1.0) {
		mottling = sin(local_pos.x * 2.9 + local_pos.y * 1.7) * sin(local_pos.z * 3.1 - local_pos.y);
		mottling *= 1.0 - smoothstep(0.18, 0.85, footprint);
	}
	vec3 color = COLOR.rgb;
	vec3 foliage = color * mix(vec3(0.72, 0.87, 0.76), vec3(0.98, 0.93, 0.71), tree_tint);
	foliage *= 0.88 + canopy_height * 0.14 + mottling * 0.065;
	ALBEDO = mix(color * (0.94 + mottling * 0.025), foliage, leaf);
	ROUGHNESS = 0.92;
	// A translucidez usa as luzes e sombras da cena, sem emissão artificial.
	BACKLIGHT = foliage * leaf * (0.12 + canopy_height * 0.09);
}
