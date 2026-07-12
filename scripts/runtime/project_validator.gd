class_name ProjectValidator
extends RefCounted
## Validates the raw parsed JSON of a project (.rpgc/.rpgm) or scenario file.
##
## Works on the raw Dictionary — NOT the deserialized resources — because
## deserialization is deliberately lenient (every field has a .get() default),
## which would mask exactly the typos this exists to catch.
##
## validate_project() / validate_scenario() return an Array of
## { "path": "maps[0].events[1].pages[0].commands[2]", "message": "..." }.

const MAX_SWITCHES := 100
const MAX_VARIABLES := 100
const SELF_SWITCH_LETTERS := ["A", "B", "C", "D"]
const VARIABLE_OPS := ["set", "add", "sub", "mul", "div"]
const CONDITION_TYPES := ["switch", "variable_gte", "self_switch"]
const MOVE_ROUTE_TARGETS := ["player", "this"]
const MOVE_ROUTE_STEPS := [
	"up", "down", "left", "right", "wait",
	"face_up", "face_down", "face_left", "face_right", "turn_toward_player",
]
const SCENARIO_ACTIONS := [
	"move", "interact", "advance_dialogue", "choose", "wait_frames",
	"expect_switch", "expect_variable", "expect_position",
	"expect_player_facing", "expect_event_facing", "expect_dialogue",
	"expect_event_erased", "expect_event_running", "expect_game_over",
	"snapshot",
]
const DIRECTIONS := ["up", "down", "left", "right"]
const SUPPORTED_VERSIONS := [1, 2, 3, 4]


static func validate_project(data: Dictionary) -> Array:
	var errors: Array = []

	var version: Variant = data.get("version", null)
	if not _is_int(version) or not SUPPORTED_VERSIONS.has(_as_int(version)):
		_err(errors, "version", "unsupported or missing version (expected one of %s): %s" % [str(SUPPORTED_VERSIONS), str(version)])

	if not data.get("maps", null) is Array:
		_err(errors, "maps", "required key \"maps\" missing or not an array")
		return errors
	var maps: Array = data["maps"]
	if maps.is_empty():
		_err(errors, "maps", "project has no maps")

	# Tile ids valid for layer checks: explicit tileset, or the 5-tile default.
	var tile_ids: Dictionary = {}
	var tileset: Variant = data.get("tileset", [])
	if tileset is Array and not (tileset as Array).is_empty():
		for i in range((tileset as Array).size()):
			var t: Variant = tileset[i]
			if not t is Dictionary or not _is_int((t as Dictionary).get("id", null)):
				_err(errors, "tileset[%d]" % i, "tile def must be an object with an integer \"id\"")
				continue
			tile_ids[_as_int(t["id"])] = true
	else:
		for id in range(5):  # TileDef.get_stub_tileset()
			tile_ids[id] = true

	# Collect map ids first so TRANSFER_PLAYER targets can be cross-checked.
	var map_bounds: Dictionary = {}  # map_id -> Vector2i(width, height)
	var seen_map_ids: Dictionary = {}
	for i in range(maps.size()):
		if not maps[i] is Dictionary:
			_err(errors, "maps[%d]" % i, "map must be an object")
			continue
		var m: Dictionary = maps[i]
		var mid: Variant = m.get("id", null)
		if not _is_int(mid):
			_err(errors, "maps[%d].id" % i, "missing or non-integer map id")
			continue
		if seen_map_ids.has(_as_int(mid)):
			_err(errors, "maps[%d].id" % i, "duplicate map id %d" % _as_int(mid))
		seen_map_ids[_as_int(mid)] = true
		map_bounds[_as_int(mid)] = Vector2i(_as_int(m.get("width", 0)), _as_int(m.get("height", 0)))

	for i in range(maps.size()):
		if maps[i] is Dictionary:
			_validate_map(errors, maps[i], "maps[%d]" % i, tile_ids, map_bounds)

	var db: Variant = data.get("database", {})
	if db is Dictionary:
		_validate_database(errors, db)
	elif db != null:
		_err(errors, "database", "must be an object")

	return errors


