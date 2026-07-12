extends Node
## Headless entry point for agent / CI use.
##
## The project must run normally so autoload singletons (ProjectState etc.)
## exist — godot --script mode does not register them. StartScreen detects
## user args and hosts this runner instead of building its UI:
##
##   godot --headless --path . -- --project games/my.rpgm \
##     --scenario games/test.json --output results.json
##
## --output <path>  Write JSON results to this file.
##                  If omitted, results are only printed to stdout.
##
## Exit codes:
##   0  all assertions passed (or no assertions)
##   1  one or more assertions failed
##   2  fatal error (bad args, file not found, etc.)

# Explicit preloads so class_name registration order doesn't matter at --script startup.
const _ScenarioRunner := preload("res://scripts/runtime/scenario_runner.gd")
const _RuntimePlayerScene := "res://scenes/runtime/RuntimePlayer.tscn"

const _USAGE := """
rpg-creator headless runner

Usage:
  --scenario <path>      Run a scenario JSON file and report results.
  --test-all [dir]       Run every *_scenario.json in a directory (default
                         games/) in one engine boot. Exit 1 on any failure.
  --project  <path>      Load a project (use with --list-maps or --scenario).
  --validate <path>      Lint a project or scenario file (exit 1 on errors).
  --resave   <path>      Load a project and save it back (migrates schema).
  --list-maps            Print a JSON array of all maps and exit.
  --list-database        Print a JSON summary of the project database and exit.
  --map-id   <int>       Override the start map id for --scenario.
  --output   <path>      Write JSON results to this file (for GUI binary use).
  --help                 Print this message.
"""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or "--help" in args:
		print(_USAGE)
		get_tree().quit(0)
		return

	# Parse args.
	var scenario_path: String = _get_arg(args, "--scenario")
	var project_path: String  = _get_arg(args, "--project")
	var validate_path: String = _get_arg(args, "--validate")
	var map_id_str: String    = _get_arg(args, "--map-id")
	var output_path: String   = _get_arg(args, "--output")
	var list_maps: bool       = "--list-maps" in args
	var list_database: bool   = "--list-database" in args

	if not validate_path.is_empty():
		_validate(validate_path, output_path)
		return

	var resave_path: String = _get_arg(args, "--resave")
	if not resave_path.is_empty():
		if not ProjectState.load_from(resave_path):
			push_error("[Headless] Could not load project: %s" % resave_path)
			get_tree().quit(2)
			return
		ProjectState.save(resave_path)
		print("[Headless] Re-saved %s at schema version %d" % [resave_path, ProjectState.serialize()["version"]])
		get_tree().quit(0)
		return

	# Load project if given. A scenario may instead name its own project
	# (the "project" key), so only the list operations hard-require --project.
	if not project_path.is_empty():
		if not ProjectState.load_from(project_path):
			push_error("[Headless] Could not load project: %s" % project_path)
			get_tree().quit(2)
			return
	elif (list_maps or list_database) and ProjectState.maps.is_empty():
		push_error("[Headless] No project loaded. Use --project <path>.")
		get_tree().quit(2)
		return

	if not map_id_str.is_empty():
		var mid := int(map_id_str)
		for i in range(ProjectState.maps.size()):
			if ProjectState.maps[i].id == mid:
				ProjectState.select_map(i)
				break

	if list_maps:
		var maps_json: String = JSON.stringify(ProjectState.list_maps(), "\t")
		print(maps_json)
		if not output_path.is_empty():
			_write_file(output_path, maps_json)
		get_tree().quit(0)
		return

	if list_database:
		var db_json: String = JSON.stringify(ProjectState.database_summary(), "\t")
		print(db_json)
		if not output_path.is_empty():
			_write_file(output_path, db_json)
		get_tree().quit(0)
		return

	if "--test-all" in args:
		var dir_path: String = _get_arg(args, "--test-all")
		if dir_path.is_empty() or dir_path.begins_with("--"):
			dir_path = "games"
		await _test_all(dir_path, output_path)
		return

	if not scenario_path.is_empty():
		await _run_scenario(scenario_path, output_path)
		return

	push_error("[Headless] No action specified. Use --scenario, --test-all, --validate, --list-maps, or --list-database.")
	get_tree().quit(2)


## Lint a project or scenario file (detected by its "steps" key) without
## running it. Prints a JSON array of { path, message } errors.
func _validate(path: String, output_path: String = "") -> void:
	if not FileAccess.file_exists(path):
		push_error("[Headless] File not found: %s" % path)
		get_tree().quit(2)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("[Headless] Not valid JSON: %s" % path)
		get_tree().quit(2)
		return

	var errors: Array
	if (parsed as Dictionary).has("steps"):
		errors = ProjectValidator.validate_scenario(parsed)
	else:
		errors = ProjectValidator.validate_project(parsed)

	var json_out := JSON.stringify(errors, "\t")
	print(json_out)
	if not output_path.is_empty():
		_write_file(output_path, json_out)
	if errors.is_empty():
		print("[Headless] %s: OK" % path)
	else:
		print("[Headless] %s: %d error(s)" % [path, errors.size()])
	get_tree().quit(0 if errors.is_empty() else 1)


