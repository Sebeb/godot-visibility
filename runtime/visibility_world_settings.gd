extends Resource
class_name VisibilityWorldSettings

## Host-owned world dimensions required by the visibility renderer.

@export_range(0.0001, 4096.0, 0.0001) var cell_size := 1.0
@export_range(0.0, 4096.0, 0.0001) var wall_thickness := 0.1
@export_range(0.0, 4096.0, 0.0001) var wall_height := 1.0


func normalized() -> VisibilityWorldSettings:
	var result := duplicate() as VisibilityWorldSettings
	result.cell_size = maxf(0.0001, cell_size)
	result.wall_thickness = maxf(0.0, wall_thickness)
	result.wall_height = maxf(0.0, wall_height)
	return result
