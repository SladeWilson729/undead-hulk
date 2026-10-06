shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform float age = 0.0;
uniform float delay = 0.0;
uniform float duration = 0.7;
uniform float radius = 6.0;
uniform vec4 force_color : source_color = vec4(0.72,0.85,0.75,1.0);
varying float crest;
void vertex() {
 float t = clamp((age-delay)/duration,0.0,1.0);
 float r = mix(0.35,radius,1.0-pow(1.0-t,2.0));
 float angle = UV.x*6.283185;
 float ripple = sin(angle*11.0+t*15.0)*0.07 + sin(angle*19.0-t*9.0)*0.035;
 float profile = sin(UV.y*3.141593);
 VERTEX = vec3(cos(angle)*(r+(UV.y-0.5)*0.65+ripple),0.08+profile*(0.28+0.3*(1.0-t)),sin(angle)*(r+(UV.y-0.5)*0.65+ripple));
 crest = profile;
}
void fragment() {
 float t = clamp((age-delay)/duration,0.0,1.0);
 float brush = 0.6+0.4*sin(UV.x*125.0+sin(UV.x*57.0)*3.0);
 float breaks = smoothstep(-0.65,0.25,sin(UV.x*81.0+delay*35.0));
 ALBEDO = force_color.rgb;
 ALPHA = crest*brush*breaks*pow(1.0-t,0.65)*0.65*step(delay,age);
}
