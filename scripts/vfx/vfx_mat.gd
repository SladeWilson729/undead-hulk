class_name VfxMat
extends RefCounted
## Small shared builders for the code-made effects (explosion, rocket, muzzle flash), so they
## all share one look: unshaded, glowing, cartoon flat color.

## Unshaded, self-lit, alpha-blended color. alpha < 1 for glows you can see through.
static func glow(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Soft round smoke puff for particles: unshaded sphere that takes its color from the
## particle's color ramp (so it can fade out).
static func puff_mesh() -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 10
	s.rings = 5
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	s.material = m
	return s


## One-shot particle burst, world space, ready to tune. NOT emitting yet: add it to the tree,
## position it, THEN set emitting = true. A burst that starts emitting before it's positioned
## fires its first particles at the world origin.
static func burst(amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	return p


## Grows from 40% to 100% over the particle's life (smoke billows out).
static func grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.4))
	c.add_point(Vector2(1.0, 1.0))
	return c


## Color over life: start color, darkening toward end color while fading to transparent.
static func fade_ramp(start: Color, end: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(start.r, start.g, start.b, 0.9))
	g.set_color(1, Color(end.r, end.g, end.b, 0.0))
	return g
