shader_type spatial;
// Plamen nitra: kuzel z vyfuku. U vyfuku bily/tyrkysovy, dal zelenkavy, spicka do modra.
// Svetle "diamanty" podel plamene a rychle mihotani. Bez textur.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float power = 1.0;
uniform float height = 1.0;
uniform float intensity = 3.0;
uniform float seed = 0.0;
uniform vec3 col_core : source_color = vec3(0.85, 1.0, 0.95);
uniform vec3 col_mid : source_color = vec3(0.25, 1.0, 0.55);
uniform vec3 col_tip : source_color = vec3(0.15, 0.5, 1.0);

varying float t;

void vertex() {
	t = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
	// jemne vlneni spicky
	float w = t * t * 0.03;
	VERTEX.x += sin(TIME * 47.0 + seed + t * 6.0) * w;
	VERTEX.z += cos(TIME * 39.0 + seed * 1.7 + t * 5.0) * w;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float body = pow(facing, 1.8);
	vec3 c = mix(col_core, col_mid, smoothstep(0.0, 0.4, t));
	c = mix(c, col_tip, smoothstep(0.45, 1.0, t));
	float diamonds = 0.72 + 0.28 * sin(t * 24.0 - TIME * 6.0 + seed);
	float flick = 0.82 + 0.18 * sin(TIME * 61.0 + seed + t * 9.0) * sin(TIME * 37.0 + seed * 2.3);
	float fade = 1.0 - smoothstep(0.5, 1.0, t);
	float a = clamp(body * fade * diamonds * flick * power, 0.0, 1.0);
	ALBEDO = c * intensity;
	ALPHA = a;
}
