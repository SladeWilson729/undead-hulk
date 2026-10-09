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

**Step 12 (rocket soldier), 2026-10-08.** One rocket soldier joins each wave (`WaveSpawner.rocket_soldiers_per_wave`). He walks on once 25% of the wave has spawned (`rocket_spawn_at`), so he arrives behind a screen of runners. He counts toward the wave, so the wave won't clear until he's dead.

**Model:** Will's Tripo rocket soldier, `assets/base_models/tripo_convert_0ef4d69c-…fbx`.
- It's Mixamo-rigged (65 bones, same names as the soldiers), imported at `root_scale` 2.03, so he's 1.72 m tall.
- The launcher is `assets/props/rocket_launcher.glb`. Its bore is at +Z, the pistol grip at z 0.03, the front grip at z 0.32, and the tube centreline at y 0.258. It's used at 1.0 scale, a 1 m tube.

**Run:** soldier B's Mixamo run, retargeted by `AnimRetarget`.
- Why retarget: the two rigs share bone names but not rest poses (hips 90 degrees apart, thighs 177, forearms 112), so copied rotations would twist him.
- How: per frame, each bone's world-space turn away from its rest is applied to the target's rest. The hips height is the clip's own height times the leg-length ratio. The clip is then shifted so the lowest toe of the stride sits exactly on the floor.
- Result: the planted foot is at 0.00-0.02 m and the hips track soldier B's within 3 cm. It's built once (10 ms) and cached.

**Kneel and fire:** `RocketPose`, a GDScript SkeletonModifier3D, followed by two TwoBoneIK3D.
- The pose modifier does the kneel (hips drop 0.37 m plus a 10-degree lean), a 30-degree shooter's torso twist with the head turned back, and the recoil (launcher kicks back 12 cm and up 8 degrees, torso rocks back 6 degrees, over 0.45 s). It also places the launcher at the right shoulder, riding Spine2.
- ArmsIK keeps both hands on the grips at all times. LegsIK, weighted by crouch, gives the kneel stance: front foot flat, back knee on the floor.
- The twist is what makes the grips reachable. His arms reach 0.57 m, and without the twist the front grip is 0.74 m from his left shoulder; with it, about 0.53 m.
- Note: modifier results only exist during the skeleton update, so measure the final pose inside `Skeleton3D.skeleton_updated`.

**AI** (RocketSoldier extends Human, so death, ragdoll, eating, car pins and obstacle avoidance are all inherited):
- APPROACH to `preferred_range` (13 m) with a clear line of sight, then KNEEL (0.35 s).
- AIM (0.9 s, with a pulsing red laser along the exact rocket path as the warning), then FIRE, then RELOAD (2.2 s) and repeat.
- If the Hulk comes inside `min_range` (6 m) he gets up and RETREATs.
- Line of sight is a world-only ray (walls, pillars, parked cars).
- On death or pin, the rig shuts off for the ragdoll and the launcher drops as a loose RubbleChunk prop.

**Rocket** (`scripts/weapons/rocket.gd`):
- 18 m/s, built in code (olive body, nose cone, fins, flickering exhaust and light, smoke trail). It casts a ray along each step's movement against world, Hulk and soldiers, excluding the shooter.
- Blast radius 3.5 m. The Hulk takes 14 at the centre down to 4 at the edge, and invulnerability (the pound) still applies.
- Soldiers in the blast die and are thrown outward, so friendly fire is on. Airborne bodies explode, pillars smash, and a parked car gets shoved.

**Effects** (all code-made, sharing the `VfxMat` helpers):
- `Explosion`: three-layer fireball, light flash, ground shockwave ring, sparks, rising smoke, a scorch decal that fades after 5 s, and a "KA-BOOM!" / "BLAM!" / "KRAKOOM!" comic.
- `MuzzleFlash`: flame cone and flash ball at the muzzle, plus a backblast cone and smoke out of the rear of the tube.
- One-shot particle bursts must be positioned before `emitting = true`, or the first burst appears at the world origin. `VfxMat.burst` now returns them not emitting.

**Sound and feel:**
- New sfx groups `rocket_launch` (the cannonball clip pitched up 1.6x) and `rocket_boom` (pitched down to 0.7x) are stand-ins until there are real rocket sounds.
- Main adds shake on launch and on the explosion, plus extra shake and a hit stop when the Hulk is caught.

