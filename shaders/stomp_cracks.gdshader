shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float age = 0.0;
uniform float lifetime = 3.6;
void fragment() {
 float reveal = smoothstep(COLOR.r*0.32,COLOR.r*0.32+0.06,age);
 float fade = 1.0-smoothstep(lifetime-1.0,lifetime,age);
 // A dark fissure bordered by a thin chipped, lighter asphalt edge.
 float edge = smoothstep(0.6,0.95,abs(UV.x*2.0-1.0));
 ALBEDO = mix(vec3(0.014,0.019,0.023),vec3(0.24,0.28,0.29),edge);
 ALPHA = reveal*fade;
}
