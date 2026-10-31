shader_type spatial;
// Mokry asfalt mesta s vodorovnym znacenim (car y, prechody) a parkovistem.
// Znaceni se pocita ze souradnic, takze je cela zem jeden objekt.

uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D asphalt_rough : hint_roughness_gray, filter_linear_mipmap, repeat_enable;
uniform sampler2D puddle_noise : filter_linear_mipmap, repeat_enable;

uniform float tex_scale = 0.12;          // opakovani textury asfaltu (1/m)
uniform float brightness = 0.55;         // jas asfaltu
uniform float wetness : hint_range(0.0, 1.0) = 0.85;
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.38;

// Mrizka ulic
uniform float grid = 90.0;               // vzdalenost os ulic
uniform float road_half = 8.0;           // polovina sirky vozovky
uniform vec4 city_rect = vec4(-180.0, -180.0, 180.0, 180.0); // xmin, zmin, xmax, zmax (osy krajnich ulic)
// Parkoviste
uniform vec4 lot_rect = vec4(230.0, -110.0, 450.0, 110.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float band(float x, float center, float half_width) {
	float w = fwidth(x) * 0.75 + 1e-4;
	return 1.0 - smoothstep(half_width - w, half_width + w, abs(x - center));
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 uv = p * tex_scale;
	vec3 albedo = texture(asphalt_albedo, uv).rgb * brightness;
	float rough = texture(asphalt_rough, uv).r;
	vec3 nmap = texture(asphalt_normal, uv).rgb;

	// --- Vodorovne znaceni ---
	float white = 0.0;
	float yellow = 0.0;
	bool in_city = p.x > city_rect.x - road_half - 1.0 && p.x < city_rect.z + road_half + 1.0
		&& p.y > city_rect.y - road_half - 1.0 && p.y < city_rect.w + road_half + 1.0;
	if (in_city) {
		vec2 off = (fract(p / grid + 0.5) - 0.5) * grid; // vzdalenost od nejblizsi osy ulice
		vec2 a = abs(off);
		bool road_x = a.x < road_half; // ulice ve smeru Z
		bool road_z = a.y < road_half; // ulice ve smeru X
		float cross_zone = road_half + 4.5;
		// Ulice ve smeru Z
		if (road_x && a.y > cross_zone) {
			yellow += band(a.x, 0.18, 0.07);
			white += band(a.x, road_half * 0.5, 0.07) * step(0.5, fract(p.y / 7.0));
			white += band(a.x, road_half - 0.45, 0.08);
		}
		// Ulice ve smeru X
		if (road_z && a.x > cross_zone) {
			yellow += band(a.y, 0.18, 0.07);
			white += band(a.y, road_half * 0.5, 0.07) * step(0.5, fract(p.x / 7.0));
			white += band(a.y, road_half - 0.45, 0.08);
		}
		// Prechody pro chodce kolem krizovatek
		if (road_x && a.y > road_half + 0.8 && a.y < road_half + 3.8) {
			white += step(0.5, fract(off.x / 1.4)) * step(a.x, road_half - 0.8);
		}
		if (road_z && a.x > road_half + 0.8 && a.x < road_half + 3.8) {
			white += step(0.5, fract(off.y / 1.4)) * step(a.y, road_half - 0.8);
		}
		// Stopcary
		if (road_x && off.x * sign(off.y) < 0.0) {
			white += band(a.y, road_half + 4.3, 0.22) * step(a.x, road_half - 0.6) * step(0.3, a.x);
		}
		if (road_z && off.y * sign(-off.x) < 0.0) {
			white += band(a.x, road_half + 4.3, 0.22) * step(a.y, road_half - 0.6) * step(0.3, a.y);
		}
	}
	// Parkoviste: stani
	if (p.x > lot_rect.x && p.x < lot_rect.z && p.y > lot_rect.y && p.y < lot_rect.w) {
		vec2 lp = p - lot_rect.xy;
		float row = mod(lp.y, 40.0);
		float stall = band(fract(lp.x / 3.0) * 3.0, 0.0, 0.07) + band(fract(lp.x / 3.0) * 3.0, 3.0, 0.07);
		if ((row > 2.0 && row < 8.0) || (row > 32.0 && row < 38.0)) {
			white += stall;
		}
		white += band(row, 8.0, 0.08) + band(row, 32.0, 0.08);
		// Sipky / okraj
		white += band(lp.x, 2.0, 0.12) + band(lp.x, lot_rect.z - lot_rect.x - 2.0, 0.12);
	}
	white = clamp(white, 0.0, 1.0);
	yellow = clamp(yellow, 0.0, 1.0);
	float paint = max(white, yellow);
	albedo = mix(albedo, vec3(0.75, 0.75, 0.72), white);
	albedo = mix(albedo, vec3(0.85, 0.6, 0.08), yellow);

	// --- Mokro a kaluze ---
	float n = texture(puddle_noise, p * 0.018).r;
	float n2 = texture(puddle_noise, p * 0.07 + vec2(13.0, 7.0)).r;
	float puddle = smoothstep(1.0 - puddle_amount - 0.05, 1.0 - puddle_amount + 0.05, n * 0.75 + n2 * 0.25);
	puddle *= 1.0 - paint * 0.6;
	float wet = clamp(wetness + puddle, 0.0, 1.0);
	albedo *= mix(1.0, 0.55, wet);           // mokry povrch je tmavsi
	rough = mix(rough, rough * 0.35, wetness);
	rough = mix(rough, 0.03, puddle);
	rough = mix(rough, max(rough, 0.35), paint * (1.0 - puddle));

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	SPECULAR = 0.5;
	// V kalužích je povrch hladky
	NORMAL_MAP = mix(nmap, vec3(0.5, 0.5, 1.0), clamp(puddle + paint * 0.5, 0.0, 1.0));
	NORMAL_MAP_DEPTH = 1.0;
}