**Tests:** step 18 passed all 23 checks, three runs in a row. It covers:
- one per wave, counted in the wave
- 1.72 m tall, carrying the launcher, running the retargeted clip
- hands on the grips while running and back on them after each kick (6-8 mm; up to ~5 cm for a frame during the 0.1 s kick)
- kneel, then laser, then a shot from range; recoil; barrel fire at both ends
- a hit of 4-14 with the explosion; a second shot after reload
- friendly fire; retreating from 3 m; no shot through a pillar (he repositions and fires); death dropping the launcher

He can also be eaten, which drops the launcher and counts the kill. A 45 s soak of live waves raised no script errors: 12 rockets fired, 12 exploded.

Steps 4-17 pass, with these test fixes:
- Step 7 turns rocket soldiers off (it checks wave counts).
- Step 15 expects 15 clips (two reused for the rocket sounds).
- Step 17's stump case removes the parked car, which overlapped the Hulk's spot and wedged him against the stump; 5 of 5 after.

**Balance note:** a rocket soldier left alone deals 14 about every 3.1 s. A Hulk that ignores him dies in about 20 s; in the soak, a stationary Hulk lost 179 HP in 40 s. That's intended (hunt him first), but it's the first knob to turn: `Rocket.max_damage` / `min_damage`, `RocketSoldier.reload_time` / `aim_time`.

**Step 13 (ninja), 2026-10-08.** One ninja joins each wave (`WaveSpawner.ninjas_per_wave`). She drops in once half the wave has spawned (`ninja_spawn_at`), after the rocket soldier, while the Hulk is busy with the crowd. She counts toward the wave like anyone and still dies in one hit.

**Model and clips:** Will's female ninja, rigged in Mixamo, so her clips play on her own skeleton with no retargeting.
- `assets/humans/ninja/Run.fbx` is the model plus the run (imported as a scene, `root_scale` 1.7, about 1.55 m tall).
- `Flip Kick.fbx` and `Two Hand Club Combo.fbx` import as animation libraries.
- `Running Arc.fbx` is imported but unused. It's a turning burst (her hips swing 47 degrees over 0.6 s), so it can't loop for circling.
- `katana.glb` is used twice, one in each fist on a BoneAttachment3D. The blades splay 12 degrees apart so they don't overlap in the two-handed swings.
- `ninja+character+3d+model.glb` (the unrigged Tripo original) is unused.

**Behaviour (`scripts/enemies/ninja_soldier.gd`):**
- STALK: runs in at 7.5 m/s (faster than the Hulk) and circles at 6.5 m for 1.0-2.4 s.
- POUNCE: Flip Kick. Code steers her body from takeoff to a spot right in front of the Hulk, so the jump fits any gap from 2.5 to 9 m. In the air she collides with the world only, so she sails over the crowd. The heel lands for 4.
- SLASH: the two-katana combo, 3 cuts for 2 each. She's rooted for the whole combo: that's the window to punch her.
- RETREAT: sprints back out, comes around from the other side, and stalks again.
- Full cycle if the Hulk stands still: 10 damage every ~6 s.

**Sound and feel:** new sfx group `ninja_hit` (the thudding punch pitched up 1.5x) is a stand-in until there's a real sword sound. Main adds shake on every hit, plus more shake and a short hit stop on the flip kick.

**Tests:** step 19 passed all 23 checks. It covers:
- one per wave, counted in the wave
- human sized, a katana in each fist, her own run clip, faster than the Hulk
- stalk, pounce from range, airborne flip, landing in his face, flip kick for 4, three cuts for 2, retreat and stalk again
- collision restored after the flip; sailing over a wall of 5 soldiers to land the kick
- punchable mid-combo; dies and counts as a kill; can be eaten mid-flip; stands down when the Hulk dies

Steps 4-18 pass, with these test fixes:
- Steps 7 and 18 turn ninjas off (they check wave counts).
- Step 15 expects 16 clips.

Two failures were already there before this step:
- Step 3's swarm check is the known flaky one.
- Step 14's "ground pound line cuts off the punch line" fails the same way with the ninja changes removed. Likely test timing (the pound starts while the punch is still swinging), not a voice bug. Not chased yet.

The soak test now handles ninjas.

**Step 13b (ninja afterimages), 2026-10-08.** Will's fix for a dark ninja on a dark floor: smoke afterimages.
- `scripts/vfx/afterimage_trail.gd` (`AfterimageTrail`) is reusable on any rigged character: add it as a child, call `setup(model)`.
- Every `interval` (0.07 s) while she's moving faster than `min_speed` (4 m/s), and for the whole flip, it bakes her skinned mesh in its current pose (`bake_mesh_from_current_skeleton_pose`) and copies the katanas. Each ghost is parented to the level, so it stays where she was.
- `shaders/afterimage.gdshader`: pale violet-white, brighter at the silhouette edge, no depth writes. Each ghost fades in (a new ghost sits right on top of her and would white her out), then breaks up into rising noise smoke and fades over `lifetime` (0.4 s). About 5 ghosts at a time.
- No ghosts while she stands in the combo: the trail shows motion, and standing still next to the Hulk she's easy to see.
- Cost: about 1.3 ms per snapshot on the lab's software renderer (much less on a GPU), roughly 14 snapshots per second while she's moving. Fine for one ninja. If ninjas ever come in groups, raise `interval` first.
- Headless runs (tests) turn the trail off: with no renderer, skinned meshes can't be baked.

