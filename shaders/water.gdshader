shader_type spatial;
// Hladina reky: tmava voda s drobnymi vlnkami, ve kterych se odrazi svetla mesta.

uniform sampler2D ripple : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.02, 0.06, 0.09);
uniform float ripple_scale = 0.035;
uniform float speed = 0.012;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * ripple_scale;
	vec3 n1 = texture(ripple, p + vec2(TIME * speed, TIME * speed * 0.6)).rgb;
	vec3 n2 = texture(ripple, p * 2.3 - vec2(TIME * speed * 1.4, TIME * speed * 0.3)).rgb;
	ALBEDO = deep_color;
	ROUGHNESS = 0.06;
	METALLIC = 0.2;
	SPECULAR = 0.8;
	NORMAL_MAP = mix(n1, n2, 0.5);
	NORMAL_MAP_DEPTH = 0.6;
}
