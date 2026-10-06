# Comic wall impacts

Hard human wall hits cycle POW!, OOF!, BIFF! with jagged ink outlines, red/cyan accents, yellow halftone paper and cream lettering. Each burst pops, settles, drifts upward and fades within 0.85 game seconds. Nearby simultaneous bursts stagger vertically. Artwork is drawn in code; SystemFont prefers Impact, then Arial Black/DejaVu Sans, with Godot fallback on other platforms.

DeathDirector owns the presentation layer. Living humans supply actual move-and-slide collision normals. Ragdoll bones and cheap flying bodies use the existing sudden-velocity-change detector, then confirm a nearby vertical world surface along their incoming horizontal direction. This latter path is an approximation using a 0.85 m ray, not a contact manifold. Floor normals and impacts below 6.5 m/s are rejected. Per-human 900 ms suppression prevents limb-by-limb duplicate bursts; at most six are visible.

Tune the Deaths node's Comic Wall Impacts group: enabled, minimum speed and maximum visible count. The words/style and animation are in `scripts/vfx/comic_wall_impact.gd`. Camera-facing artwork is a screen overlay anchored at impact; it intentionally remains legible over geometry. No damage, splat or launch behavior is changed.

Validation: `godot --path . --fixed-fps 60 -s tools/comic_impact_preview.gd` launches an actual ragdoll, cheap body and living shoved human into the bridge wall. Checks one burst per human, floor/low-speed rejection and cleanup, and saves `docs/comic-wall-impact.png`. Passed in Godot 4.7.2 Forward+ on RTX 3060 on October 6, 2026. Rendered capture inspected. The user shader-cache directory warning is unrelated to effect rendering. Other platforms/fonts and crowded gameplay performance remain untested.