static func _validate_map(errors: Array, m: Dictionary, path: String, tile_ids: Dictionary, map_bounds: Dictionary) -> void:
	var w: int = _as_int(m.get("width", 0))
	var h: int = _as_int(m.get("height", 0))
	if w < 1 or h < 1:
		_err(errors, path, "width/height must be >= 1 (got %dx%d)" % [w, h])

	for layer_name in ["ground_layer", "surface_layer"]:
		var layer: Variant = m.get(layer_name, {})
		if not layer is Dictionary:
			_err(errors, "%s.%s" % [path, layer_name], "must be an object of \"x,y\" -> tile id")
			continue
		for key in (layer as Dictionary):
			var lpath := "%s.%s[\"%s\"]" % [path, layer_name, key]
			var parts: PackedStringArray = str(key).split(",")
			if parts.size() != 2 or not parts[0].strip_edges().is_valid_int() or not parts[1].strip_edges().is_valid_int():
				_err(errors, lpath, "layer key must be \"x,y\" with integer coordinates")
				continue
			var x := int(parts[0])
			var y := int(parts[1])
			if x < 0 or y < 0 or x >= w or y >= h:
				_err(errors, lpath, "cell (%d,%d) outside map bounds %dx%d" % [x, y, w, h])
			var tid: Variant = layer[key]
			if not _is_int(tid) or not tile_ids.has(_as_int(tid)):
				_err(errors, lpath, "unknown tile id: %s" % str(tid))

	var events: Variant = m.get("events", [])
	if not events is Array:
		_err(errors, "%s.events" % path, "must be an array")
		return
	var seen_event_ids: Dictionary = {}
	for i in range((events as Array).size()):
		var epath := "%s.events[%d]" % [path, i]
		if not events[i] is Dictionary:
			_err(errors, epath, "event must be an object")
			continue
		var ev: Dictionary = events[i]
		var eid: Variant = ev.get("id", null)
		if not _is_int(eid):
			_err(errors, "%s.id" % epath, "missing or non-integer event id")
		elif seen_event_ids.has(_as_int(eid)):
			_err(errors, "%s.id" % epath, "duplicate event id %d in map" % _as_int(eid))
		else:
			seen_event_ids[_as_int(eid)] = true
		var ex: int = _as_int(ev.get("x", -1))
		var ey: int = _as_int(ev.get("y", -1))
		if ex < 0 or ey < 0 or ex >= w or ey >= h:
			_err(errors, epath, "event at (%d,%d) outside map bounds %dx%d" % [ex, ey, w, h])
		var pages: Variant = ev.get("pages", [])
		if not pages is Array:
			_err(errors, "%s.pages" % epath, "must be an array")
			continue
		for p in range((pages as Array).size()):
			if pages[p] is Dictionary:
				_validate_page(errors, pages[p], "%s.pages[%d]" % [epath, p], map_bounds)
			else:
				_err(errors, "%s.pages[%d]" % [epath, p], "page must be an object")


static func _validate_page(errors: Array, page: Dictionary, path: String, map_bounds: Dictionary) -> void:
	var trigger: Variant = page.get("trigger", 0)
	if _canonical_enum(trigger, EventPage.Trigger) < 0:
		_err(errors, "%s.trigger" % path, "unknown trigger (0-3 or one of %s): %s" % [str(EventPage.Trigger.keys()), str(trigger)])

	var ssw: String = str(page.get("condition_self_switch", ""))
	if ssw != "" and not SELF_SWITCH_LETTERS.has(ssw):
		_err(errors, "%s.condition_self_switch" % path, "must be \"\" or A-D, got \"%s\"" % ssw)
	var csw: int = _as_int(page.get("condition_switch_id", -1))
	if csw < -1 or csw >= MAX_SWITCHES:
		_err(errors, "%s.condition_switch_id" % path, "switch id out of range (-1..%d): %d" % [MAX_SWITCHES - 1, csw])
	var cvar: int = _as_int(page.get("condition_variable_id", -1))
	if cvar < -1 or cvar >= MAX_VARIABLES:
		_err(errors, "%s.condition_variable_id" % path, "variable id out of range (-1..%d): %d" % [MAX_VARIABLES - 1, cvar])

	var gc: Variant = page.get("graphic_color", [0.8, 0.2, 0.2, 1.0])
	if not (gc is Array and (gc as Array).size() == 4):
		_err(errors, "%s.graphic_color" % path, "must be a 4-element [r,g,b,a] array of floats 0-1")

	var commands: Variant = page.get("commands", [])
	if not commands is Array:
		_err(errors, "%s.commands" % path, "must be an array")
		return
	# Jumps from nested branches resolve against page-level labels.
	var labels: Dictionary = {}
	_collect_labels(commands, labels)
	_validate_commands(errors, commands, "%s.commands" % path, map_bounds, labels)


