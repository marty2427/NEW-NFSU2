shader_type canvas_item;
// Radialni rozmazani v rychlosti + rychlostni cary pri nitru. Stred obrazu zustava ostry.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float nitro : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.52);

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - center;
	float dist = length(dir);
	float edge = smoothstep(0.12, 0.7, dist);
	float amount = strength * edge * 0.07;
	vec3 col = vec3(0.0);
	const int SAMPLES = 12;
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1);
		col += textureLod(screen_tex, uv - dir * amount * t, 0.0).rgb;
	}
	col /= float(SAMPLES);

	// Rychlostni cary (nitro)
	if (nitro > 0.0) {
		float ang = atan(dir.y, dir.x);
		float ray = floor(ang * 60.0);
		float h = hash(ray);
		float flow = fract(dist * 2.5 - TIME * (2.0 + h * 2.0) + h);
		float line = step(0.93, h) * smoothstep(0.0, 0.25, flow) * (1.0 - smoothstep(0.25, 0.5, flow));
		col += vec3(0.6, 0.85, 1.0) * line * edge * nitro * 0.35;
	}
	COLOR = vec4(col, 1.0);
}
