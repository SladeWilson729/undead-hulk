shader_type spatial;
render_mode specular_disabled;
#include "res://assets/materials/painterly/paint.gdshaderinc"
uniform vec4 base_color : source_color = vec4(0.19,0.22,0.26,1);
uniform vec4 paint_color : source_color = vec4(0.34,0.38,0.42,1);
uniform vec4 stone_color : source_color = vec4(0.48,0.49,0.46,1);
uniform float meters_per_pattern : hint_range(0.25,8.0) = 2.0;
uniform float brush_strength : hint_range(0,1) = 0.55;
uniform float aggregate_strength : hint_range(0,1) = 0.24;
uniform float crack_strength : hint_range(0,1) = 0.3;
uniform float seed : hint_range(0,100) = 7.0;
uniform bool world_mapping = true;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX,1)).xyz; }
void fragment() {
 vec2 p = (world_mapping ? world_position.xz : UV) / max(meters_per_pattern,0.01);
 p += vec2(seed, seed*0.71);
 float broad = paint_p(p*3.0);
 float strokes = paint_p(p*vec2(13.0,42.0)+noise_p(p*8.0)*2.0);
 float daubs = bands_p(broad*0.65+strokes*0.35);
 vec3 col = mix(base_color.rgb,paint_color.rgb,daubs*brush_strength);
 // Sparse irregular aggregate with distance filtering to suppress sparkle.
 vec2 cell = floor(p*65.0);
 vec2 center = vec2(hash_p(cell),hash_p(cell+41.0))*0.6+0.2;
 float aa = max(length(fwidth(p*65.0)),0.02);
 float stone = (1.0-smoothstep(0.09,0.09+aa,length(fract(p*65.0)-center))) * step(0.78,hash_p(cell+9.0)) * (1.0-smoothstep(0.25,0.8,aa));
 col = mix(col,stone_color.rgb,stone*aggregate_strength);
 float vein = abs(noise_p(p*2.8+noise_p(p*9.0)*0.18)-0.5);
 float crack = (1.0-smoothstep(0.006,0.016+length(fwidth(p)),vein))*step(0.56,noise_p(p*4.0+81.0));
 ALBEDO = col*(1.0-crack*crack_strength);
 ROUGHNESS = 1.0;
}
void light() {
 float n = max(dot(NORMAL,LIGHT),0.0);
 float cel = smoothstep(0.02,0.06,n)*0.32 + smoothstep(0.36,0.40,n)*0.33 + smoothstep(0.72,0.76,n)*0.35;
 DIFFUSE_LIGHT += cel * ATTENUATION * LIGHT_COLOR / PI;
}
