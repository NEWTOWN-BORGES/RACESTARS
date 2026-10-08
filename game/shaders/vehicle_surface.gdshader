// PBR com cores da Vespa preservadas; metal neutro, pintura e borracha distintos.
shader_type spatial;
render_mode cull_back;
varying vec3 local_pos;
varying float facing_up;

void vertex() {
	local_pos = VERTEX;
	facing_up = (MODEL_NORMAL_MATRIX * NORMAL).y;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float hi = max(base.r, max(base.g, base.b));
	float lo = min(base.r, min(base.g, base.b));
	float metal = (1.0 - smoothstep(0.04, 0.14, hi - lo)) * smoothstep(0.16, 0.38, hi);
	vec3 p = local_pos * 180.0;
	float detail = sin(p.x + sin(p.z)) * sin(p.y * 1.13 + p.z);
	float fade = 1.0 - smoothstep(0.5, 2.5, length(fwidth(p)));
	float dust = smoothstep(0.25, 0.9, facing_up) * 0.035;
	ALBEDO = mix(base * (1.0 + detail * fade * 0.025), vec3(0.5, 0.36, 0.19), dust);
	METALLIC = mix(0.12, 0.85, metal);
	ROUGHNESS = clamp(mix(0.46, 0.28, metal) + (1.0 - smoothstep(0.06, 0.22, hi)) * 0.35 + detail * fade * 0.035, 0.22, 0.9);
	SPECULAR = 0.5;
}
