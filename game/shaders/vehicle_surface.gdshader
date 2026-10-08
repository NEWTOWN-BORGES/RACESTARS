// A pintura original identifica as peças; o desgaste acompanha o veículo.
shader_type spatial;
render_mode cull_back;
global uniform float cinematic_detail;

varying vec3 local_pos;
varying float facing_up;

float finish_hash(vec2 p) {
	vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float finish_noise(vec2 p) {
	vec2 cell = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(finish_hash(cell), finish_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(finish_hash(cell + vec2(0.0, 1.0)), finish_hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	local_pos = VERTEX;
	facing_up = normalize(MODEL_NORMAL_MATRIX * NORMAL).y;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float hi = max(base.r, max(base.g, base.b));
	float lo = min(base.r, min(base.g, base.b));
	float metal = (1.0 - smoothstep(0.04, 0.14, hi - lo)) * smoothstep(0.16, 0.38, hi);
	float rubber = 1.0 - smoothstep(0.045, 0.16, hi);
	float painted = (1.0 - metal) * (1.0 - rubber);
	float footprint = max(length(dFdx(local_pos)), length(dFdy(local_pos)));
	float wear_fade = cinematic_detail * (1.0 - smoothstep(0.06, 0.30, footprint));
	float fine_fade = cinematic_detail * (1.0 - smoothstep(0.008, 0.045, footprint));
	vec2 p = vec2(local_pos.x + local_pos.y * 0.71, local_pos.z);
	float patina = finish_noise(p * 2.7);
	// Longitudinal residues and fine brushed finish, with no repeating panel grid.
	float streak = finish_noise(p * vec2(8.0, 0.65) + vec2(7.3, 2.1));
	float grime = smoothstep(0.48, 0.86, streak) * (0.035 + 0.055 * (1.0 - facing_up));
	grime *= wear_fade * (1.0 - rubber * 0.65);
	float dust = smoothstep(0.15, 0.85, facing_up) * (0.025 + patina * 0.035) * wear_fade;
	float brush = 0.0;
	float chips = 0.0;
	if (cinematic_detail > 0.45) {
		brush = (finish_noise(p * vec2(115.0, 2.5)) - 0.5) * fine_fade;
		float scuff = finish_noise(p * vec2(35.0, 11.0) + vec2(19.1, 5.7));
		chips = smoothstep(0.76, 0.91, scuff) * smoothstep(0.42, 0.72, patina);
		chips *= painted * fine_fade * 0.32;
	}
	vec3 finish = base * (1.0 + (patina - 0.5) * 0.08 * wear_fade);
	finish = mix(finish, vec3(0.19, 0.20, 0.21), chips);
	finish *= 1.0 - grime;
	ALBEDO = mix(finish, vec3(0.30, 0.23, 0.14), dust);
	METALLIC = clamp(mix(0.08, 0.82, metal) + chips * 0.65 - dust * 0.8, 0.0, 0.88);
	ROUGHNESS = clamp(mix(0.44, 0.30, metal) + rubber * 0.36 + grime * 0.9
		+ dust * 1.4 + (patina - 0.5) * wear_fade * 0.10 + brush * metal * 0.13, 0.25, 0.92);
	SPECULAR = mix(0.48, 0.28, rubber);
	CLEARCOAT = painted * (0.13 - grime * 0.5);
	CLEARCOAT_ROUGHNESS = 0.38;
}
