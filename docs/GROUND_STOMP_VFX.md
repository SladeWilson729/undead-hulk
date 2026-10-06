# Ground stomp: force waves and fractured asphalt

Implemented October 6, 2026, for Godot 4.7.2 Forward+.

Press Space or right mouse in the game. The existing jump attack triggers this effect on its landing frame. Damage, knockback, cooldown, character animation, camera shake and hit stop remain owned by the existing gameplay systems.

## Visual sequence

- Three broken, rippling force fronts expand over about one second, staggered by 0.13 seconds. The leading front approaches the attack's kill radius; this is an animated impact cue, not a persistent range indicator.
- Thirteen jagged fissures branch outward over roughly 0.38 seconds. Dark centers and lighter chipped edges suggest split asphalt.
- Up to 24 five-sided asphalt chips jump, tumble, settle and shrink away. These are cosmetic meshes without collision.
- Cracks linger, then fade over the final second. The complete effect frees itself at 3.6 seconds. Repeated uses own independent materials and age values; hit stop slows their timeline with gameplay.

## Reuse and tuning

`res://scenes/vfx/ground_stomp_effect.tscn` is the reusable effect. Select its root to adjust lifetime, debris count and force color. GroundPound's Presentation / Impact Effect selects the scene; it passes the current kill radius and a fresh pattern seed at impact.

For scripted use, instantiate the scene, set radius and pattern_seed, add it to the world, position it at ground contact, then call `play()` from a physics callback. It samples collision layer 1 once to place cracks and debris. Use a fixed seed to reproduce a layout. This is a procedural one-shot animation, not an imported skeleton clip.

Crack and debris placement target approximately flat static ground within 0.65 m below the origin. Fissures are rejected where their corners lack upward-facing support. A 0.065 m surface offset clears the current bridge's slightly raised visual mesh. Adjust that offset if the render mesh and collision surface change. Airborne force fronts can extend beyond the bridge; cracks cannot. The effect is cosmetic and does not deform terrain or change navigation/collision.

## Validation

Run `godot --path . --fixed-fps 60 -s tools/stomp_preview.gd` for the rendered integration check. It triggers the real Hulk attack twice, checks one effect per landing, cooldown completion, cleanup, changed blast radius, and crack vertices staying on the bridge near an edge. It saves `docs/stomp-impact.png` and `docs/stomp-cracks.png`.

Rendered captures were visually inspected in Forward+ on an RTX 3060. Godot reported no script or shader errors. A sandbox warning prevents caching shaders to the user folder but did not prevent rendering. Combat with populated waves and performance at scale have not been benchmarked.
