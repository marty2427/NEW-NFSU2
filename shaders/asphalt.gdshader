shader_type spatial;
// Mokry asfalt s kalužemi. Kaluze jsou skoro zrcadlove (odrazy neonu pres SSR).

uniform sampler2D noise_big : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_fine : filter_linear_mipmap, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.05, 0.05, 0.055);
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.42;
uniform float wetness : hint_range(0.0, 1.0) = 0.8;
uniform float scale_big = 0.02;
uniform float scale_fine = 0.35;
uniform float bump_strength = 6.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float big = texture(noise_big, p * scale_big).r;
	float fine = texture(noise_fine, p * scale_fine).r;
	float puddle = smoothstep(1.0 - puddle_amount - 0.04, 1.0 - puddle_amount + 0.04, big);

	vec3 col = base_color * (0.7 + fine * 0.6);
	col = mix(col, col * 0.4, clamp(puddle + wetness * 0.3, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.8, 0.32, wetness), 0.02, puddle);
	SPECULAR = 0.5;
	METALLIC = 0.0;

	// Hrubost povrchu (v kaluzich hladky)
	float e = 0.03;
	float hx = texture(noise_fine, (p + vec2(e, 0.0)) * scale_fine).r - fine;
	float hz = texture(noise_fine, (p + vec2(0.0, e)) * scale_fine).r - fine;
	float b = bump_strength * (1.0 - puddle);
	vec3 n = normalize(vec3(-hx * b, 1.0, -hz * b));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
