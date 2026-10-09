# Run-end popup

Implemented in scripts/ui/run_end_popup.gd, connected by HUD on Health.died.
Death and victory share the layout: summary "won" swaps the headline (DEAD. AGAIN. / SMASHED IT!),
the starburst and the subtitle ("fell on wave N of 15" / "all 15 waves + boss"). The 1.2-second death delay is preserved.
Presentation: vector ink outlines, skewed paper, deterministic print flecks, halftone,
coral headline and slime-green score/retry accents. Live labels use system Impact /
Trebuchet with DejaVu fallback. No external artwork or font files are required.
The 1080 x 850 design fits the viewport; mouse and focused keyboard button activate retry;
the existing R shortcut remains available.

Run scoring defaults (wave multiplier +0.25 per wave, x4.25 on wave 14): Smashed 10, Stomped 15, Eaten 30, Crushed 20, Buried 25,
Friendly Fire 35, Fell 15, Other 10. Kills and special bounties multiply by current
wave. Juggles award 40 x wave; wall splats award 15 x wave. Each cleared wave
awards 100 x wave. Juggles are post-death style events, not duplicate enemy kills.
Run freezes on player death. Best score saves to user://run_best_v1.cfg. A failed
save is reported in the popup. Future score rebalance should version that save file.

Validation: Godot 4.7.2, Windows, OpenGL compatibility, RTX 3060.
- tools/run_end_preview.gd: arithmetic, special bounty, style, duplicate wave clear,
  post-death freeze and best score reload passed. Add -- --render to render sample data.
- tools/run_end_integration.gd: actual player health death, popup delay, button focus,
  retry signal and fresh run passed. Existing sound assets produced loader errors.
- docs/run-end-popup.png and run-end-popup-small.png: inspected sample data at large
  and 960 x 540 viewports. docs/run-end-in-game.png: actual death integration capture.
- Tests use temporary res://docs save files, removed on success, and a workspace-local
  APPDATA directory to isolate the user's actual best score.
- Automated integration activates the button signal; manual mouse/controller playtest
  and a packaged export were not performed.

Run from the project directory:
    godot --headless --path . --script res://tools/run_end_preview.gd
    godot --path . --rendering-method gl_compatibility --script res://tools/run_end_integration.gd

Revisions (Claude, 2026-10-08):
- Button reads NEW RUN [R] (node "NewRun"); there is no revive.
- Fell has its own row (7 cause rows, CAUSE_ROWS); "Other mishaps" now counts only Other.
- Headline auto-sizes to fit inside the coral banner (_fit_size).
- AUGMENTS CLAIMED row: count plus names, wrapped to two lines and trimmed with "...".
- Class name RunEndPopup; HUD keeps it in hud.end_popup.
- Tool assertions updated for the 0.25 multiplier: preview 486, integration 120.
