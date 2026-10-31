shader_type spatial;
// Fasada budovy s nahodne rozsvicenymi okny.

uniform vec3 wall_color : source_color = vec3(0.035, 0.035, 0.045);
uniform float seed = 0.0;
uniform float lit_ratio = 0.3;
uniform vec2 cell = vec2(2.6, 3.4);
uniform float window_energy = 1.2;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.73) * 43758.5453);
}

void fragment() {
	vec3 col = wall_color;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emi = vec3(0.0);
	if (abs(wnorm.y) < 0.5 && wpos.y > 4.0) {
		float u = abs(wnorm.x) > abs(wnorm.z) ? wpos.z : wpos.x;
		vec2 g = vec2(u, wpos.y) / cell;
		vec2 id = floor(g) + floor(wnorm.xz * 2.0) * 31.0;
		vec2 f = fract(g);
		float win = step(0.16, f.x) * step(f.x, 0.84) * step(0.22, f.y) * step(f.y, 0.82);
		if (win > 0.5) {
			col = vec3(0.015, 0.02, 0.03);
			rough = 0.08;
			metal = 0.6;
			if (hash(id) < lit_ratio) {
				float h2 = hash(id * 1.7 + 3.1);
				vec3 c = h2 < 0.55 ? vec3(1.0, 0.72, 0.42) : (h2 < 0.85 ? vec3(0.55, 0.75, 1.0) : vec3(1.0, 0.3, 0.85));
				emi = c * window_energy * (0.4 + hash(id * 2.3) * 1.0);
			}
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emi;
}
