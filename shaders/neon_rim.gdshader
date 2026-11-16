shader_type spatial;
render_mode unshaded;
// Svitici neonovy pruh (barva z instance v MultiMeshi).
uniform float energy = 4.0;
varying vec3 tint;

void vertex() {
	tint = COLOR.rgb;
}

void fragment() {
	ALBEDO = tint * energy;
}
