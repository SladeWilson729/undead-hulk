# Painterly cel characters

The Hulk and all four soldiers now use `res://shaders/painterly_character.gdshader` at runtime. Imported FBX resources remain unchanged. Original albedo textures, colors, UV transforms and the Hulk's normal map are carried into shared converted materials. The existing damage overlay is untouched, and reparented ragdoll/flying-body visuals keep their surface overrides.

## Art controls

Edit `assets/materials/painterly/hulk_character.tres` or `soldier_character.tres` and restart the running scene to refresh cached materials. These are style presets: the character setup fills their source textures automatically. For a standalone mesh, assign the shader and supply its albedo texture yourself.

- **Palette Strength / Palette Steps:** flatten texture luminance into painted color patches while retaining hue. Lower strength preserves more original detail.
- **Brush Strength / Brush Scale:** restrained UV-anchored pigment variation; follows skinned animation rather than sliding through world space. UV seams can also be pigment seams.
- **Texture Softness:** mip bias that reduces photographic detail. Keep low for recognizable faces/camouflage.
- **Mid Threshold / Highlight Threshold / Band Softness:** three lighting levels with narrow softened transitions.
- **Shadow Color / Shadow Fill / Highlight Color:** cool shadow and warm highlight palette. Ambient environment light is intentionally replaced by a fixed painted fill, so the characters remain slightly visible without direct light; reduce Shadow Fill for dark scenes.
- **Normal Strength:** reduces noisy normal-map shading while preserving the Hulk's sculpted surface.
- **Contour Strength:** darkens grazing angles for drawn-looking forms. This is surface shading, not an expanded silhouette outline.

On Hulk or Human nodes, turn off **Painterly Enabled** before running for the original look, or assign another Paint Style preset. Materials are cached per source/preset, so identical soldier variants share resources. Presets are copied on first use; changes during a running session do not propagate to cached copies.

Current imports were checked: all five are opaque, backface-culled, single-surface materials. The conversion skips transparent and nonstandard shader materials. Future assets using emission, unusual culling, secondary UVs or special texture channels need additional conversion support.

## Validation — October 6, 2026

Rendered and visually inspected original and painted lineups in Godot 4.7.2 Forward+ on RTX 3060. Checks passed for all five characters receiving the shader, albedo retention, Hulk normal-map retention, damage overlay, material sharing, and ragdoll transfer. No script or shader errors. Shader-cache access warning occurs under the restricted environment but does not prevent rendering.

Run `godot --path . --fixed-fps 60 -s tools/character_style_preview.gd`. Add `-- --original` for the comparison. Images: `docs/characters-painted.png` and `docs/characters-original.png`. Other renderers, mobile performance and large-wave performance are untested. Custom light functions require per-pixel shading (do not enable forced vertex shading).
