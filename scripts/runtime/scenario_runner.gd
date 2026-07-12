class_name ScenarioRunner
extends Node
## Executes a scenario JSON file against the current RuntimePlayer.
##
## Scenario format (JSON):
## {
##   "project": "path/to/file.rpgc",  // optional — if omitted uses current ProjectState
##   "start_map_id": 0,               // optional
##   "steps": [
##     { "action": "move",              "direction": "right", "times": 3 },
##     { "action": "interact" },
##     { "action": "advance_dialogue" },
##     { "action": "choose",            "index": 1 },
##     { "action": "wait_frames",       "count": 60 },
##     { "action": "expect_switch",     "id": 1,  "value": true },
##     { "action": "expect_variable",   "id": 0,  "value": 2 },
##     { "action": "expect_position",   "map_id": 0, "x": 5, "y": 7 },
##     { "action": "expect_player_facing", "x": -1, "y": 0 },   // player facing vector
##     { "action": "expect_event_facing",  "id": 0, "x": 1, "y": 0 }, // event's facing vector
##     { "action": "expect_dialogue",      "contains": "Hello" },  // any dialogue so far
##     { "action": "expect_event_erased",  "id": 0, "value": true },
##     { "action": "expect_event_running", "value": false },
##     { "action": "expect_game_over" },
##     { "action": "snapshot" }         // emits trace_snapshot signal with current state
##   ]
## }
##
## Optional top-level "timeout_frames" (default 6000): the run fails with a
## "timeout" assertion if it doesn't finish within that many frames.
##
## Results are collected in `results` and also written to stdout if headless is true.

signal scenario_completed(results: Dictionary)

var headless: bool = false

var _runtime: RuntimePlayer = null
var _steps: Array = []
var _step_index: int = 0
var _waiting_frames: int = 0
var _assertions: Array = []    # { "pass": bool, "message": String }
var _trace: Array = []         # all trace_* signals collected during run
var _running: bool = false
var _finished: bool = false
var _game_over: bool = false
var _timeout_frames: int = 6000
var _elapsed_frames: int = 0


func setup(runtime: RuntimePlayer, is_headless: bool = false) -> void:
	_runtime = runtime
	headless = is_headless
	# Wire up trace signals.
	SignalBus.trace_event_started.connect(_on_trace.bind("event_started"))
	SignalBus.trace_event_finished.connect(_on_trace_event_finished)
	SignalBus.trace_command_executed.connect(_on_trace_command)
	SignalBus.trace_switch_changed.connect(_on_trace_switch)
	SignalBus.trace_variable_changed.connect(_on_trace_variable)
	SignalBus.trace_transfer.connect(_on_trace_transfer)
	SignalBus.trace_dialogue.connect(_on_trace_dialogue)
	SignalBus.trace_choice_made.connect(_on_trace_choice)
	SignalBus.trace_player_moved.connect(_on_trace_player_moved)
	SignalBus.trace_assertion_failed.connect(_on_trace_assertion_failed)
	SignalBus.trace_self_switch_changed.connect(_on_trace_self_switch)
	SignalBus.trace_game_over.connect(_on_trace_game_over)
	SignalBus.trace_gold_changed.connect(func(g: int, d: int) -> void:
		_trace.append({ "type": "gold_changed", "gold": g, "delta": d }))
	SignalBus.trace_item_changed.connect(func(kind: String, id: int, count: int) -> void:
		_trace.append({ "type": "item_changed", "kind": kind, "id": id, "count": count }))
	SignalBus.trace_hp_changed.connect(func(actor_id: int, hp: int, max_hp: int) -> void:
		_trace.append({ "type": "hp_changed", "actor_id": actor_id, "hp": hp, "max_hp": max_hp }))
	SignalBus.trace_mp_changed.connect(func(actor_id: int, mp: int, max_mp: int) -> void:
		_trace.append({ "type": "mp_changed", "actor_id": actor_id, "mp": mp, "max_mp": max_mp }))
	SignalBus.trace_equip_changed.connect(func(actor_id: int, slot: String, equip_id: int) -> void:
		_trace.append({ "type": "equip_changed", "actor_id": actor_id, "slot": slot, "equip_id": equip_id }))
	SignalBus.trace_item_used.connect(func(item_id: int, actor_id: int, ok: bool) -> void:
		_trace.append({ "type": "item_used", "item_id": item_id, "actor_id": actor_id, "ok": ok }))
	SignalBus.trace_shop_opened.connect(func(entries: Array) -> void:
		_trace.append({ "type": "shop_opened", "entries": entries.duplicate(true) }))
	SignalBus.trace_shop_transaction.connect(func(action: String, kind: String, id: int, count: int, gold_delta: int, ok: bool) -> void:
		_trace.append({ "type": "shop_transaction", "action": action, "kind": kind, "id": id, "count": count, "gold_delta": gold_delta, "ok": ok }))
	SignalBus.trace_shop_closed.connect(func() -> void:
		_trace.append({ "type": "shop_closed" }))


