# Undead Hulk: Dev Log

## Locked decisions
| Decision | Choice |
|---|---|
| Engine | Godot 4.7 stable (moved off the 4.8 dev build on 2026-10-06; tests run on 4.7.2) |
| Physics | Jolt (Project Settings > Physics > 3D) |
| Camera | High angle, fixed rotation, follows Hulk with mouse look-ahead |
| Platform | PC first, mobile later |
| Input | Keyboard + mouse |
| Gore | Cartoony red |
| Scale | Humans 1.8 m, Hulk 3.6 m (set in collision shapes, never with node scale) |

## Collision layers
| Layer | Name | Used by |
|---|---|---|
| 1 | world | Floor, walls, rails |
| 2 | player | Hulk |
| 3 | enemies | Living humans (step 3) |
| 4 | ragdolls | Dead bodies / gibs (step 6) |
| 5 | hitboxes | Punch and ground pound areas (step 4-5) |

- **Hulk:** layer 2, mask 1 (world only). He passes through humans and shoves them aside with `Hulk._shove_humans()`, so the swarm can never pin him in place.
- **Human:** layer 3, mask 1 + 2 + 3 (world, Hulk, other humans). Humans stop at the Hulk's capsule and pile up around him instead of overlapping each other or him.

## Controls
| Action | Input |
|---|---|
| Move | WASD |
| Aim / face | Mouse |
| Punch | Left mouse (hold to keep punching) |
| Ground pound | Right mouse or Space |
| Debug: take 10 damage | H (editor builds only) |
| Restart after death | R |

## Milestone 1 progress
- [x] Step 1: Project + greybox level (80 m x 8 m corridor, tall north wall, low south rail so the camera never loses the Hulk)
- [x] Step 2: Hulk movement, mouse aim, camera rig, health, HUD, placeholder death and restart
- [x] Step 3: Enemy chase + contact damage (1 dmg, 1.0 s per-enemy cooldown), flanking, Hulk shove, hurt flash. A temporary spawner in main.gd puts 16 humans in at start; step 7 replaces it.
- [x] Step 4: Punch (cone hit check, max 4 victims, alternating fists, hit stop, screen shake). Victims become FlyingBody rigid bodies (the "cheap death" that stays as the ragdoll fallback in step 6).
- [x] Step 5: Ground pound (hop + slam, kills everything within 6 m and launches it upward, knocks back the 6-9 m ring, invulnerable while airborne, 4 s cooldown, HUD cooldown readout, shockwave ring)
- [x] Step 6: Death system. DeathDirector picks ragdoll (cap 15), cheap body over the cap, or explosion (10% random). Impacts splat (15+) or stain (7+). Juggle: punch or pound an airborne body to explode it. Stains cap 60, gibs cap 160. Humans got limbs + a procedural run/slap animation that matches the ragdoll layout.
- [x] Step 7: Wave spawner. Clear-to-advance waves: 12 + 8 per wave, alternating ends, +4% human speed per wave (capped at 1.3x), max 60 alive. 5 s breaks. HUD: wave, kills, banners, game-over summary. Debug spawner and F key removed; H only works in editor builds.
- [ ] Step 8: Juice + art pass
  - [x] 8a: Hulk model + animations (Mixamo zombie hulk: idle, walk, two haymakers, Jump Attack as the ground pound)
  - [x] 8b: Soldier models + animations (4 rigged Mixamo soldiers, Running + Punch Combo) and skeleton ragdolls
  - [ ] 8c: Hulk run clip, death clip, toon shading, sound

## Validation log
**Steps 1-2, 2026-10-05.** I ran an automated headless test against Godot 4.7.2 (Linux), and all 25 checks passed:
- Input map loads.
- Jolt is active.
- The Hulk lands on the floor and reaches its top speed of 7.0 m/s.
- The Hulk stops when keys are released, and the walls block it.
- Facing turns toward the target, and the center of the screen projects onto the camera focus.
- H deals 10 damage and the HUD updates.
- The Hulk dies exactly once and the game over banner shows.
- A dead Hulk ignores input, and R reloads the scene at full HP.

