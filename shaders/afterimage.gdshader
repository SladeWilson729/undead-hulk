shader_type spatial;
// Smoke afterimage: a frozen copy of a character's pose that glows at the silhouette edge,
// breaks up into drifting smoke as it fades, and never writes depth (ghosts overlap cleanly).
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 smoke_color : source_color = vec4(0.82, 0.78, 0.95, 1.0);
// Brighter rim so the outline reads from the high gameplay camera.
uniform vec4 rim_color : source_color = vec4(0.95, 0.92, 1.0, 1.0);
uniform float base_alpha = 0.55;
uniform float rim_power = 2.0;
// Size of the smoke blotches (world units). Smaller = finer smoke.
uniform float smoke_scale = 5.0;
// Fraction of the ghost's life spent fading in.
uniform float fade_in = 0.2;
// 0 = just spawned, 1 = gone. Set per ghost from script.
instance uniform float fade = 0.0;

varying vec3 world_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	// Smoke rises as the ghost ages, so the breakup crawls upward.
	vec3 p = world_pos * smoke_scale + vec3(0.0, -fade * 3.0, 0.0);
	float n = noise(p) * 0.65 + noise(p * 2.3) * 0.35;
	// Dissolve: as fade goes 0 -> 1, more of the smoke falls below the threshold and vanishes.
	float keep = smoothstep(fade - 0.05, fade + 0.2, n);
	ALBEDO = mix(smoke_color.rgb, rim_color.rgb, rim);
	// Fade in over the first slice of life: a brand-new ghost sits exactly on top of her and
	// would white her out. By the time it shows, she's moved on and it reads as a trail.
	float appear = smoothstep(0.0, fade_in, fade);
	ALPHA = clamp((base_alpha + rim * 0.45) * keep * (1.0 - fade) * appear, 0.0, 1.0);
}
