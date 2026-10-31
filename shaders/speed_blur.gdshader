shader_type canvas_item;
// Radialni rozmazani v rychlosti - stred obrazu zustava ostry.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.55);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - center;
	float edge = smoothstep(0.15, 0.75, length(dir));
	float amount = strength * edge * 0.06;
	vec3 col = vec3(0.0);
	const int SAMPLES = 10;
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1);
		col += textureLod(screen_tex, uv - dir * amount * t, 0.0).rgb;
	}
	col /= float(SAMPLES);
	COLOR = vec4(col, 1.0);
}
