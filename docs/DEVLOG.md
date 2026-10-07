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
  - [x] 8c: Hulk death clip (Mixamo Death, keeps its fall-back travel; game-over text waits 1.2 s)
  - [ ] 8d: Hulk run clip, toon shading, sound

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

**Step 8c (Hulk death), 2026-10-06.** I ran an automated headless test against Godot 4.7.2, and all 9 checks passed:
- The death clip loads and plays once, keeping its ~1.7 m fall-back travel while the other clips stay pinned.
- Dying plays it.
- The game-over text waits during the fall and appears after 1.2 s.
- The Hulk stays down on the final pose even if keys are pressed.
- R restarts with him standing.

Steps 3 to 9 still pass (step 7 now waits for the delayed game-over text).

Clip data: Death is 3.0 s long; he hits the ground at ~1.5 s and is still by ~2.1 s.

**Step 8d (Hulk victory), 2026-10-06.** Clearing a wave queues a victory roar (`assets/hulk/victory.fbx`). It plays the next time the Hulk stands still during the break, so a punch or walk in progress finishes first. Moving or attacking cancels it immediately, and the next wave starting cuts it. A dead Hulk never celebrates. I ran an automated headless test against Godot 4.7.2, and all 15 checks passed, including a real wave cleared through the spawner. Steps 3 to 10 still pass (step 8 now expects 7 clips).

Clip data: Victory is 6.2 s long. It is still for ~0.4 s, pumps the right arm from 0.6 to 1.6 s, and roars with both arms up at ~2.4, 3.3 and 4.2 s. It settles by ~5.4 s, and the last 0.8 s is dead frames. We play 0.35 to 5.4 s. The clip drifts ~2 m backward; the hips pin removes that drift.

