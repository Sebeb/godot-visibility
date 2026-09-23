# Visibility system

## Purpose

This addon owns fog-of-war capture, explored-memory surfaces, visibility-mask
simulation, and render-mask composition. A host owns world topology and game
policy. The addon never queries a generator, renderer, room model, discovery
model, or sound propagation system.

## World contract

`FogCameraManager.configure_world(grid_size, settings)` is the only world
configuration entry point. `grid_size` is a rectangular cell extent.
`VisibilityWorldSettings` contains exactly:

- `cell_size`
- `wall_thickness`
- `wall_height`

The manager derives its padded capture rectangle and render-target size from
those values. Calling `configure_world` again resets capture history and updates
registered reveal-source scaling.

## Geometry and reveal input

Hosts push geometry instead of exposing topology:

- `FogBlocker2D` owns a static polygon and registers through the
  `visibility_blocker_2d` group.
- Dynamic nodes join `visibility_segment_provider` and implement
  `get_visibility_segments_2d()`. Each entry is a dictionary with `start` and
  `end` vectors. An optional `get_visibility_segments_2d_revision()` avoids
  rebuilding unchanged geometry.
- `FogRevealSource2D` registers itself and supplies its capture light, effective
  origin, range, shape, and facing.

`FogRevealSource2D.corner_peek_solver` is an optional `Object`. When present it
must implement `solve_corner_peek(origin: Vector2, facing: Vector2) -> Vector2`.
The returned vector is an offset in the same local world space. Null selects
the no-peek path.

## Output contract

The built-in named surfaces are `current_visibility` and `fog_of_war`.
Additional host surfaces use
`register_render_mask_surface(name, texture)` and
`unregister_render_mask_surface(name)`. Consumers read through
`get_render_mask_texture(name)` and track changes through
`get_render_mask_texture_revision(name)`.

When explored memory changes, the manager emits
`fog_history_surface_updated(dirty_uv_rects)`. Host discovery or bookkeeping
systems may subscribe to that signal; the addon contains no such policy.

## Explicit exclusions

The extraction intentionally excludes the source game's sound-light field,
built-in camera-room transitions, wall-knowledge controller, cell-discovery
controller, and visible-area coverage policy. The generic named-mask registry
and the standalone render-layer compositor remain available.

## Source provenance

The original files were extracted from `Sebeb/Pills-God` at commit
`ff0b89d1840cb2a3c411f52a607183a15db1dfcf`. See `README.md` for the complete
inventory and licence attribution.