static func _collect_labels(commands: Array, labels: Dictionary) -> void:
	for c in commands:
		if not c is Dictionary:
			continue
		var params: Variant = (c as Dictionary).get("params", {})
		if not params is Dictionary:
			continue
		if _canonical_enum((c as Dictionary).get("type", null), EventCommand.Type) == EventCommand.Type.LABEL:
			labels[str((params as Dictionary).get("name", ""))] = true
		for branch in ["commands_if", "commands_else"]:
			if (params as Dictionary).get(branch, null) is Array:
				_collect_labels(params[branch], labels)


static func _validate_commands(errors: Array, commands: Array, path: String, map_bounds: Dictionary, labels: Dictionary) -> void:
	for i in range(commands.size()):
		var cpath := "%s[%d]" % [path, i]
		if not commands[i] is Dictionary:
			_err(errors, cpath, "command must be an object")
			continue
		var cmd: Dictionary = commands[i]
		var ctype: int = _canonical_enum(cmd.get("type", null), EventCommand.Type)
		if ctype < 0:
			_err(errors, "%s.type" % cpath, "unknown command type (integer 0-%d or one of %s): %s" % [EventCommand.Type.size() - 1, str(EventCommand.Type.keys()), str(cmd.get("type"))])
			continue
		var params: Variant = cmd.get("params", {})
		if not params is Dictionary:
			_err(errors, "%s.params" % cpath, "params must be an object")
			continue
		_validate_params(errors, ctype, params, cpath, map_bounds, labels)


