# Godot Visibility

A Godot 4 addon containing the fog-of-war, visibility-mask, and render-layer
composition code extracted from
[Sebeb/Pills-God](https://github.com/Sebeb/Pills-God) at commit
[`ff0b89d1840cb2a3c411f52a607183a15db1dfcf`](https://github.com/Sebeb/Pills-God/tree/ff0b89d1840cb2a3c411f52a607183a15db1dfcf).

This first commit is an attribution and provenance checkpoint. The source
artifacts listed below are copied byte-for-byte from the pinned commit, with
only their directories changed. They still contain Pills-God-specific
dependencies and are not yet portable to an unrelated host project.

## Extracted files

The following source paths were taken. Files from `systems/maze/` and
`systems/perception/` are now under `runtime/`; files from `rendering/` retain
their relative paths under `rendering/`; the technical specification is now
`system-doc.md`.

### Runtime

- `systems/maze/fog_camera_manager.gd`
- `systems/maze/fog_camera_manager.gd.uid`
- `systems/maze/fog_memory_decay_config.gd`
- `systems/maze/fog_memory_decay_config.gd.uid`
- `systems/maze/fog_memory_decay_controller.gd`
- `systems/maze/fog_memory_decay_controller.gd.uid`
- `systems/maze/fog_memory_decay_controller.tscn`
- `systems/maze/fog_memory_decay_source_3d.gd`
- `systems/maze/fog_memory_decay_source_3d.gd.uid`
- `systems/maze/fog_memory_decay_source_3d.tscn`
- `systems/maze/fog_memory_dissolve_profile.gd`
- `systems/maze/fog_memory_dissolve_profile.gd.uid`
- `systems/maze/organic_visibility_mask_scheduler.gd`
- `systems/maze/organic_visibility_mask_scheduler.gd.uid`
- `systems/maze/organic_visibility_mask_simulation.gd`
- `systems/maze/organic_visibility_mask_simulation.gd.uid`
- `systems/maze/packed_visibility_capture.gd`
- `systems/maze/packed_visibility_capture.gd.uid`
- `systems/maze/render_layer_compositor.gd`
- `systems/maze/render_layer_compositor.gd.uid`
- `systems/maze/render_mask_composition.gd`
- `systems/maze/render_mask_composition.gd.uid`
- `systems/maze/render_mask_compositor.gd`
- `systems/maze/render_mask_compositor.gd.uid`
- `systems/maze/wall_mask_resampler.gd`
- `systems/maze/wall_mask_resampler.gd.uid`
- `systems/perception/fog_blocker_2d.gd`
- `systems/perception/fog_blocker_2d.gd.uid`
- `systems/perception/fog_blocker_2d.tscn`
- `systems/perception/fog_reveal_source_2d.gd`
- `systems/perception/fog_reveal_source_2d.gd.uid`
- `systems/perception/fog_reveal_source_2d.tscn`

### Rendering

- `rendering/visibility_mask_common.gdshaderinc`
- `rendering/visibility_mask_common.gdshaderinc.uid`
- `rendering/fog_glow_diffusion.gdshader`
- `rendering/fog_glow_diffusion.gdshader.uid`
- `rendering/fog_history_merge.gdshader`
- `rendering/fog_history_merge.gdshader.uid`
- `rendering/fog_world_mask_2d.gdshader`
- `rendering/fog_world_mask_2d.gdshader.uid`
- `rendering/fog_world_mask_3d.gdshader`
- `rendering/fog_world_mask_3d.gdshader.uid`
- `rendering/sprite_visibility_masked.gdshader`
- `rendering/sprite_visibility_masked.gdshader.uid`
- `rendering/sprite_visibility_masked.tres`
- `rendering/object_origin_visibility_tint.gdshader`
- `rendering/object_origin_visibility_tint.gdshader.uid`
- `rendering/view_distance_mask.gdshader`
- `rendering/view_distance_mask.gdshader.uid`
- `rendering/wall_mask_resample.gdshader`
- `rendering/wall_mask_resample.gdshader.uid`
- `rendering/render_mask_composite.gdshader`
- `rendering/render_mask_composite.gdshader.uid`
- `rendering/render_layer_color_composite.gdshader`
- `rendering/render_layer_color_composite.gdshader.uid`
- `rendering/render_layer_mask_visualization.gdshader`
- `rendering/render_layer_mask_visualization.gdshader.uid`
- `rendering/compute/visibility_mask_creep.glsl`
- `rendering/compute/visibility_mask_creep.glsl.import`
- `rendering/compute/visibility_mask_halo.glsl`
- `rendering/compute/visibility_mask_halo.glsl.import`
- `rendering/compute/visibility_mask_pack.glsl`
- `rendering/compute/visibility_mask_pack.glsl.import`
- `rendering/compute/visibility_mask_phase.glsl`
- `rendering/compute/visibility_mask_phase.glsl.import`
- `rendering/compute/visibility_mask_present.glsl`
- `rendering/compute/visibility_mask_present.glsl.import`

### Documentation and licence

- `systems/fog-camera-manager-tech-spec.md`
- `LICENSE`

`plugin.cfg`, `plugin.gd`, and this README were authored for the extracted
repository and are not represented as copied source files.

## Installation

Add this repository at `addons/visibility` in a Godot project and enable the
Visibility plugin. Portability work is intentionally deferred until after this
provenance commit.

## Licence

MIT. The original `Copyright (c) 2025 Korin` notice is preserved in
[`LICENSE`](LICENSE).
