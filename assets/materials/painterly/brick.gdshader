shader_type spatial;
render_mode specular_disabled;
#include "res://assets/materials/painterly/paint.gdshaderinc"
uniform vec4 brick_color : source_color = vec4(0.57,0.25,0.16,1);
uniform vec4 light_color : source_color = vec4(0.77,0.43,0.27,1);
uniform vec4 mortar_color : source_color = vec4(0.28,0.27,0.25,1);
uniform vec2 bricks_per_uv = vec2(8.0,16.0);
uniform bool world_mapping = true;
uniform vec2 brick_size_meters = vec2(0.5,0.22);
uniform float mortar_width : hint_range(0.02,0.2) = 0.075;
uniform float brush_strength : hint_range(0,1) = 0.65;
uniform float brick_variation : hint_range(0,1) = 0.3;
uniform float edge_wear : hint_range(0,1) = 0.45;
uniform float seed : hint_range(0,100) = 13.0;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
 world_position = (MODEL_MATRIX * vec4(VERTEX,1)).xyz;
 world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}
void fragment() {
 vec2 p = UV*max(bricks_per_uv,vec2(1));
 if (world_mapping) {
  vec3 n = abs(normalize(world_normal));
  vec2 planar = n.y > max(n.x,n.z) ? world_position.xz : (n.x > n.z ? vec2(world_position.z,-world_position.y) : vec2(world_position.x,-world_position.y));
  p = planar / max(brick_size_meters,vec2(0.01));
 }
 float row = floor(p.y);
 p.x += mod(row,2.0)*0.5;
 vec2 id = floor(p); vec2 f = fract(p);
 float rnd = hash_p(id+seed);
 float brush = paint_p(p*vec2(5.0,13.0)+seed);
 float chips = noise_p(p*25.0+seed)*edge_wear*0.035;
 vec2 edge = min(f,1.0-f)*vec2(2.0,1.0);
 float distance_edge = min(edge.x,edge.y)-chips;
 float aa = max(length(fwidth(p))*0.45,0.002);
 float face = smoothstep(mortar_width-aa,mortar_width+aa,distance_edge);
 vec3 col = mix(brick_color.rgb,light_color.rgb,bands_p(brush)*brush_strength);
 col *= 1.0+(rnd-0.5)*brick_variation;
 // Painted top/left bevel and cool recessed lower edge.
 float rim = 1.0-smoothstep(mortar_width+0.018,mortar_width+0.06,distance_edge);
 float top_left = step(f.y,0.5)*0.7+step(f.x,0.5)*0.3;
 col *= 1.0+rim*(top_left*0.36-0.18);
 vec3 mortar = mortar_color.rgb*(0.85+noise_p(p*18.0)*0.2);
 ALBEDO = mix(mortar,col,face);
 ROUGHNESS = 1.0;
}
void light() {
 float n = max(dot(NORMAL,LIGHT),0.0);
 float cel = smoothstep(0.02,0.06,n)*0.32 + smoothstep(0.36,0.40,n)*0.33 + smoothstep(0.72,0.76,n)*0.35;
 DIFFUSE_LIGHT += cel * ATTENUATION * LIGHT_COLOR / PI;
}
