shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;
#include "res://assets/materials/painterly/paint.gdshaderinc"

group_uniforms SourceTextures;
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool use_normal_map = false;
uniform float source_normal_scale = 1.0;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);

group_uniforms Paint;
uniform float texture_softness : hint_range(0.0,3.0) = 0.7;
uniform float palette_steps : hint_range(3.0,16.0) = 7.0;
uniform float palette_strength : hint_range(0.0,1.0) = 0.55;
uniform float brush_scale : hint_range(8.0,160.0) = 65.0;
uniform float brush_strength : hint_range(0.0,0.5) = 0.13;
uniform float saturation : hint_range(0.0,1.5) = 1.08;
uniform float normal_strength : hint_range(0.0,1.0) = 0.35;

group_uniforms CelLight;
uniform vec4 shadow_color : source_color = vec4(0.55,0.62,0.76,1.0);
uniform vec4 highlight_color : source_color = vec4(1.0,0.94,0.79,1.0);
uniform float shadow_fill : hint_range(0.0,0.6) = 0.27;
uniform float mid_threshold : hint_range(0.1,0.65) = 0.32;
uniform float highlight_threshold : hint_range(0.5,0.95) = 0.72;
uniform float band_softness : hint_range(0.005,0.15) = 0.035;
uniform float contour_strength : hint_range(0.0,0.8) = 0.3;

void fragment() {
 vec2 uv = UV*uv_scale+uv_offset;
 vec3 source = texture(albedo_texture,uv,texture_softness).rgb*albedo_tint.rgb;
 float luminance = dot(source,vec3(0.2126,0.7152,0.0722));
 source = mix(vec3(luminance),source,saturation);
 // Quantize luminance rather than RGB so skin and camouflage retain their hues.
 float steps = max(palette_steps,3.0);
 float quantized = floor(luminance*steps+0.5)/steps;
 float ratio = (quantized+0.055)/(luminance+0.055);
 source *= mix(1.0,ratio,palette_strength);
 // UV-space pigment travels with the skinned mesh, with no world-space swimming.
 vec2 brush_uv = vec2(uv.x+uv.y*0.35,uv.y)*brush_scale;
 float pigment = paint_p(brush_uv*vec2(1.0,2.8));
 float daubs = bands_p(pigment);
 source *= 1.0+(daubs-0.5)*brush_strength;
 float contour = 1.0-smoothstep(0.05,0.3,abs(dot(normalize(NORMAL),normalize(VIEW))));
 ALBEDO = max(source,vec3(0.0))*(1.0-contour*contour_strength);
 ROUGHNESS = 1.0;
 if (use_normal_map) {
  NORMAL_MAP = texture(normal_texture,uv).rgb;
  NORMAL_MAP_DEPTH = source_normal_scale*normal_strength;
 }
 // Controlled painted shadow fill replaces variable environment ambient light.
 EMISSION = ALBEDO*shadow_color.rgb*shadow_fill;
}

void light() {
 float n = max(dot(NORMAL,LIGHT),0.0);
 float mid = smoothstep(mid_threshold-band_softness,mid_threshold+band_softness,n);
 float high = smoothstep(highlight_threshold-band_softness,highlight_threshold+band_softness,n);
 float amount = (0.12+mid*0.44+high*0.3)*smoothstep(0.0,0.04,n);
 vec3 paint_light = mix(vec3(0.82,0.88,1.0),highlight_color.rgb,high*0.65);
 DIFFUSE_LIGHT += paint_light*amount*ATTENUATION*LIGHT_COLOR/PI;
}