static func _validate_params(errors: Array, ctype: int, params: Dictionary, cpath: String, map_bounds: Dictionary, labels: Dictionary) -> void:
	match ctype:
		EventCommand.Type.SHOW_TEXT:
			if not (params.get("lines", null) is Array) or (params["lines"] as Array).is_empty():
				_err(errors, "%s.params.lines" % cpath, "SHOW_TEXT needs a non-empty \"lines\" array")

		EventCommand.Type.SHOW_CHOICES:
			var choices: Variant = params.get("choices", null)
			if not choices is Array or (choices as Array).is_empty():
				_err(errors, "%s.params.choices" % cpath, "SHOW_CHOICES needs a non-empty \"choices\" array")
			elif _is_int(params.get("cancel_index", -1)) and _as_int(params.get("cancel_index", -1)) >= (choices as Array).size():
				_err(errors, "%s.params.cancel_index" % cpath, "cancel_index beyond last choice")

		EventCommand.Type.CONTROL_SWITCHES:
			_check_id_array(errors, params, "%s.params" % cpath, MAX_SWITCHES, "switch")

		EventCommand.Type.CONTROL_VARIABLES:
			_check_id_array(errors, params, "%s.params" % cpath, MAX_VARIABLES, "variable")
			var op: String = str(params.get("op", "set"))
			if not VARIABLE_OPS.has(op):
				_err(errors, "%s.params.op" % cpath, "op must be one of %s, got \"%s\"" % [str(VARIABLE_OPS), op])
			if not _is_number(params.get("value", 0)):
				_err(errors, "%s.params.value" % cpath, "value must be a number")

		EventCommand.Type.CONDITIONAL_BRANCH:
			var cond: String = str(params.get("condition_type", "switch"))
			if not CONDITION_TYPES.has(cond):
				_err(errors, "%s.params.condition_type" % cpath, "must be one of %s, got \"%s\"" % [str(CONDITION_TYPES), cond])
			elif cond == "self_switch" and not SELF_SWITCH_LETTERS.has(str(params.get("value", ""))):
				_err(errors, "%s.params.value" % cpath, "self_switch condition needs value A-D")
			elif cond != "self_switch":
				var id: int = _as_int(params.get("id", 0))
				var limit: int = MAX_SWITCHES if cond == "switch" else MAX_VARIABLES
				if id < 0 or id >= limit:
					_err(errors, "%s.params.id" % cpath, "%s id out of range (0..%d): %d" % [cond, limit - 1, id])
			for branch in ["commands_if", "commands_else"]:
				var sub: Variant = params.get(branch, [])
				if sub is Array:
					_validate_commands(errors, sub, "%s.params.%s" % [cpath, branch], map_bounds, labels)
				else:
					_err(errors, "%s.params.%s" % [cpath, branch], "must be an array of commands")

		EventCommand.Type.TRANSFER_PLAYER:
			var mid: Variant = params.get("map_id", null)
			if not _is_int(mid) or not map_bounds.has(_as_int(mid)):
				_err(errors, "%s.params.map_id" % cpath, "TRANSFER_PLAYER target map does not exist: %s" % str(mid))
			else:
				var b: Vector2i = map_bounds[_as_int(mid)]
				var tx: int = _as_int(params.get("x", -1))
				var ty: int = _as_int(params.get("y", -1))
				if tx < 0 or ty < 0 or tx >= b.x or ty >= b.y:
					_err(errors, cpath, "TRANSFER_PLAYER target (%d,%d) outside map %d bounds %dx%d" % [tx, ty, _as_int(mid), b.x, b.y])

		EventCommand.Type.SET_SELF_SWITCH:
			if not SELF_SWITCH_LETTERS.has(str(params.get("letter", ""))):
				_err(errors, "%s.params.letter" % cpath, "letter must be A-D")

		EventCommand.Type.WAIT:
			if not _is_number(params.get("frames", null)) or _as_int(params.get("frames", 0)) < 0:
				_err(errors, "%s.params.frames" % cpath, "WAIT needs a non-negative \"frames\" number")

		EventCommand.Type.FADE_OUT, EventCommand.Type.FADE_IN:
			if not _is_number(params.get("duration", 0.5)) or float(params.get("duration", 0.5)) < 0.0:
				_err(errors, "%s.params.duration" % cpath, "duration must be a non-negative number of seconds")

		EventCommand.Type.LABEL:
			if str(params.get("name", "")).is_empty():
				_err(errors, "%s.params.name" % cpath, "LABEL needs a non-empty \"name\"")

		EventCommand.Type.JUMP_TO_LABEL:
			var target: String = str(params.get("name", ""))
			if target.is_empty():
				_err(errors, "%s.params.name" % cpath, "JUMP_TO_LABEL needs a non-empty \"name\"")
			elif not labels.has(target):
				_err(errors, "%s.params.name" % cpath, "no LABEL named \"%s\" on this page" % target)

		EventCommand.Type.MOVE_ROUTE:
			if not MOVE_ROUTE_TARGETS.has(str(params.get("target", ""))):
				_err(errors, "%s.params.target" % cpath, "target must be one of %s" % str(MOVE_ROUTE_TARGETS))
			var steps: Variant = params.get("steps", null)
			if not steps is Array:
				_err(errors, "%s.params.steps" % cpath, "MOVE_ROUTE needs a \"steps\" array")
			else:
				for s in range((steps as Array).size()):
					if not MOVE_ROUTE_STEPS.has(str(steps[s])):
						_err(errors, "%s.params.steps[%d]" % [cpath, s], "unknown step \"%s\" (allowed: %s)" % [str(steps[s]), str(MOVE_ROUTE_STEPS)])


static func _check_id_array(errors: Array, params: Dictionary, path: String, limit: int, kind: String) -> void:
	var ids: Variant = params.get("ids", null)
	if not ids is Array or (ids as Array).is_empty():
		_err(errors, "%s.ids" % path, "needs a non-empty \"ids\" array of %s ids" % kind)
		return
	for i in range((ids as Array).size()):
		if not _is_int(ids[i]) or _as_int(ids[i]) < 0 or _as_int(ids[i]) >= limit:
			_err(errors, "%s.ids[%d]" % [path, i], "%s id out of range (0..%d): %s" % [kind, limit - 1, str(ids[i])])


