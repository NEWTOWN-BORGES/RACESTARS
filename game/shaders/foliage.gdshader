// Variação de copa e vento suave em instâncias; troncos e colisões ficam estáveis.
shader_type spatial;
render_mode specular_disabled;

varying vec3 local_pos;
varying float leaf;
varying float tree_tint;

void vertex() {
	local_pos = VERTEX;
	leaf = smoothstep(0.01, 0.10, COLOR.g - COLOR.r * 0.83);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tree_tint = sin(dot(MODEL_MATRIX[3].xz, vec2(0.13, 0.17))) * 0.5 + 0.5;
	float top = smoothstep(1.0, 8.0, VERTEX.y) * leaf;
	float breeze = sin(TIME * 0.85 + world.x * 0.035 + world.z * 0.022);
	// Menos de 20 cm no modelo: perceptível de perto, estável durante a corrida.
	VERTEX.x += top * (breeze * 0.12 + sin(VERTEX.z * 1.7 + VERTEX.y) * 0.065);
	VERTEX.z += top * sin(TIME * 0.7 + world.z * 0.031) * 0.08;
}

void fragment() {
	float mottling = sin(local_pos.x * 2.9 + local_pos.y * 1.7) * sin(local_pos.z * 3.1 - local_pos.y);
	vec3 color = COLOR.rgb;
	vec3 foliage = color * mix(vec3(0.76, 0.84, 0.80), vec3(0.97, 0.91, 0.71), tree_tint);
	foliage *= 0.92 + mottling * 0.075;
	ALBEDO = mix(color * (0.93 + mottling * 0.04), foliage, leaf);
	ROUGHNESS = 0.95;
}