func _run_scenario(path: String, output_path: String = "") -> void:
	var results: Dictionary = await _run_scenario_once(path)
	if results.is_empty():
		get_tree().quit(2)
		return
	if not output_path.is_empty():
		_write_file(output_path, JSON.stringify(results, "\t"))
		print("[Headless] Results written to: %s" % output_path)
	get_tree().quit(0 if int(results["failed"]) == 0 else 1)


## Run every *_scenario.json in a directory sequentially inside this one
## engine boot (each gets a fresh RuntimePlayer; GameState resets in its
## _ready and each scenario loads its own embedded project).
func _test_all(dir_path: String, output_path: String = "") -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("[Headless] Cannot open directory: %s" % dir_path)
		get_tree().quit(2)
		return
	var files: Array = []
	for f in dir.get_files():
		if f.ends_with("_scenario.json"):
			files.append(dir_path.path_join(f))
	files.sort()
	if files.is_empty():
		push_error("[Headless] No *_scenario.json files in %s" % dir_path)
		get_tree().quit(2)
		return

	var summary: Array = []
	var total_failed: int = 0
	for f in files:
		print("\n=== [Headless] %s" % f)
		var results: Dictionary = await _run_scenario_once(f)
		if results.is_empty():
			total_failed += 1
			summary.append({ "file": f, "fatal": true })
			continue
		total_failed += int(results["failed"])
		summary.append({ "file": f, "passed": results["passed"], "failed": results["failed"] })

	var out := { "scenarios": summary, "total_failed": total_failed }
	print("[Headless:test-all] ", JSON.stringify(out, "\t"))
	if not output_path.is_empty():
		_write_file(output_path, JSON.stringify(out, "\t"))
	get_tree().quit(0 if total_failed == 0 else 1)


## Run one scenario and return its results ({} on fatal error). The
## scenario's embedded project (and start map) must be applied BEFORE the
## runtime scene exists — RuntimePlayer builds the map in _ready(), so a
## project loaded later would never be constructed.
func _run_scenario_once(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[Headless] Scenario file not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("[Headless] Scenario is not valid JSON: %s" % path)
		return {}
	var scenario: Dictionary = parsed

	var embedded_project: String = scenario.get("project", "")
	if not embedded_project.is_empty():
		if not ProjectState.load_from(embedded_project):
			push_error("[Headless] Could not load scenario project: %s" % embedded_project)
			return {}
		scenario.erase("project")  # Already loaded — don't reload mid-run.
	elif ProjectState.maps.is_empty():
		push_error("[Headless] No project loaded. Pass --project or add a \"project\" key to the scenario.")
		return {}

	var start_map_id: int = int(scenario.get("start_map_id", -1))
	if start_map_id >= 0:
		for i in range(ProjectState.maps.size()):
			if ProjectState.maps[i].id == start_map_id:
				ProjectState.select_map(i)
				break
		scenario.erase("start_map_id")

	# Build a minimal runtime scene (no window needed when --headless).
	var runtime_scene := load(_RuntimePlayerScene) as PackedScene
	if runtime_scene == null:
		push_error("[Headless] RuntimePlayer.tscn not found.")
		return {}

	var runtime: RuntimePlayer = runtime_scene.instantiate()
	add_child(runtime)

	var runner := _ScenarioRunner.new()
	runner.headless = true
	add_child(runner)
	runner.setup(runtime, true)

	# Collect via a holder rather than awaiting the signal directly: a
	# scenario with no awaiting steps completes synchronously inside
	# run_from_dict, before an await could subscribe.
	var holder: Dictionary = {}
	runner.scenario_completed.connect(
		func(results: Dictionary) -> void: holder["results"] = results,
		CONNECT_ONE_SHOT
	)
	runner.run_from_dict(scenario)
	while not holder.has("results"):
		await get_tree().process_frame

	runner.queue_free()
	runtime.queue_free()
	await get_tree().process_frame
	return holder["results"]


static func _write_file(path: String, content: String) -> void:
	# Support both absolute paths and paths relative to the project root.
	var abs_path: String = path
	if not path.begins_with("/") and not path.substr(1, 1) == ":":
		abs_path = ProjectSettings.globalize_path("res://") + path
	var file := FileAccess.open(abs_path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
	else:
		push_error("[Headless] Could not write output file: %s" % abs_path)


static func _get_arg(args: Array, flag: String) -> String:
	var idx := args.find(flag)
	if idx >= 0 and idx + 1 < args.size():
		return args[idx + 1]
	return ""