static func _validate_database(errors: Array, db: Dictionary) -> void:
	var class_ids: Dictionary = {}
	for c in db.get("classes", []):
		if c is Dictionary and _is_int((c as Dictionary).get("id", null)):
			class_ids[_as_int(c["id"])] = true
	var actors: Variant = db.get("actors", [])
	if actors is Array:
		for i in range((actors as Array).size()):
			var a: Variant = actors[i]
			if not a is Dictionary:
				continue
			var cid: int = _as_int((a as Dictionary).get("class_id", -1))
			if cid != -1 and not class_ids.has(cid):
				_err(errors, "database.actors[%d].class_id" % i, "references missing class id %d" % cid)
	var equipment: Variant = db.get("equipment", [])
	if equipment is Array:
		for i in range((equipment as Array).size()):
			var e: Variant = equipment[i]
			if e is Dictionary and not ["weapon", "armor"].has(str((e as Dictionary).get("kind", "weapon"))):
				_err(errors, "database.equipment[%d].kind" % i, "kind must be \"weapon\" or \"armor\"")


# ---------------------------------------------------------------------------
# Scenario validation
# ---------------------------------------------------------------------------

static func validate_scenario(data: Dictionary) -> Array:
	var errors: Array = []
	var project: String = str(data.get("project", ""))
	if not project.is_empty() and not FileAccess.file_exists(project):
		_err(errors, "project", "project file not found: %s" % project)

	var steps: Variant = data.get("steps", null)
	if not steps is Array:
		_err(errors, "steps", "required key \"steps\" missing or not an array")
		return errors

	var has_assertion := false
	for i in range((steps as Array).size()):
		var spath := "steps[%d]" % i
		if not steps[i] is Dictionary:
			_err(errors, spath, "step must be an object")
			continue
		var step: Dictionary = steps[i]
		var action: String = str(step.get("action", ""))
		if not SCENARIO_ACTIONS.has(action):
			_err(errors, "%s.action" % spath, "unknown action \"%s\" (allowed: %s)" % [action, str(SCENARIO_ACTIONS)])
			continue
		if action.begins_with("expect_"):
			has_assertion = true
		match action:
			"move":
				if not DIRECTIONS.has(str(step.get("direction", ""))):
					_err(errors, "%s.direction" % spath, "move needs direction up/down/left/right")
			"choose":
				if not _is_int(step.get("index", null)):
					_err(errors, "%s.index" % spath, "choose needs an integer \"index\"")
			"wait_frames":
				if not _is_int(step.get("count", null)) or _as_int(step.get("count", 0)) < 1:
					_err(errors, "%s.count" % spath, "wait_frames needs a positive integer \"count\"")
			"expect_switch", "expect_variable":
				if not _is_int(step.get("id", null)):
					_err(errors, "%s.id" % spath, "%s needs an integer \"id\"" % action)
	if not has_assertion:
		_err(errors, "steps", "scenario has no expect_* assertions — it can never fail")
	return errors


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _err(errors: Array, path: String, message: String) -> void:
	errors.append({ "path": path, "message": message })


## True for ints and float-typed whole numbers (all JSON numbers parse as float).
static func _is_int(v: Variant) -> bool:
	return v is int or (v is float and v == floorf(v))


static func _is_number(v: Variant) -> bool:
	return v is int or v is float


static func _as_int(v: Variant) -> int:
	if v is int or v is float:
		return int(v)
	return -2147483648


## Resolve an enum value given as an int ordinal or a string key.
## Returns the ordinal, or -1 if unknown.
static func _canonical_enum(v: Variant, enum_dict: Dictionary) -> int:
	if _is_int(v) and _as_int(v) >= 0 and _as_int(v) < enum_dict.size():
		return _as_int(v)
	if v is String and enum_dict.has(v):
		return enum_dict[v]
	return -1