func run_from_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		_record_assertion(false, "scenario file not found: %s" % path)
		_finish()
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_record_assertion(false, "scenario file is not valid JSON: %s" % path)
		_finish()
		return
	run_from_dict(parsed)


func run_from_dict(data: Dictionary) -> void:
	# Optionally load a different project.
	var project_path: String = data.get("project", "")
	if not project_path.is_empty():
		if not ProjectState.load_from(project_path):
			# Recorded as a failed assertion so headless runs exit 1, not 0.
			_record_assertion(false, "could not load project: %s" % project_path)
			_finish()
			return
	elif ProjectState.maps.is_empty():
		_record_assertion(false, "no project loaded and scenario has no \"project\" key")
		_finish()
		return

	# Optionally switch start map.
	var start_map_id: int = data.get("start_map_id", -1)
	if start_map_id >= 0:
		for i in range(ProjectState.maps.size()):
			if ProjectState.maps[i].id == start_map_id:
				ProjectState.select_map(i)
				break

	# Deterministic runs: GameState.reset() seeds rng with a constant; an
	# explicit scenario seed overrides it here (before any steps execute).
	if data.has("rng_seed"):
		GameState.rng.seed = int(data["rng_seed"])

	_steps = data.get("steps", [])
	_step_index = 0
	_timeout_frames = int(data.get("timeout_frames", 6000))
	_elapsed_frames = 0
	_running = true
	_process_next_step()


## Watchdog: a scenario that never reaches its end (runaway waits, future
## blocking actions) fails with a "timeout" assertion instead of hanging.
func _process(_delta: float) -> void:
	if not _running or _finished:
		return
	_elapsed_frames += 1
	if _elapsed_frames > _timeout_frames:
		_record_assertion(false, "timeout: scenario did not finish within %d frames" % _timeout_frames)
		_finish()


