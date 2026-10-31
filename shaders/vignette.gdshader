shader_type canvas_item;
// Jemna vineta + poskozeni (cervene okraje pri velkem poskozeni).

uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform float pulse = 0.0;

void fragment() {
	vec2 d = UV - vec2(0.5);
	float v = smoothstep(0.35, 0.85, length(d * vec2(1.0, 0.8)));
	vec3 tint = mix(vec3(0.0), vec3(0.6, 0.0, 0.02), damage);
	float a = v * (0.45 + damage * 0.45 * (0.7 + 0.3 * pulse));
	COLOR = vec4(tint, a);
}
