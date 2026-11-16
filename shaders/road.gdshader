shader_type spatial;
// Mokry asfalt ulic s vodorovnym znacenim. Znaceni se kresli podle UV:
//   UV.x  = vzdalenost od osy ulice (m, zaporna vlevo), UV.y = vzdalenost podel ulice (m)
//   UV2.x = vzdalenost od zacatku ulice, UV2.y = delka ulice
//   COLOR.r = polovina sirky ulice / 32, COLOR.g = 1 kdyz se ma kreslit znaceni (0 = krizovatka, plocha)

uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_rough : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D puddle_noise : filter_linear_mipmap, repeat_enable;

uniform float tex_scale = 0.12;
uniform float brightness = 0.55;
uniform float wetness : hint_range(0.0, 1.0) = 0.85;
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.38;

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

	float white = 0.0;
	float yellow = 0.0;
	if (COLOR.g > 0.5) {
		float half_w = COLOR.r * 32.0;
		float lat = UV.x;
		float a = abs(lat);
		float along = UV.y;
		float to_end = min(UV2.x, UV2.y - UV2.x);
		if (to_end > 6.0) {
			// Dvojita zluta uprostred, prerusovane pruhy, plne krajnice
			yellow += band(a, 0.2, 0.07);
			float dashes = step(0.5, fract(along / 8.0));
			if (half_w > 9.5) {
				white += band(a, half_w * 0.36, 0.07) * dashes;
				white += band(a, half_w * 0.68, 0.07) * dashes;
			} else if (half_w > 7.0) {
				white += band(a, half_w * 0.5, 0.07) * dashes;
			}
			white += band(a, half_w - 0.45, 0.08);
		} else if (to_end > 1.2 && to_end < 4.4) {
			// Prechod pro chodce u krizovatky
			white += step(0.5, fract(lat / 1.4 + 0.25)) * step(a, half_w - 0.6);
		} else if (to_end > 5.0 && to_end < 5.45) {
			white += step(a, half_w - 0.5);   // stopcara
		}
	}
	white = clamp(white, 0.0, 1.0);
	yellow = clamp(yellow, 0.0, 1.0);
	float paint = max(white, yellow);
	albedo = mix(albedo, vec3(0.75, 0.75, 0.72), white);
	albedo = mix(albedo, vec3(0.85, 0.6, 0.08), yellow);

	// Mokro a kaluze
	float n = texture(puddle_noise, p * 0.018).r;
	float n2 = texture(puddle_noise, p * 0.07 + vec2(13.0, 7.0)).r;
	float puddle = smoothstep(1.0 - puddle_amount - 0.05, 1.0 - puddle_amount + 0.05, n * 0.75 + n2 * 0.25);
	puddle *= 1.0 - paint * 0.6;
	float wet = clamp(wetness + puddle, 0.0, 1.0);
	albedo *= mix(1.0, 0.55, wet);
	rough = mix(rough, rough * 0.35, wetness);
	rough = mix(rough, 0.03, puddle * wetness);
	rough = mix(rough, max(rough, 0.35), paint * (1.0 - puddle));

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	SPECULAR = 0.5;
	NORMAL_MAP = mix(nmap, vec3(0.5, 0.5, 1.0), clamp(puddle + paint * 0.5, 0.0, 1.0));
	NORMAL_MAP_DEPTH = 1.0;
}
