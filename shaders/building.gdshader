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

// Vyhlazeny prechod (proti zrneni oken v dalce)
float aastep(float edge, float x) {
	float w = max(fwidth(x) * 0.75, 1e-4);
	return smoothstep(edge - w, edge + w, x);
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
		float win = aastep(0.16, f.x) * (1.0 - aastep(0.84, f.x)) * aastep(0.22, f.y) * (1.0 - aastep(0.82, f.y));
		// V dalce se okna slijou do prumerne barvy misto zrneni
		float far_blend = smoothstep(0.25, 0.8, max(fwidth(g.x), fwidth(g.y)));
		win = mix(win, 0.45, far_blend);
		col = mix(col, vec3(0.015, 0.02, 0.03), win);
		rough = mix(rough, 0.08, win);
		metal = mix(0.0, 0.6, win);
		if (hash(id) < lit_ratio) {
			float h2 = hash(id * 1.7 + 3.1);
			vec3 c = h2 < 0.55 ? vec3(1.0, 0.72, 0.42) : (h2 < 0.85 ? vec3(0.55, 0.75, 1.0) : vec3(1.0, 0.3, 0.85));
			emi = c * window_energy * (0.4 + hash(id * 2.3) * 1.0) * win * (1.0 - far_blend * 0.4);
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emi;
}