**Tests:** steps 18 and 19 pass. A new rendered check (`shottrail.gd`, it needs a renderer) passes 6 of 6: trail on, ~5 ghosts while running and while flipping, none during the combo, and every ghost cleaned up after she dies.
- Step 18's "hands on the grips while running" is borderline flaky: it read 0.020 m against a < 0.02 limit once, then passed 3 of 3. It depends on where in the stride he spawns.

**Step 14 (scene split), 2026-10-08.** main.tscn is now the game shell; the arena is its own scene. No gameplay changes.
- `scenes/level/main.tscn` keeps what every level shares: WorldEnvironment, Sun, Hulk, Enemies, Deaths, Spawner, CameraRig, HUD, Music, Sfx. `Level` is now an instance of the arena scene.
- `scenes/level/arena_01.tscn` is the corridor: Floor, WallNorth, RailSouth, CapWest, CapEast, the two pillars, the Car, and `SpawnPoints` (West and East markers). Node names are unchanged, so `Level/Car`, `Level/PillarEast` and the rest still work.
- `scenes/level/pillar.tscn` is a reusable breakable pillar: drag it into any level and set `size` in the Inspector.
- Spawning reads Marker3D nodes in the `spawn_points` group, taking turns in scene order, each with a random spread (`WaveSpawner.spawn_spread`, 2 x 3 m). A new level sets its own spawn points by placing markers; no code changes. If a level has no markers, the old corridor ends are the fallback.
- Lighting and environment stay in main for now. If levels later need their own mood, move them into the level scene. Only one WorldEnvironment can be active, so stacked sections should share one.

**Tests:** step 20 passed all 11 checks. It covers:
- the arena is an instance, and every wall, cap, pillar and the car sit exactly where they were
- the pillars are pillar.tscn instances and still breakable; the floor keeps its asphalt
- spawns alternate between the markers within the spread; moving a marker moves the spawns; no markers falls back

A rendered frame matches the old view. Steps 4-13, 15, 16, 18 and 19 pass. Pre-existing flaky or failing ones, unchanged by the split:
- step 3: the known swarm count
- step 14: the pound-line check (already failing)
- step 17: "5 of 6 got round" failed 1 in 3 runs with the old main.tscn and 2 in 3 with the new one, so it's randomness. It's worth a look later.

**Step 15 (new sounds), 2026-10-08.** Will added a sword, rocket, throw and eat sounds. Levels measured with ffmpeg as before.
- **Sword:** `ninja_hit` now uses `Heavy_sword_chopping_#2`. That file holds a sharp chop (0-0.42 s) and then a slow swelling whoosh (0.9-1.65 s), so Sfx gained optional `start`/`end` per group to play just a slice. A hit plays only the chop. The whoosh is unused for now; it could become a swing sound timed to land on each cut.
- **Rocket:** `rocket_launch` is `Heavy_rocket_launch_#4`; `rocket_boom` is `violent_explosion_#3`; the cannonball stand-ins are gone. New `rocket_flyby` (`Rocket_flying_past_#2`) plays once when a rocket comes within `Rocket.flyby_distance` (6 m) of the Hulk. That's about a third of a second of "incoming!" before a direct hit, and the whoosh on a near miss.
- **Voice:** `throw_1-3` and `eat_1-3` fill HulkVoice's throw_lines and eat_lines, with measured lead trims (55-125 ms).
- **Voice priority change:** a newer ACTION line (pound, lift, throw, eat) now cuts off an older one; before, equal priority couldn't interrupt. Pound lines run up to ~5 s, so the old rule meant a lift right after a pound stayed silent, and a throw right after the lift never got its line. Punch grunts still never interrupt anything.

**Tests:** step 21 passed all 13 checks. It covers:
- every new clip loads
- the chop stops at the end of its slice
- launch, then whoosh, then boom, in that order; a near miss 1.5 m away still whooshes
- throw and eat lines play past their lead silence