I also rendered one screenshot with the OpenGL fallback to check framing.

Not yet verified: how it feels on Will's PC in the Forward+ renderer. That needs a hands-on playtest.

**Step 3, 2026-10-05.** I ran an automated headless test against Godot 4.8-dev7, and all 11 checks passed:
- 16 humans spawn, split evenly between the two ends.
- 8 of them surround the Hulk and attack.
- None clip inside his capsule.
- Damage is exactly 1 per attacker per second (24 damage in 3 s from 8 attackers).
- The Hulk bulldozes 13 m through the swarm in 2 s.
- kill() removes a human and emits its signal.
- F spawns 10 more.
- Humans go idle when the Hulk dies.

Rough performance: with 60 humans swarming, the physics step took about 3.6 ms per frame. That was measured on a headless cloud CPU, not Will's PC, so it isn't a benchmark.

**Step 4, 2026-10-05.** I ran an automated headless test against Godot 4.8-dev7, and all 18 checks passed:
- The cone hits humans in front and skips humans behind, beside, or out of reach.
- The Hulk slows during the punch, and his speed comes back after.
- Punched humans become flying bodies that carry their visuals.
- Hit stop kicks in on a connect and releases afterwards.
- Bodies fly away and upward, then clean themselves up.
- Holding the button punches about 5 times in 2 s.

All 11 step 3 checks still pass.

Balance note: with no target cap, an 80 to 100 degree cone killed 31 of a 33-human swarm in 4 punches. With `max_targets = 4`, the same 4 punches killed 16.

**Step 5, 2026-10-05.** I ran an automated headless test against Godot 4.8-dev7, and all 22 checks passed:
- The input starts the pound, and the Hulk hops into the air.
- The Hulk can't be hurt and can't punch while airborne.
- The impact kills the 3 humans inside 6 m and launches them upward.
- A human in the 6-9 m ring survives but gets knocked back. A human 15 m away is untouched.
- The 4 s cooldown blocks a second pound but still allows punching.
- The HUD shows the countdown.

The step 3 and step 4 suites still pass. The step 3 "8+ attackers" check sometimes reports 7, because human speeds and flank directions are random; I saw 7, 8, 9 and 8 across runs.

Balance note: one pound into a clumped swarm of 32 killed all 32. Revisit the cooldown and radius once step 7 waves exist.

**Step 6, 2026-10-05.** I ran an automated headless test against Godot 4.8-dev7, and all 21 checks passed:
- Running humans swing their legs.
- A kill spawns a ragdoll wearing that human's shirt, and the joints hold the body together in flight.
- With the cap set to 3, the 4th through 6th deaths use the cheap body.
- A big fall splats: the body is removed and a stain appears. A gentle landing doesn't splat.
- At 100% explode chance, a kill produces 10 gibs.
- Punching an airborne body explodes it, and that counts as a hit for hit stop.
- The stain cap holds at 60 and the gib cap holds.
- Everything cleans itself up.

The step 3, 4 and 5 suites still pass.

**Measured impact strengths** (8 bodies per case, max sudden velocity change across all ragdoll parts):

| Case | Impacts (m/s) | Splats at threshold 15 |
|---|---|---|
| Pound, center victims | 13-18 | 6 of 8 |
| Pound, edge victims | 1-15 | 0 of 8 |
| Punch, down the corridor | 8-17 | 2 of 8 |
| Punch, into the wall | 18-25 | 8 of 8 |

Measuring the torso alone missed most landings, because the limbs hit the floor first and cushion it. That's why every part is watched.

**Stress test** (60 humans, a pound plus a punch every 1/3 s for 4 s): peak 15 ragdolls, 31 cheap bodies, 19 explosions. The physics step averaged 6.6 ms and peaked at 18.8 ms on a slow cloud CPU. **Needs measuring on Will's PC.** If it hitches, lower DeathDirector.ragdoll_cap first.

