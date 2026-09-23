extends RefCounted
class_name OrganicVisibilityMaskScheduler

## Fixed-rate tick scheduler for the organic visibility-mask simulation.
##
## This is deliberately a pure, Node-free, GPU-free object so the frame-rate
## equivalence requirement can be proven by arithmetic rather than asserted.
## Two properties make 30 / 60 / 144 FPS behaviour equivalent:
##
## 1. The executed tick count is derived from TOTAL elapsed simulation time
##    (`floor(elapsed * ticks_per_second)`), not accumulated per frame. A frame
##    subdivision can therefore never drift: after T seconds every frame rate
##    has executed the same number of ticks, and a rounding disagreement is
##    bounded at one tick regardless of how many frames produced T.
## 2. Creep substeps are metered PER TICK, not per frame. The number of creep
##    dilations that accompany tick N is a pure function of N, so the whole
##    simulation is a pure function of the tick count and inherits property 1.
##
## PGO-233 shipped a bug where per-render-frame differencing of physics-driven
## state collapsed to zero on tickless frames. Nothing here differences anything
## per frame: `advance()` consumes a delta and emits whole ticks, and a frame
## that produces zero ticks produces zero work rather than a degenerate step.

## Real time consumed so far, in seconds. Only ever advanced by `advance()`.
var _elapsed_seconds := 0.0
## Ticks already handed out. Never decreases except when catch-up is capped or
## the scheduler is reset.
var _executed_ticks := 0
## Fractional creep substeps carried between ticks.
var _creep_remainder := 0.0
## Ticks dropped because catch-up was capped, for the debug snapshot.
var _dropped_ticks := 0
var _total_creep_steps := 0


## Consumes `delta` seconds and returns one entry per tick to execute, each
## holding the number of ordered creep dilation substeps that tick owes.
## An empty result means this frame has no simulation work at all.
func advance(
	delta: float,
	ticks_per_second: float,
	creep_steps_per_tick: float,
	max_catch_up_steps: int
) -> PackedInt32Array:
	var steps := PackedInt32Array()
	var rate := maxf(0.0001, ticks_per_second)
	_elapsed_seconds += maxf(0.0, delta)
	var target_ticks := int(floor(_elapsed_seconds * rate))
	var pending := target_ticks - _executed_ticks
	if pending <= 0:
		return steps
	var cap := maxi(1, max_catch_up_steps)
	if pending > cap:
		# Drop the backlog instead of trying to work it off. Re-baselining the
		# executed count (rather than leaving it behind) is what prevents an
		# unrecoverable spiral: a hitch costs simulation time, never a growing
		# per-frame debt that guarantees the next frame is late too.
		_dropped_ticks += pending - cap
		_executed_ticks = target_ticks - cap
		pending = cap
	for _index in pending:
		_creep_remainder += maxf(0.0, creep_steps_per_tick)
		var creep_steps := int(floor(_creep_remainder))
		_creep_remainder -= float(creep_steps)
		_total_creep_steps += creep_steps
		steps.append(creep_steps)
	_executed_ticks += pending
	return steps


## Returns the tick index this scheduler has advanced to. The simulation state
## is a pure function of this number, which is what the frame-rate equivalence
## checks compare.
func get_executed_ticks() -> int:
	return _executed_ticks


func get_total_creep_steps() -> int:
	return _total_creep_steps


func get_dropped_ticks() -> int:
	return _dropped_ticks


func get_elapsed_seconds() -> float:
	return _elapsed_seconds


func reset() -> void:
	_elapsed_seconds = 0.0
	_executed_ticks = 0
	_creep_remainder = 0.0
	_dropped_ticks = 0
	_total_creep_steps = 0


## Replays a whole run at a fixed frame rate and reports the totals. Used by the
## frame-rate equivalence checks to compare 30 / 60 / 144 FPS without needing a
## GPU or a rendered frame.
static func simulate_run(
	seconds: float,
	frames_per_second: float,
	ticks_per_second: float,
	creep_steps_per_tick: float,
	max_catch_up_steps: int
) -> Dictionary:
	var scheduler := OrganicVisibilityMaskScheduler.new()
	var delta := 1.0 / maxf(0.0001, frames_per_second)
	var frames := int(round(maxf(0.0, seconds) * maxf(0.0001, frames_per_second)))
	var busy_frames := 0
	# The per-tick creep substep counts in tick order, flattened across frames.
	# This is the sequence the GPU actually executes, so two frame rates that
	# produce the same prefix here produce byte-identical simulation state for
	# every tick in that prefix.
	var creep_sequence := PackedInt32Array()
	for _frame in frames:
		var steps := scheduler.advance(delta, ticks_per_second, creep_steps_per_tick, max_catch_up_steps)
		if steps.is_empty():
			continue
		busy_frames += 1
		creep_sequence.append_array(steps)
	return {
		"frames": frames,
		"busy_frames": busy_frames,
		"ticks": scheduler.get_executed_ticks(),
		"creep_steps": scheduler.get_total_creep_steps(),
		"dropped_ticks": scheduler.get_dropped_ticks(),
		"creep_sequence": creep_sequence,
	}