**Step 9a (breakable pillar, test feature), 2026-10-06.** Added `scripts/level/breakable_pillar.gd` and `scripts/level/rubble_chunk.gd`. Two test pillars sit in main.tscn: Level/PillarEast at (7, 0, -1.5) and Level/PillarWest at (-7, 0, 1.5).
- A pillar is built in code from 24 brick chunks plus a stump. It's a @tool script, so it shows in the editor; set `size` in the Inspector.
- A punch (cone reach plus the pillar's half-width) or a ground pound (kill_radius) turns every chunk into a RubbleChunk rigid body. Rubble flies away from the Hulk and fastest at the height of the hit, so the top topples and rains down. The stump stays behind with a small collider.
- Rubble faster than `kill_speed` (6 m/s) kills any soldier it touches. Rubble passes through the Hulk. It freezes with collision off once it settles, then sinks away after `rubble_lifetime`.
- Smashing a pillar shakes the camera, adds a hit stop, a dust burst and a "KRAK!" comic.
- Chunk UVs are built from each chunk's position inside the pillar, with the painterly brick shader's own planar projection and `world_mapping` off. That way the bricks line up before the break and stay glued to the chunks in flight.
- New collision layer 6 (value 32) is debris. Its mask is world, enemies and debris. Neither the Hulk nor the soldiers mask it.

I ran an automated headless test against Godot 4.7.2, and all 15 checks passed:
- An intact pillar blocks the Hulk; a punch smashes it into 24 chunks plus a stump.
- Rubble killed 4 of 6 soldiers standing behind the pillar and flew up to 14 m.
- All chunks settle and freeze, the Hulk walks through rubble, and a pound smashes the second pillar.
- Rubble sinks away after its lifetime.

Steps 3 to 11 still pass. Step 8's height check now waits for process frames, because a heavier level load runs several physics frames before the first pose is applied.

**Step 9b (throwable car), 2026-10-06.** Will's car is in `assets/props/car/rusty_sedan.fbx`. It's Tripo AI output with the texture embedded, about 5k triangles, imported at `root_scale` 4.2, so it's 4.2 x 2.1 x 1.6 m with its front at +Z. One car sits in main.tscn at Level/Car (-2.5, 0, 2.2).
- **Controls:** E picks up the nearest car within 4 m. While holding, E or left click throws it where the Hulk faces.
- **Lift:** the Overhead Squat clip from 3.5 s (hands on the car) at 2.5x, about 0.9 s. He barely moves during the lift and can't throw until it finishes.
- **Carry:** the carry_idle and carry_walk clips are built in code from idle/walk legs plus the lift's final overhead pose on the arms, spine and head (`HulkAnimator._with_upper_body`). He moves at 0.75x speed, and punching and pounding are locked.
- **Throw:** the Throw In clip from 1.0 to 2.2 s at 2x; the car leaves his hands at 1.5 s (0.25 s after the click). The clip's 5.5 m lunge is pinned. The car is glued to the midpoint of his hand bones throughout.
- **In flight:** 22 m/s forward and -4 m/s vertical, so it slams walls low, plus a flat spin. Its collision layer is 0 and its mask is world.
  - The CrushZone Area3D (mask enemies, extending 2.4 m below the car) pins soldiers above 10 m/s, up to 6, and kills them above 4 m/s.
  - A sudden drop in horizontal speed (below 55% in one frame, from at least 7 m/s) is a crush: pinned soldiers explode into gibs, with a "CRUNCH!", shake and hit stop.
  - It plows through BreakablePillars (smashes them and keeps 85% speed).
- **Afterwards:** when it settles, survivors drop off as limp bodies and the car is solid cover again and can be thrown again. Falling off the bridge returns it to its start point. If the Hulk dies holding it, it drops.
- New pieces:
  - `scripts/props/throwable_car.gd` and `scenes/props/throwable_car.tscn`
  - `scripts/player/carry_throw.gd` (a node on hulk.tscn)
  - `Human.pin_to()`
  - the "grab" input on E
  - layer 6 named "debris" in project.godot

I ran an automated headless test against Godot 4.7.2, and all 28 checks passed:
- Lift, carry poses, slower carry walk, throw release on the clip's frame.
- An open throw killed 5 of 5 soldiers, with up to 5 riding, smashed a pillar and settled about 16 m out.
- A wall throw crushed 3 pinned soldiers into gibs.
- The car came back home after being thrown off the bridge, and it drops when the Hulk dies.

Steps 3 to 12 still pass (step 8 now expects 11 clips).

Known look issue: soldiers pinned while the car is still high ride at floor level under it, so they read as swept along rather than splayed on the hood. It reads fine from the gameplay camera; revisit if close-ups matter.

**Step 10a (voice and music), 2026-10-06.** Will's audio is in `assets/sound/`. The music is "Zombie Funfair.wav" (122 s, 48 kHz stereo), set to loop in its import settings. The effects are 17 voiced lines: punch 1-8, ground-pound 1-3, lift-car 1-3, victory 1-3. All of them are voice or growl, mostly two phrases each; there are no impact sounds yet.
- `default_bus_layout.tres` adds Music (-8 dB), Voice and SFX buses. Mix them in the editor's Audio tab.
- **Music:** the Music node in main.tscn autoplays on the Music bus and ducks to `music_death_duck_db` (-14 dB) over 1.5 s when the Hulk dies.
- **Voice** (HulkVoice, `scripts/audio/hulk_voice.gd`, node Hulk/Voice) is one channel with priorities: punch < pound/lift/throw < victory. A line only cuts off a lower-priority one.
  - Punch lines play on `punch_chance` (35%) of swings, only when he's silent.
  - Each line gets +/-5% pitch, never repeats the previous one from its list, and starts past its measured lead-in silence (`LEAD_TRIM`, 35-255 ms per file).
  - It's driven by new signals: `PunchAttack.swung`, `GroundPound.leaped`, `CarryThrow.lifted` and `throw_started`, and `HulkAnimator.victory_started`.
  - Death stops the voice. `throw_lines` is empty until there's a throw line.
- The music track ends on about 1 s of decay and opens quietly, so there's a short breath at each 2-minute loop. Set a loop point in an audio editor if it bothers you.

I ran an automated headless test against Godot 4.7.2, and all 16 checks passed: buses, music loop and playback, lead trim, priority blocking, no repeats, punch rationing, pound interrupting a punch line, lift line, victory line through a real wave clear, silence on death, music duck.

Steps 4 to 13 still pass. Step 3's "8+ attackers surround the Hulk" check is still flaky: it reads 6-8 at the 9 s mark, with or without the props. The same happens without this change; it's on the list to look at with the swarm tuning.

**Step 10b (impact sounds), 2026-10-06.** Will added 13 ElevenLabs effects. None has lead-in silence, but their loudness ranged from -8.9 to -30.5 dB RMS. `scripts/audio/sfx.gd` (the Sfx node in main.tscn) plays them from a 24-voice pool of 3D players on the SFX bus, so they pan with where they happen. Each group levels its files to one target loudness using the measured RMS, and has voice and stagger limits:
- **punch_hit:** squishy and thudding punch, on a connecting punch only (no sound on a whiff). Up to 3 at once.
- **pound_hit:** cannonball, on every pound landing.
- **pillar_smash:** brick wall, from `BreakablePillar.smashed`.
- **car_impact:** heavy metal box, from the new `ThrowableCar.impacted` (any solid hit at 4 m/s or more, at most every 0.2 s). Volume scales with speed.
- **splat:** orange, melon and watermelon, on DeathDirector explosions and splats. Up to 4 at once, 40 ms apart.
- **yelp:** man and woman yelps, on the new `WaveSpawner.human_killed`. 40% chance, up to 2 at once, 120 ms apart. A 20-kill pound gives one or two yelps, not a choir.
- Main does all the wiring. The file names (with "#") are kept as generated, because I can't rename files on Will's machine.

I ran an automated headless test against Godot 4.7.2, and all 13 checks passed: all clips load, the pool and levelling work, a whiff is silent, and the punch, pound, pillar, car, explosion and yelp sounds each fire at the right moment within their limits. Steps 4 to 14 still pass.

**Step 11 (car volume, eating soldiers, obstacle avoidance), 2026-10-07.**
- **Car clang:** its level went from -12 to -20, it's limited to 1 voice at least 0.4 s apart, and the speed boost is capped at +2 dB. A bouncing car was re-triggering a 4 s crash tail.
- **Eating:** a new EatSoldier node on the Hulk (`scripts/player/eat_soldier.gd`), on the F key ("eat" action).
  - It grabs the closest soldier within 3.2 m in a 140-degree cone in front of him. The soldier is caught on the press via `Human.pin_to`, which counts as a kill and makes him yelp.
  - Picking Up plays from 0.4 to 2.4 s at 2x. The soldier slides into the right fist on the grab frame (1.25 s) and dangles 1.5 m below it.
  - eating plays from 0 to 1.3 s at 1.5x. On the chomp frame (0.45 s), gibs burst from his mouth (`DeathDirector.explode_at`, so the splat sound and shake come with it) and he heals +5, capped at max HP.
  - The whole move takes about 1.9 s, at 0.1x movement, with punch, pound and car locked. The 3 s cooldown starts after swallowing.
  - The HUD shows EAT READY / NOM / countdown. `HulkVoice.eat_lines` plays on the grab; it's empty until there's a line for it. Dying mid-meal drops the soldier with no heal.
- **Obstacle avoidance** (`Human._avoid`): every 0.1 s (staggered) a chasing soldier sphere-casts 2.5 m along his line to the Hulk. Clear: he runs straight. Blocked: he casts 16 directions and takes the clear one closest to the goal, with a bias to keep his chosen side.
  - The probe is a 0.35 m sphere at 0.45 m height, on the world layer only, so it catches walls, pillars, stumps and parked cars but ignores the Hulk and the crowd.
  - I didn't use a navmesh, because the obstacles move and break.
  - Before and after, 6 soldiers each: pillar 3 to 6 of 6, parked car 0 to 6 of 6, stump 6 to 6 of 6.
  - Physics cost with 60 soldiers: 31.0 ms with avoidance against 31.6 ms without, on the lab machine, so no measurable difference.

I ran automated headless tests against Godot 4.7.2: step 16 (eating) passed all 25 checks and step 17 (pathing) all 3 cases.
- Steps 4 to 15 still pass. Step 8 now expects 13 clips.
- Step 5 had started failing about a third of the time: its soldiers stand next to the parked car, and launched bodies bounced off it. It now removes the props, and passed 8 of 8.
- Step 3's "8+ attackers" check is unchanged at 5-8 (the swarm-tuning item).

## Tuning knobs (select the node, see Inspector)
- **Hulk:** move_speed, acceleration, deceleration, turn_sharpness
- **CameraRig:** follow_sharpness, look_ahead_factor, look_ahead_max
- **Hulk/PunchAttack:** windup, recovery, move_slow, reach, arc_degrees, max_targets, launch_speed_min/max, launch_lift_min/max
- **HUD:** game_over_delay (seconds before the game-over text covers the death fall)
- **Hulk/Animator:** walk_natural_speed, max_walk_playback, idle_threshold, locomotion_blend, punch_impact_time, punch_end_time, punch_speed, pound_start_time, pound_impact_time, pound_end_time, pound_recover_speed, victory_start_time, victory_end_time, victory_blend
- **Hulk/GroundPound:** cooldown, hop_speed (0: the clip does the leap), rise_time (0.45 s windup), slam_speed, air_control, kill_radius, shove_radius, lift_center/edge, outward_center/edge, shove_speed
- **Main > Hit feel:** pound_shake, pound_hit_stop
- **Human (soldier animation):** max_run_playback, punch_loop_start, punch_loop_end, anim_blend
- **Ragdoll (scripts/deaths/ragdoll.gd):** lifetime; bone list, capsule radii and masses in the BONES table
- **Spawner (WaveSpawner in main.tscn):** first_wave_size, size_growth, first_break, break_time, spawn_interval, min_spawn_interval, interval_shrink_per_wave, max_alive, speed_growth, max_speed_multiplier
- **Hulk/Voice (HulkVoice):** the line lists per event, punch_chance, pitch_variance; bus volumes in the Audio tab
- **Main > Audio:** music_death_duck_db
- **Hulk/EatSoldier:** eat_range, arc_degrees, hang_drop, heal_amount, cooldown, move_while_eating
- **Hulk/Animator > Eat clips:** pickup_start_time, pickup_grab_time, pickup_end_time, pickup_speed, eat_start_time, eat_chomp_time, eat_end_time, eat_speed
- **Human > Obstacle avoidance:** avoid_lookahead, avoid_interval, avoid_side_bias
- **Sfx (main.tscn):** voices, unit_size, panning; per-group target / max_voices / min_interval / chance / pitch in the `groups` table in `scripts/audio/sfx.gd`
- **ThrowableCar > Sound:** impact_sound_speed
- **ThrowableCar (Level/Car):** throw_speed, throw_lift, throw_spin, pin_speed, kill_speed, max_pinned, crush_speed, crush_drop, respawn_height; CrushZone shape size
- **Hulk/CarryThrow:** pickup_range, grab_snap_time, lift_move, carry_speed, grip_offset, throw_move, throw_lockout
- **Hulk/Animator > Carry clips:** lift_start_time, lift_speed, throw_start_time, throw_release_time, throw_end_time, throw_speed
- **Main > Hit feel:** car_crush_shake, car_crush_shake_per_kill, car_crush_hit_stop
- **BreakablePillar (Level/PillarEast, PillarWest):** size, layer_height, burst_speed, burst_lift, spread, spin, kill_speed, rubble_lifetime, chunk_mass
- **Main > Hit feel:** smash_shake, smash_hit_stop
- **Deaths (DeathDirector in main.tscn):** ragdoll_cap, stain_cap, gib_cap, explode_chance, stain_speed, splat_speed, gibs_per_explosion, blood_color
- **PunchAttack > Juggle:** juggle_extra_reach, juggle_max_height
- **FlyingBody (flying_body.tscn):** lifetime, spin, physics material bounce/friction
- **Main > Hit feel:** hit_stop_duration, hit_stop_time_scale, punch_shake, punch_shake_per_hit
- **CameraRig > Shake:** shake_decay, max_shake_offset
- **Human (human.tscn):** move_speed, speed_variance, flank_range, flank_strength, attack_cooldown, attack_reach
- **Main:** debug_start_count, debug_spawn_batch
- **Camera height/angle:** the transform on CameraRig/Camera3D. It currently sits 16 m up and 11 m back, tilted down about 55 degrees.