I rendered one screenshot in Forward+ (Vulkan/lavapipe) to confirm stains and ragdolls draw correctly.

**Step 7, 2026-10-05.** I ran an automated headless test against Godot 4.8-dev7, and all 19 checks passed:
- Wave 1 starts after 2 s with 12 humans, trickling in from alternating ends.
- Clearing a wave starts a break, and the kill counter and banners update.
- Wave 2 has 20 humans running 4% faster, and the speed bonus caps at 1.3x.
- A human that falls off the bridge is killed, so a wave can't get stuck.
- max_alive holds.
- Spawning stops when the Hulk dies, and the game-over screen shows the wave and kill count.

The step 3, 4, 5 and 6 suites still pass.

**Balance runs** (tools/balance_bot.gd, 3 runs per setting):

| Pound cooldown | Bot | Wave reached |
|---|---|---|
| 4 s | stands still | 6, 6, 6 |
| 6 s | stands still | 6, 6, 6 |
| 8 s | stands still | 6, 6, 6 |
| 4 s | kites | 6, 7, 7 |
| 8 s | kites | 6, 6, 6 |

Finding: the pound cooldown barely changes the outcome. The Hulk dies from attrition: 100 HP, no healing, and about 140 humans to get through by wave 6. Pound left at 4 s pending a sustain decision.

**Step 8a (Hulk model), 2026-10-05.** I ran an automated headless test against Godot 4.8-dev7, and all 22 checks passed:
- The 5 clips load. Idle and walk loop; the attacks don't.
- The model stands 3.65 m tall, faces the Hulk's forward direction, and carries the hurt-flash overlay.
- Moving plays walk, scaled to speed (capped at 2.4x); stopping returns to idle.
- The punch clip sits at 1.18 s on the gameplay strike frame (impact pose 1.20 s), and punches alternate hands.
- The pound snaps to the slam pose (1.65 s) on the impact frame after a 0.45 s windup, and the body stays grounded.
- Everything returns to idle afterwards.

