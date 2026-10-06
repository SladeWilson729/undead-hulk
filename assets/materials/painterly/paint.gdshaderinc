float hash_p(vec2 p) {
 return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise_p(vec2 p) {
 vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
 return mix(mix(hash_p(i), hash_p(i+vec2(1,0)), f.x), mix(hash_p(i+vec2(0,1)), hash_p(i+vec2(1,1)), f.x), f.y);
}
float paint_p(vec2 p) {
 return noise_p(p)*0.55 + noise_p(p*2.13+17.0)*0.3 + noise_p(p*4.37)*0.15;
}
float bands_p(float x) {
 return smoothstep(0.32,0.36,x)*0.45 + smoothstep(0.63,0.67,x)*0.35 + 0.2;
}
