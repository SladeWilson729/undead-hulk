# Painterly cel materials

Drag `asphalt.tres` or `brick.tres` into a MeshInstance3D's Material Override.
Open `res://scenes/material_preview/material_preview.tscn` and press F6 for the study scene.
The main game scene is unchanged. No external textures or plugins are required.

## Art controls

- Asphalt: blue-gray paint, scattered aggregate, broken cracks. Adjust Base Color, Paint Color, Brush Strength, Aggregate Strength, Crack Strength and Meters Per Pattern. Default seed: 7.
- Brick: terracotta running bond with dark mortar and painted edge shading. Adjust Brick Color, Light Color, Mortar Color, Mortar Width, Edge Wear and Brick Variation. Default seed: 13. Brick Size Meters defaults to 0.5 × 0.22, including mortar.
- Both: three direct-light bands, matte finish, real light attenuation and shadows. Ambient lighting fills shadows; excessive ambient energy will reduce the cel effect. Painted bevels are color detail, not geometry or normal-map relief.
- Duplicate a material before creating an independent variant. All source is editable in the adjacent shader files; `paint.gdshaderinc` holds shared paint noise.

## Mapping

World Mapping is enabled by default. Asphalt projects onto world XZ for horizontal streets. Brick selects the dominant world axis for flat architectural faces, preserving scale on resized meshes. This mapping is intended for static architecture: moving objects slide through the pattern, and curved or diagonal surfaces can show projection transitions.

For UV-authored or moving meshes, disable World Mapping. Brick then uses Bricks Per UV; choose counts appropriate to the mesh aspect ratio. Asphalt uses UV divided by Meters Per Pattern as its pattern coordinates in this mode (the value becomes a UV scale). Noise is continuous in world space, but these shaders do not promise matching paint at arbitrary wrapped UV seams. They are procedural materials, not exported seamless image tiles.

## Validation — 2026-10-06

Rendered and visually inspected with Godot 4.7.2, Forward+, NVIDIA RTX 3060. Default warm brick/cool asphalt and a gray-brick variant with maximum mortar width and edge wear were inspected. An initial version also rendered in Compatibility; the final package was validated in Forward+.

`preview.png` is the default engine capture; `variant.png` demonstrates alternate colors and parameters. To reproduce, run Godot with the project path and scene above, followed by `-- --capture`; add `--variant` for the alternate study. The variant does not alter the saved materials. Its title retains the default palette names.

No shader or scene errors were reported. The restricted environment prevented writing Godot's user shader cache; rendering and PNG captures succeeded. Performance has not been benchmarked at game scale.

Lighting implementation follows the [Godot spatial shader reference](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html).
