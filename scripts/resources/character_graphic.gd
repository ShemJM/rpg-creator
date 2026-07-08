class_name CharacterGraphic
extends Resource
## Defines a character spritesheet (charset) sliced into directional walk frames.
## RPG Maker-style default layout: rows = facing directions (down/left/right/up),
## columns = walk-cycle frames. Slicing is stored explicitly so any sheet works.

## Absolute path to the source image.
@export var source_path: String = ""
## Size of a single frame in pixels.
@export var frame_width: int = 32
@export var frame_height: int = 32
## Sheet dimensions in frames (informational; row lookups use the dir_*_row fields).
@export var columns: int = 3
@export var rows: int = 4
## How many walk-cycle frames each direction has (columns used for animation).
@export var frames_per_direction: int = 3
## Animation speed while moving.
@export var anim_fps: float = 6.0
## Row index within the sheet for each facing.
@export var dir_down_row: int = 0
@export var dir_left_row: int = 1
@export var dir_right_row: int = 2
@export var dir_up_row: int = 3


func is_valid() -> bool:
	return not source_path.is_empty() and frame_width > 0 and frame_height > 0


## Pick the sheet row for a facing direction. Vertical facing wins on diagonals.
func row_for_direction(dir: Vector2i) -> int:
	if dir.y > 0:
		return dir_down_row
	if dir.y < 0:
		return dir_up_row
	if dir.x < 0:
		return dir_left_row
	if dir.x > 0:
		return dir_right_row
	return dir_down_row


## Pixel region for a facing direction + walk frame.
func region_for(dir: Vector2i, frame: int) -> Rect2i:
	var frame_count: int = maxi(frames_per_direction, 1)
	var col: int = clampi(frame, 0, frame_count - 1)
	var row: int = row_for_direction(dir)
	return Rect2i(col * frame_width, row * frame_height, frame_width, frame_height)


func to_dict() -> Dictionary:
	return {
		"source_path": source_path,
		"frame_width": frame_width,
		"frame_height": frame_height,
		"columns": columns,
		"rows": rows,
		"frames_per_direction": frames_per_direction,
		"anim_fps": anim_fps,
		"dir_rows": [dir_down_row, dir_left_row, dir_right_row, dir_up_row],
	}


static func from_dict(d: Dictionary) -> CharacterGraphic:
	var g := CharacterGraphic.new()
	g.source_path = d.get("source_path", "")
	g.frame_width = int(d.get("frame_width", 32))
	g.frame_height = int(d.get("frame_height", 32))
	g.columns = int(d.get("columns", 3))
	g.rows = int(d.get("rows", 4))
	g.frames_per_direction = int(d.get("frames_per_direction", 3))
	g.anim_fps = float(d.get("anim_fps", 6.0))
	var dr: Array = d.get("dir_rows", [0, 1, 2, 3])
	if dr.size() == 4:
		g.dir_down_row = int(dr[0])
		g.dir_left_row = int(dr[1])
		g.dir_right_row = int(dr[2])
		g.dir_up_row = int(dr[3])
	return g