func _process_next_step() -> void:
	if _finished:
		return
	if _step_index >= _steps.size():
		_finish()
		return

	var step: Dictionary = _steps[_step_index]
	_step_index += 1
	var action: String = step.get("action", "")

	match action:
		"move":
			var direction: String = step.get("direction", "down")
			var times: int = step.get("times", 1)
			for _i in range(times):
				_runtime.scripted_move(direction)
				# process_frame fires after _physics_process so touch-event
				# detection and trace collection are complete before the next step.
				await get_tree().process_frame
			_process_next_step()

		"interact":
			_runtime.scripted_interact()
			await get_tree().process_frame
			_process_next_step()

		"advance_dialogue":
			_runtime.scripted_advance_dialogue()
			await get_tree().process_frame
			_process_next_step()

		"choose":
			var index: int = step.get("index", 0)
			_runtime.scripted_make_choice(index)
			await get_tree().process_frame
			_process_next_step()

		"shop_buy":
			SignalBus.scripted_shop_buy.emit(int(step.get("index", 0)), int(step.get("count", 1)))
			await get_tree().process_frame
			_process_next_step()

		"shop_sell":
			SignalBus.scripted_shop_sell.emit(str(step.get("kind", "item")), int(step.get("id", 0)), int(step.get("count", 1)))
			await get_tree().process_frame
			_process_next_step()

		"shop_close":
			SignalBus.scripted_shop_close.emit()
			await get_tree().process_frame
			_process_next_step()

		"wait_frames":
			var count: int = step.get("count", 1)
			for _i in range(count):
				await get_tree().process_frame
			_process_next_step()

		"expect_switch":
			var id: int = step.get("id", 0)
			var expected: bool = step.get("value", true)
			var actual: bool = GameState.get_switch(id)
			_record_assertion(
				actual == expected,
				"expect_switch[%d] == %s : got %s" % [id, str(expected), str(actual)]
			)
			_process_next_step()

		"expect_variable":
			var id: int = step.get("id", 0)
			var expected: int = step.get("value", 0)
			var actual: int = GameState.get_variable(id)
			_record_assertion(
				actual == expected,
				"expect_variable[%d] == %d : got %d" % [id, expected, actual]
			)
			_process_next_step()

		"expect_position":
			var map_id: int = step.get("map_id", -1)
			var exp_x: int = step.get("x", 0)
			var exp_y: int = step.get("y", 0)
			var snap: Dictionary = _runtime.get_snapshot()
			var pos_ok: bool = snap["player_grid"]["x"] == exp_x and snap["player_grid"]["y"] == exp_y
			var map_ok: bool = map_id < 0 or snap["map_id"] == map_id
			_record_assertion(
				pos_ok and map_ok,
				"expect_position map=%d (%d,%d) : got map=%d (%d,%d)" % [
					map_id, exp_x, exp_y,
					snap["map_id"], snap["player_grid"]["x"], snap["player_grid"]["y"]
				]
			)
			_process_next_step()

		"expect_player_facing":
			var exp_fx: int = step.get("x", 0)
			var exp_fy: int = step.get("y", 0)
			var fsnap: Dictionary = _runtime.get_snapshot()
			var pf: Dictionary = fsnap.get("player_facing", {})
			_record_assertion(
				pf.get("x", 999) == exp_fx and pf.get("y", 999) == exp_fy,
				"expect_player_facing (%d,%d) : got (%s,%s)" % [exp_fx, exp_fy, str(pf.get("x")), str(pf.get("y"))]
			)
			_process_next_step()

		"expect_event_facing":
			var ev_id: int = step.get("id", 0)
			var efx: int = step.get("x", 0)
			var efy: int = step.get("y", 0)
			var esnap: Dictionary = _runtime.get_snapshot()
			var ef: Dictionary = esnap.get("event_facing", {}).get(str(ev_id), {})
			_record_assertion(
				ef.get("x", 999) == efx and ef.get("y", 999) == efy,
				"expect_event_facing[%d] (%d,%d) : got (%s,%s)" % [ev_id, efx, efy, str(ef.get("x")), str(ef.get("y"))]
			)
			_process_next_step()

		"expect_dialogue":
			var needle: String = str(step.get("contains", ""))
			var want_speaker: String = str(step.get("speaker", ""))
			var found := false
			for entry in _trace:
				if entry.get("type", "") != "dialogue":
					continue
				if not needle.is_empty() and not str(entry.get("text", "")).contains(needle):
					continue
				if not want_speaker.is_empty() and str(entry.get("speaker", "")) != want_speaker:
					continue
				found = true
				break
			_record_assertion(
				found,
				"expect_dialogue contains \"%s\"%s : %s" % [
					needle,
					"" if want_speaker.is_empty() else " from \"%s\"" % want_speaker,
					"found" if found else "no matching dialogue in trace"
				]
			)
			_process_next_step()

		"expect_event_erased":
			var er_id: int = step.get("id", 0)
			var er_expected: bool = step.get("value", true)
			var er_snap: Dictionary = _runtime.get_snapshot()
			var er_actual: bool = er_snap.get("events_erased", []).has(er_id)
			_record_assertion(
				er_actual == er_expected,
				"expect_event_erased[%d] == %s : got %s" % [er_id, str(er_expected), str(er_actual)]
			)
			_process_next_step()

		"expect_event_running":
			var run_expected: bool = step.get("value", true)
			var run_actual: bool = _runtime.get_snapshot().get("event_running", false)
			_record_assertion(
				run_actual == run_expected,
				"expect_event_running == %s : got %s" % [str(run_expected), str(run_actual)]
			)
			_process_next_step()

		"expect_game_over":
			var go_expected: bool = step.get("value", true)
			_record_assertion(
				_game_over == go_expected,
				"expect_game_over == %s : got %s" % [str(go_expected), str(_game_over)]
			)
			_process_next_step()

		"expect_gold":
			var gold_expected: int = int(step.get("value", 0))
			_record_assertion(
				GameState.gold == gold_expected,
				"expect_gold == %d : got %d" % [gold_expected, GameState.gold]
			)
			_process_next_step()

		"expect_item_count":
			var ic_kind: String = str(step.get("kind", "item"))
			var ic_id: int = int(step.get("id", 0))
			var ic_expected: int = int(step.get("value", 0))
			var ic_actual: int = GameState.get_stock(ic_kind, ic_id)
			_record_assertion(
				ic_actual == ic_expected,
				"expect_item_count %s[%d] == %d : got %d" % [ic_kind, ic_id, ic_expected, ic_actual]
			)
			_process_next_step()

		"expect_party_size":
			var ps_expected: int = int(step.get("value", 1))
			_record_assertion(
				GameState.party.size() == ps_expected,
				"expect_party_size == %d : got %d" % [ps_expected, GameState.party.size()]
			)
			_process_next_step()

		"expect_actor_hp":
			var ah_id: int = int(step.get("actor_id", 0))
			var ah_member: Dictionary = GameState.get_member(ah_id)
			var ah_actual: int = int(ah_member.get("hp", -1))
			if step.has("gte"):
				var ah_min: int = int(step["gte"])
				_record_assertion(
					not ah_member.is_empty() and ah_actual >= ah_min,
					"expect_actor_hp[%d] >= %d : got %d" % [ah_id, ah_min, ah_actual]
				)
			else:
				var ah_expected: int = int(step.get("value", 0))
				_record_assertion(
					not ah_member.is_empty() and ah_actual == ah_expected,
					"expect_actor_hp[%d] == %d : got %d" % [ah_id, ah_expected, ah_actual]
				)
			_process_next_step()

		"expect_shop_open":
			var so_expected: bool = step.get("value", true)
			var so_actual: bool = _runtime.get_snapshot().get("shop_open", false)
			_record_assertion(
				so_actual == so_expected,
				"expect_shop_open == %s : got %s" % [str(so_expected), str(so_actual)]
			)
			_process_next_step()

		"expect_actor_stat":
			var as_id: int = int(step.get("actor_id", 0))
			var as_stat: String = str(step.get("stat", "atk"))
			var as_expected: int = int(step.get("value", 0))
			var as_stats: Dictionary = GameState.get_member_stats(as_id)
			var as_actual: int = int(as_stats.get(as_stat, -1))
			_record_assertion(
				not as_stats.is_empty() and as_actual == as_expected,
				"expect_actor_stat[%d].%s == %d : got %d" % [as_id, as_stat, as_expected, as_actual]
			)
			_process_next_step()

		"snapshot":
			var snap: Dictionary = _runtime.get_snapshot()
			_trace.append({ "type": "snapshot", "data": snap })
			if headless:
				print("[Scenario:snapshot] ", JSON.stringify(snap))
			_process_next_step()

		_:
			push_warning("[Scenario] Unknown action: %s" % action)
			_process_next_step()


