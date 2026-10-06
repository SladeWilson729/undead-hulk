# Undead Hulk — independent gamer / streamer review

Date: October 6, 2026
Reviewer: separate AI playtest agent using an experienced action-game player and Twitch-host perspective; no claim of human playtesting or real streaming credentials.

## Verdict

The strongest hook is already visible: a huge painted monster turns a tiny soldier swarm into airborne chaos. The stomp is the signature shot. This is a promising arcade combat prototype, but the current corridor and repeated melee rushes need more decisions and a stronger run structure before they can support a long play session or broadcast.

## Method and limits

Launched the actual Godot 4.7.2 Forward+ build on the available RTX 3060. Inspected the running game through Windows screenshots. Native R taps did not reliably reach the game, so this review does not rate keyboard/mouse latency or manual aiming feel.

Used an isolated rendered gameplay harness, `tools/gamer_review_play.gd`, with normal movement actions and the existing punch/stomp entrypoints. It aims automatically at the closest soldier, moves left initially, then approaches distant targets later. It does not alter health, wave sizes, enemy behavior, attack damage, cooldowns, or assets. This is a scripted playtest, not an uninterrupted human-controlled session. The first 26.7-second action-injection attempt failed to drive aiming/stomp reliably; its death is excluded from balance judgments. Its restart event correctly restored 100 HP and zero kills.

Screenshots are actual rendered gameplay frames. Timing is simulated game time, not a performance benchmark. The environment reported an unavailable user shader-cache directory. No audio listening test, exported-build test, controller test, or late-wave endurance test was performed. Code inspection only supports the feature inventory; observations below come from the rendered session.

## Runtime results

The valid rendered run lasted 90.0 seconds of active simulated gameplay, followed by 11.8 seconds deliberately idle until death. It reached wave 5 with 113 kills and 69 HP before the idle phase. It completed 114 punch swings and two stomps. Hit-signal totals include possible corpse juggles and should not be treated as unique kills. Restart returned to 100 HP, zero kills and the initial wave countdown.

| Milestone | Game time | HP | Total kills |
|---|---:|---:|---:|
| Wave 2 begins | 20.1 s | 97 | 12 |
| Wave 3 begins | 40.3 s | 85 | 32 |
| Wave 4 begins | 60.3 s | 77 | 60 |
| Wave 5 begins | 82.1 s | 72 | 96 |
| Active test ends | 90.0 s | 69 | 113 |

The basic auto-aim strategy sustained the early waves with limited repositioning and only two stomps. That suggests early combat could benefit from more tactical variety; it is not proof that a new human player will find it easy. Automated aim is a substantial advantage.

## What works

- **Immediate power fantasy.** Hulk's size against the soldiers communicates the premise without exposition. Painting on the characters and asphalt is visible at normal play scale.
- **Stomp is a strong visual payoff.** The force arcs, radial cracks, flying bodies and wave-clear response combine into a recognizable spectacle. Keep this as the centerpiece of trailers and short clips.
- **Two attacks have distinct jobs.** Punching singles out nearby targets; stomp turns surrounding bodies into a crowd-clear moment. The cooldown offers a clear recovery rhythm.
- **Readable basic status.** Health, kills, current wave, and stomp availability are easy to locate. The wave countdown tells the player when the next fight begins.
- **Fast restart foundation.** Actual restart event testing reset HP, kills, and wave state. That is essential for an arcade game built around repeated attempts.

## What holds it back

- **The arena lacks things to do with the strength fantasy.** The test takes place in one long bare corridor. Enemies provide most of the change; the street itself offers little interaction or route choice.
- **Enemy variety currently reads primarily as costumes.** Different soldiers converge into similar close-range melee piles. Visual inspection showed bodies overlapping around Hulk; source inspection confirms the shared chase/contact-attack behavior. This reduces tactical and spectator readability.
- **Big effects are stronger than the run's goals.** The session communicates survive/kill/next wave, but offers no visible upgrade decision, objective twist, combo target, or larger destination. This limits the narrative a streamer can build around a run.
- **Presentation has competing styles.** Painted characters and brickwork are attractive, but very saturated flat red splats draw attention away from them. Large plain wave banners and substantial blank space above the arena make it look more like a prototype than a finished comic-book game.
- **Crowd damage needs clearer explanation.** A red hurt flash reports that damage occurred, but overlapping soldiers obscure which attack caused it. A viewer can see chaos more easily than successful defensive decisions.

## Recommended additions, in order

| Priority | Addition | Concrete first version | Benefit |
|---|---|---|---|
| 1 | Destruction that changes combat | Add one throwable parked car and a breakable wall section; reward hitting several soldiers with the same object. | Converts the existing strength fantasy into player choices and repeatable clip moments. |
| 2 | Three distinct enemy roles | Keep the melee swarm; introduce a shield soldier vulnerable from behind or to stomp, and a ranged soldier with a clear aim line and windup. Introduce one role at a time. | Creates target priority, movement decisions, and readable danger without just inflating health. |
| 3 | Combo/style scoring | Award escalating points for launch → juggle → wall impact; show a brief named combo and a personal-best comparison at death. | Makes spectacular play measurable and gives a streamer a challenge to narrate. Existing wall comics and juggling are natural foundations. |
| 4 | Short run progression | Every few waves, offer three upgrades: wider stomp, ricochet throws, or rage healing earned through aggressive play. Add a named encounter at a fixed milestone. | Gives each run a build, a risk/reward decision, and an endpoint worth reaching. Tune after baseline manual playtests. |
| 5 | Comic presentation and sound pass | Integrate compact ink-panel HUD, mute the splat color, add optional threat indicators and shake/flash controls. Add layered punch/stomp/wall-crash sounds and a stomp-ready cue. | Supports readability and perceived impact. Audio is a recommendation from source inventory: no AudioStream gameplay system was found, and sound was not auditioned. |
| 6 | Stream-friendly challenge layer | Daily seeded runs or local challenge presets such as wall-impact-only scoring, plus a results card with best combo, biggest stomp, and wave reached. | Creates repeatable broadcasts and audience predictions. Twitch integration can wait until the core loop earns repeat plays. |

## Suggested next milestone

Build a polished five-wave slice: existing swarm, one new enemy role, one throwable object, one upgrade choice, and a score/results screen. Test whether people choose a second run without being prompted. That is a more useful milestone than adding many more cosmetic effects first.

## Evidence

- `stomp-1.png`: actual crowd-clear impact, force arcs, cracked street, and launched soldiers.
- `play-030.png`: ordinary wave-two combat view, HUD and environment composition.
- `death.png` and `restart.png`: end-of-run and restart states.
- `playtest.log`: wave/HP/kill timeline and harness results.

The POW/OOF/BIFF implementation exists, but this session did not reliably capture the brief wall words. Their in-motion readability remains unassessed; I would not call them broken or claim to have verified them here.

