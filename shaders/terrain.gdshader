shader_type spatial;
// Teren: plochou mrizku zveda podle vyskove mapy. Ve meste dlazba, mimo mesto trava a na strmych svazich skala.

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform sampler2D pavement : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec2 origin;
uniform float cell = 16.0;
uniform vec2 grid;

varying vec3 world_pos;
varying vec3 world_normal;
varying float city;

float height_at(vec2 xz) {
	vec2 uv = ((xz - origin) / cell + 0.5) / grid;
	return textureLod(heightmap, uv, 0.0).r;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = height_at(w.xz);
	float hx = height_at(w.xz + vec2(cell, 0.0)) - height_at(w.xz - vec2(cell, 0.0));
	float hz = height_at(w.xz + vec2(0.0, cell)) - height_at(w.xz - vec2(0.0, cell));
	VERTEX.y = h;
	world_normal = normalize(vec3(-hx, 2.0 * cell, -hz));
	NORMAL = world_normal;
	world_pos = vec3(w.x, h, w.z);
	city = textureLod(mask, ((w.xz - origin) / cell + 0.5) / grid, 0.0).r;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n1 = texture(detail, p * 0.004).r;
	float n2 = texture(detail, p * 0.031 + vec2(3.7, 1.9)).r;
	vec3 grass = mix(vec3(0.07, 0.12, 0.05), vec3(0.17, 0.18, 0.09), n1) * (0.75 + 0.5 * n2);
	grass = mix(grass, vec3(0.20, 0.17, 0.11), smoothstep(0.55, 0.8, n2) * 0.5);   // suche flaky
	vec3 rock = mix(vec3(0.27, 0.25, 0.23), vec3(0.42, 0.40, 0.36), n2);
	float steep = smoothstep(0.90, 0.74, world_normal.y);
	vec3 land = mix(grass, rock, steep);
	vec3 paved = texture(pavement, p * 0.3).rgb * vec3(0.8, 0.8, 0.86);
	ALBEDO = mix(land, paved, smoothstep(0.35, 0.65, city));
	ROUGHNESS = mix(0.95, 0.8, city);
	SPECULAR = 0.2;
}