func _record_assertion(passed: bool, message: String) -> void:
	_assertions.append({ "pass": passed, "message": message })
	var prefix: String = "PASS" if passed else "FAIL"
	if headless or not passed:
		print("[Scenario:%s] %s" % [prefix, message])
	if not passed:
		SignalBus.trace_assertion_failed.emit(message)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_running = false
	var passed: int = 0
	var failed: int = 0
	for a in _assertions:
		if a["pass"]:
			passed += 1
		else:
			failed += 1

	var results: Dictionary = {
		"passed": passed,
		"failed": failed,
		"total": passed + failed,
		"assertions": _assertions,
		"trace": _trace,
		"snapshot": _runtime.get_snapshot() if _runtime else {},
	}

	if headless:
		print("[Scenario:results] ", JSON.stringify(results, "\t"))

	scenario_completed.emit(results)


# ---------------------------------------------------------------------------
# Trace collectors
# ---------------------------------------------------------------------------

func _on_trace(label: String, arg1: Variant, arg2: Variant = null, arg3: Variant = null) -> void:
	_trace.append({ "type": label, "args": [arg1, arg2, arg3] })


func _on_trace_event_finished(event_name: String, event_id: int) -> void:
	_trace.append({ "type": "event_finished", "name": event_name, "id": event_id })


func _on_trace_command(event_id: int, command_type: String, params: Dictionary) -> void:
	_trace.append({ "type": "command", "event_id": event_id, "command": command_type, "params": params })


func _on_trace_switch(id: int, value: bool) -> void:
	_trace.append({ "type": "switch_changed", "id": id, "value": value })


func _on_trace_variable(id: int, value: int) -> void:
	_trace.append({ "type": "variable_changed", "id": id, "value": value })


func _on_trace_transfer(from_map_id: int, to_map_id: int, x: int, y: int) -> void:
	_trace.append({ "type": "transfer", "from": from_map_id, "to": to_map_id, "x": x, "y": y })


func _on_trace_dialogue(speaker: String, text: String) -> void:
	_trace.append({ "type": "dialogue", "speaker": speaker, "text": text })


func _on_trace_choice(index: int, label: String) -> void:
	_trace.append({ "type": "choice_made", "index": index, "label": label })


func _on_trace_player_moved(grid_pos: Vector2i, map_id: int) -> void:
	_trace.append({ "type": "player_moved", "x": grid_pos.x, "y": grid_pos.y, "map_id": map_id })


func _on_trace_assertion_failed(message: String) -> void:
	_trace.append({ "type": "assertion_failed", "message": message })


func _on_trace_self_switch(event_id: int, letter: String, value: bool) -> void:
	_trace.append({ "type": "self_switch_changed", "event_id": event_id, "letter": letter, "value": value })


func _on_trace_game_over() -> void:
	_game_over = true
	_trace.append({ "type": "game_over" })