Step 14's long-standing failure was the test: it fired a ground pound mid-punch, which the game correctly refuses. With that fixed, the test exposed the real priority problem above. Step 14 now passes 3 of 3, with a new check that the throw line cuts off the lift line. Step 15 expects 17 clips. Steps 12, 13, 16, 18, 19 and 20 pass.

**Roguelike plan (locked 2026-10-08).**
- A run is 14 standard waves. On wave 15 the wave dies, the game fakes a win, then the boss arrives. Kill the boss to win.
- Grunts stay one-hit kills. The rocket soldier and ninja get 2-4 hits. The boss has a health pool.
- After each wave you pick 1 of 3 augments.
- Build order: kill causes and the Run record (done), then the run summary screen with New Run (replaces "Press R to rise again"), then the augment system with 6-8 cheap augments, then the expensive augments (new attacks, helper), then the boss.

**Step 16 (kill causes + Run record), 2026-10-08.** The base the summary and augments sit on.
- `scripts/game/kill_cause.gd` (`KillCause`) lists how a soldier can die, with summary names: Smashed (punch), Stomped (pound), Eaten, Crushed (car hit or pin), Buried (rubble), Friendly Fire (rocket blast), Fell (off the level).
- `Human.kill()` and `pin_to()` now take a cause and set `Human.death_cause` before `died` fires. Every call site passes the right one; the ninja and rocket soldier pass it through.
- `scripts/game/run.gd` (`Run`), a node in main.tscn, records the run:
  - kills by cause, specials killed by name, juggles, wall splats, waves cleared
  - augments (an empty list for now) and the score
  - `summary()` returns everything the end screen will show
- The spawner gained `human_died(human)`. Punch and pound gained `juggled(count)`. Main wires those, plus the death director's `splatted` and the wave signals, into the Run.
- Specials carry `kind_name` and `bounty` (Human exports): the rocket soldier and ninja are each worth 150 extra.
- **Score:**
  - Kill points by cause: Smashed 10, Stomped 10, Fell 15, Crushed 20, Buried 25, Eaten 30, Friendly Fire 35.
  - Kill points are multiplied by the wave: x1.0 at wave 1, +0.1 per wave.
  - Bonuses: juggle 40, wall splat 15, wave clear 100 x wave number.
  - All of it is tunable on the Run node.
- The HUD shows SCORE next to KILLS.

**Tests:** step 22 passed all 19 checks. It covers:
- each cause, produced by the real move where practical: punch, pound, eat, car sweep, rubble hit, rocket blast, falling off
- the bounty and the specials list
- juggle and splat points, the wave multiplier, the wave clear bonus
- summary order and totals; the HUD score

Steps 4-21 pass (step 7 now expects the score on the HUD line). Step 3 is still the known flaky swarm count.

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
- **RocketSoldier (rocket_soldier.tscn):** max_range, preferred_range, min_range, kneel_time, aim_time, reload_time, show_aim_laser
- **Rocket (scripts/weapons/rocket.gd):** speed, max_life, blast_radius, max_damage, min_damage, blast_launch, flyby_distance
- **RocketPose (vars in rocket_pose.gd):** launcher_scale, launcher_offset, torso_twist, kneel_drop, kneel_lean, recoil_time, recoil_back, recoil_pitch, recoil_lean
- **Spawner > Rocket soldiers:** rocket_soldier_scene, rocket_soldiers_per_wave, rocket_spawn_at
- **Main > Rockets:** rocket_launch_shake, rocket_boom_shake, rocket_hit_shake, rocket_hit_stop
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
- **NinjaSoldier (ninja_soldier.tscn):** move_speed, stalk_range, stalk_time_min/max, pounce_min/max, flip_damage, slash_damage, strike_reach, flip_speed, slash_speed, retreat_time, katana_scale, grip_point, blade_splay_degrees
- **Spawner > Ninjas:** ninja_scene, ninjas_per_wave, ninja_spawn_at
- **Spawner > Spawn points:** spawn_spread. The markers themselves live in the level scene (`Level/SpawnPoints`)
- **Main > Ninja:** ninja_hit_shake, ninja_flip_shake, ninja_flip_hit_stop
- **AfterimageTrail (created in code by the ninja, so edit the defaults at the top of `scripts/vfx/afterimage_trail.gd`):** interval, lifetime, min_speed, smoke_color, rim_color, base_alpha, grow, enabled. Shader extras in `shaders/afterimage.gdshader`: rim_power, smoke_scale, fade_in
- **Run (main.tscn):** points_smashed / stomped / eaten / crushed / buried / friendly_fire / fell / other, juggle_points, splat_points, wave_clear_points, wave_multiplier_step
- **Score on enemies (Human exports, set per scene):** kind_name, bounty
