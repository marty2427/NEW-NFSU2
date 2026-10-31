shader_type spatial;
// Fasada budovy: textura (beton, cihly, oblozeni), okna s nahodne rozsvicenymi
// mistnostmi a v prizemi osvetlene vylohy obchodu.

uniform sampler2D wall_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wall_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 wall_tint : source_color = vec3(1.0);
uniform float wall_scale = 0.25;         // opakovani textury (1/m)
uniform float seed = 0.0;
uniform float lit_ratio = 0.35;
uniform vec2 cell = vec2(3.2, 3.6);      // rozestup oken (sirka, vyska patra)
uniform float window_energy = 1.3;
uniform float shop_height = 4.6;         // vyska prizemi s vylohami
uniform float shop_energy = 1.3;
uniform vec3 shop_color : source_color = vec3(1.0, 0.8, 0.55);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.73) * 43758.5453);
}

float aastep(float edge, float x) {
	float w = max(fwidth(x) * 0.75, 1e-4);
	return smoothstep(edge - w, edge + w, x);
}

void fragment() {
	bool side = abs(wnorm.y) < 0.5;
	float u = abs(wnorm.x) > abs(wnorm.z) ? wpos.z : wpos.x;
	vec2 tuv = side ? vec2(u, wpos.y) * wall_scale : wpos.xz * wall_scale;
	vec3 col = texture(wall_albedo, tuv).rgb * wall_tint;
	vec3 nm = texture(wall_normal, tuv).rgb;
	float rough = 0.8;
	float metal = 0.0;
	vec3 emi = vec3(0.0);

	if (side) {
		float y = wpos.y;
		vec2 face_id = floor(wnorm.xz * 2.0 + 0.5) * 31.0;
		if (y > shop_height + 0.6) {
			// Okna v patrech
			vec2 g = vec2(u, y - shop_height) / cell;
			vec2 id = floor(g) + face_id;
			vec2 f = fract(g);
			float win = aastep(0.18, f.x) * (1.0 - aastep(0.82, f.x)) * aastep(0.2, f.y) * (1.0 - aastep(0.78, f.y));
			float far_blend = smoothstep(0.3, 0.9, max(fwidth(g.x), fwidth(g.y)));
			win = mix(win, 0.4, far_blend);
			col = mix(col, vec3(0.02, 0.025, 0.035), win);
			rough = mix(rough, 0.06, win);
			metal = mix(0.0, 0.7, win);
			nm = mix(nm, vec3(0.5, 0.5, 1.0), win);
			if (hash(id) < lit_ratio) {
				float h2 = hash(id * 1.7 + 3.1);
				vec3 c = h2 < 0.55 ? vec3(1.0, 0.72, 0.42) : (h2 < 0.85 ? vec3(0.6, 0.8, 1.0) : vec3(1.0, 0.35, 0.85));
				emi = c * window_energy * (0.35 + hash(id * 2.3)) * win * (1.0 - far_blend * 0.3);
			}
		} else if (y > 0.4 && y < shop_height) {
			// Vylohy obchodu v prizemi
			float seg = u / 7.0;
			vec2 id = vec2(floor(seg), 0.0) + face_id;
			float f = fract(seg);
			float glass = aastep(0.06, f) * (1.0 - aastep(0.94, f)) * aastep(0.5, y) * (1.0 - aastep(shop_height - 0.9, y));
			float open = step(0.25, hash(id + 5.0));
			col = mix(col, vec3(0.02), glass);
			rough = mix(rough, 0.05, glass);
			metal = mix(metal, 0.5, glass);
			nm = mix(nm, vec3(0.5, 0.5, 1.0), glass);
			float h3 = hash(id + 9.0);
			vec3 c = h3 < 0.5 ? shop_color : (h3 < 0.75 ? vec3(0.7, 0.9, 1.0) : vec3(1.0, 0.5, 0.75));
			// Interier: svetlejsi nahore, police/regaly naznacene pruhy
			float shelves = 0.75 + 0.25 * step(0.5, fract(y * 1.3));
			emi += c * shop_energy * glass * open * shelves * (0.6 + 0.4 * smoothstep(0.5, shop_height, y));
			// Svitici pruh nad vylohou
			float strip = aastep(shop_height - 0.75, y) * (1.0 - aastep(shop_height - 0.55, y));
			emi += c * shop_energy * 1.5 * strip * open;
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emi;
	NORMAL_MAP = nm;
}