The step 3 to 7 suites still pass (step 5's "hulk hops" check now expects him to stay grounded). I rendered a Forward+ contact sheet of idle, punch, pound airborne and pound landing.

**Asset pipeline (how to add a Mixamo clip):**
1. On Mixamo, use the same uploaded character and download as FBX Binary, **With Skin**, 30 fps (tick In Place for locomotion).
2. Put it in `assets/hulk/` as `hulk_<name>.fbx`. In Godot's Import dock, set **Import As: Animation Library**, set **FBX > Embedded Image Handling: Discard**, then click Reimport. Copying an existing `hulk_walk.fbx.import` (with its `uid=` line deleted) does the same.
3. Add the file to `CLIP_FILES` in `scripts/player/hulk_animator.gd`.

All the Hulk clips share one skeleton, so no retargeting is needed. Root motion is stripped automatically (hips pinned in X/Z).

**Measured clip timings:**
- Zombie Punching: the haymaker lands at ~1.2 s (punch_a = right hand, punch_b = left).
- Jump Attack: crouch to 0.45 s, airborne 0.6-1.4 s, hands hit the floor at 1.65 s, recovery to ~2.5 s, root drift ~3 m (stripped).
- Walking: feet match the floor at 1.88 m/s, so the Hulk's 7 m/s would need 3.7x playback. Capped at 2.4x with some foot slide. **A Mutant Run clip would fix this.**

Raw downloads were moved to `assets/_raw/`. That folder is skipped by Godot (`.gdignore`) and by git.

**Step 8b (soldiers), 2026-10-06.** I ran an automated headless test against Godot 4.7.2, and all 37 checks passed:
- All 4 soldiers build at 1.80 m with no node scaling, and random spawns use all 4.
- Running plays at a rate matched to ground speed, and attacking soldiers loop the Punch Combo flurry.
- Each soldier type, including the 41-bone rig, builds an 11-body skeleton ragdoll that launches, lands on the floor, and stays in one piece.
- Juggling a soldier ragdoll explodes him into gibs in his uniform color.
- Ragdolls sink and free themselves after their lifetime.
- The ragdoll cap holds under stress.

Steps 3 to 8 still pass. Step 6 was updated: it now checks that the ragdoll is the soldier's own model rather than a shirt color.

**Stress test** (60 soldiers, a pound plus punches): physics averaged 7.4-8.0 ms and peaked at 15.7-18.6 ms on a slow cloud CPU. That's about the same as the capsule people. **The render cost of 60 skinned soldiers still needs measuring on Will's PC.**

**Soldier pipeline:**
- Files: `assets/humans/soldier_X_run.fbx` (model, textures and Running, imported as a scene) and `soldier_X_punch.fbx` (Punch Combo only, imported as an Animation Library).
- `nodes/root_scale` in each `.import` makes the soldier 1.8 m tall. Don't scale the node instead: physics bodies (the ragdoll) can't be scaled.
- Variants live in `scripts/enemies/soldier_variants.gd`, along with their measured run speeds.
- Ragdoll bodies are built in code (`scripts/deaths/ragdoll.gd`) from 11 Mixamo bone names, so any Mixamo soldier works without editing a scene.

**Measured clip data:**
- Running (0.7 s loop): the planted foot matches the floor at 2.7 / 3.4 / 3.6 / 3.4 m/s (soldiers A / B / C / D).
- Punch Combo (2.2 s): four punches between 0.45 and 1.55 s; that window loops while attacking.

## Tuning knobs (select the node, see Inspector)
- **Hulk:** move_speed, acceleration, deceleration, turn_sharpness
- **CameraRig:** follow_sharpness, look_ahead_factor, look_ahead_max
- **Hulk/PunchAttack:** windup, recovery, move_slow, reach, arc_degrees, max_targets, launch_speed_min/max, launch_lift_min/max
- **Hulk/Animator:** walk_natural_speed, max_walk_playback, idle_threshold, locomotion_blend, punch_impact_time, punch_end_time, punch_speed, pound_start_time, pound_impact_time, pound_end_time, pound_recover_speed
- **Hulk/GroundPound:** cooldown, hop_speed (0: the clip does the leap), rise_time (0.45 s windup), slam_speed, air_control, kill_radius, shove_radius, lift_center/edge, outward_center/edge, shove_speed
- **Main > Hit feel:** pound_shake, pound_hit_stop
- **Human (soldier animation):** max_run_playback, punch_loop_start, punch_loop_end, anim_blend
- **Ragdoll (scripts/deaths/ragdoll.gd):** lifetime; bone list, capsule radii and masses in the BONES table
- **Spawner (WaveSpawner in main.tscn):** first_wave_size, size_growth, first_break, break_time, spawn_interval, min_spawn_interval, interval_shrink_per_wave, max_alive, speed_growth, max_speed_multiplier
- **Deaths (DeathDirector in main.tscn):** ragdoll_cap, stain_cap, gib_cap, explode_chance, stain_speed, splat_speed, gibs_per_explosion, blood_color
- **PunchAttack > Juggle:** juggle_extra_reach, juggle_max_height
- **FlyingBody (flying_body.tscn):** lifetime, spin, physics material bounce/friction
- **Main > Hit feel:** hit_stop_duration, hit_stop_time_scale, punch_shake, punch_shake_per_hit
- **CameraRig > Shake:** shake_decay, max_shake_offset
- **Human (human.tscn):** move_speed, speed_variance, flank_range, flank_strength, attack_cooldown, attack_reach
- **Main:** debug_start_count, debug_spawn_batch
- **Camera height/angle:** the transform on CameraRig/Camera3D. It currently sits 16 m up and 11 m back, tilted down about 55 degrees.
