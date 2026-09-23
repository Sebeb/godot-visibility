# Visibility system

UID: sdoc-5e7cd4de-7980-4853-a7d2-0999a92fd91c

## System Design

### Purpose

This addon owns fog-of-war capture, explored-memory surfaces, visibility-mask
simulation, and render-mask composition. A host owns world topology and game
policy. The addon never queries a generator, renderer, room model, discovery
model, or sound propagation system.

### World contract

`FogCameraManager.configure_world(grid_size, settings)` is the only world
configuration entry point. `grid_size` is a rectangular cell extent.
`VisibilityWorldSettings` contains exactly:

- `cell_size`
- `wall_thickness`
- `wall_height`

The manager derives its padded capture rectangle and render-target size from
those values. Calling `configure_world` again resets capture history and updates
registered reveal-source scaling.

### Geometry and reveal input

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

### Output contract

The built-in named surfaces are `current_visibility` and `fog_of_war`.
Additional host surfaces use
`register_render_mask_surface(name, texture)` and
`unregister_render_mask_surface(name)`. Consumers read through
`get_render_mask_texture(name)` and track changes through
`get_render_mask_texture_revision(name)`.

Shaders consuming these masks include `sprite_visibility_masked.gdshader` for
sprite alpha, `object_origin_visibility_tint.gdshader` for origin-sampled tint,
and `view_distance_mask.gdshader` for distance-limited visibility. They are
examples of the consumer contract, not game-specific policy.

When explored memory changes, the manager emits
`fog_history_surface_updated(dirty_uv_rects)`. Host discovery or bookkeeping
systems may subscribe to that signal; the addon contains no such policy.

### Tuning and optional host state

Every manager exposes one `VisibilityTuning` resource. It owns the shipped fog
memory decay defaults and may hold a `state_adapter`, which is null by default.
Without an adapter, authored and shipped defaults are the complete source of
truth.

An adapter is duck-typed. It implements
`get_value(path: StringName, default_value: Variant) -> Variant` and
`connect_changed(path: StringName, callback: Callable) -> void`. It may also
implement `disconnect_changed(path, callback)` so nodes can detach during
teardown. Change callbacks receive the new value as their only argument.

`FogMemoryDecayConfig.tuning_path` optionally namespaces its rate and map-open
multiplier. `FogMemoryDecaySource3D.enable_state_path` optionally gates one
source, while `VisibilityTuning.viewing_map_state_path` controls the shared
map-open multiplier. Empty paths disable the corresponding adapter lookup.

### Explicit exclusions

The extraction intentionally excludes the source game's sound-light field,
built-in camera-room transitions, wall-knowledge controller, cell-discovery
controller, and visible-area coverage policy. The generic named-mask registry
and the standalone render-layer compositor remain available.

## System Implementation

`plugin.gd` registers `FogCameraManager` as an editor type and creates no
runtime nodes. `runtime/fog_camera_manager.gd` owns the capture viewports,
surface registry, source and blocker registration, and memory-decay controller.
The remaining scripts in `runtime/` provide the pushed geometry components,
decay scheduling, mask simulation, and compositors. Shaders and compute kernels
live under `rendering/`.

`runtime/visibility_tuning.gd` is the only host-state boundary. Callers assign
its `state_adapter` at runtime when they need live host values. All adapter
calls are guarded by method checks, and a missing adapter returns the supplied
default. `FogMemoryDecaySource3D` obtains the same tuning instance from its
manager, attaches optional change callbacks, and detaches them when the adapter
supports `disconnect_changed`.

The portable runtime uses the `visibility_manager`, `visibility_blocker_2d`,
`visibility_reveal_source_2d`, and `visibility_segment_provider` groups. The
`FogCameraManager` class name remains unchanged to avoid unnecessary consumer
churn.

Portability is checked by enabling the addon in an otherwise empty Godot 4.7.2
project, then instantiating the tuning resource, manager, config, and decay
source in a headless script. The probe verifies defaults, adapter overrides,
group registration, and adapter-controlled source disablement.

### Source provenance

The original files were extracted from `Sebeb/Pills-God` at commit
`ff0b89d1840cb2a3c411f52a607183a15db1dfcf`. See `README.md` for the complete
inventory and licence attribution.
