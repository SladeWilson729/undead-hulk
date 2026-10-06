shader_type spatial;
// Greybox floor with world-space grid lines (one cell = 2 m by default).
// WHY: on a flat grey floor you can't feel speed or judge distance. The grid fixes that
// for free and will be swapped for real art in step 8.

uniform vec4 base_color : source_color = vec4(0.20, 0.21, 0.24, 1.0);
uniform vec4 line_color : source_color = vec4(0.34, 0.35, 0.40, 1.0);
uniform float cell_size = 2.0;
uniform float line_width = 0.05;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = abs(fract(world_pos.xz / cell_size - 0.5) - 0.5) * cell_size;
	float on_line = 1.0 - step(line_width, min(g.x, g.y));
	ALBEDO = mix(base_color.rgb, line_color.rgb, on_line);
	ROUGHNESS = 0.9;
}
