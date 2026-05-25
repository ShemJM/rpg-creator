extends Node
## Headless entry point for agent / CI use.
##
## Launch with the standard Godot GUI binary (--headless disables the window):
##
##   Godot_v4.6.2-stable_win64.exe --headless --path . ^
##     --script scripts/runtime/headless_runner.gd ^
##     -- --project games/my.rpgm --scenario games/test.json --output results.json
##
## Or with the console binary (Godot_v4.x_console.exe) for live stdout:
##
##   Godot_v4.6.2-stable_win64_console.exe --headless --path . ^
##     --script scripts/runtime/headless_runner.gd ^
##     -- --project games/my.rpgm --scenario games/test.json
##
## --output <path>  Write JSON results to this file (works with GUI binary).
##                  If omitted, results are only printed to stdout (console binary).
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
  --project  <path>      Load a project (use with --list-maps or --scenario).
  --list-maps            Print a JSON array of all maps and exit.
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
	var map_id_str: String    = _get_arg(args, "--map-id")
	var output_path: String   = _get_arg(args, "--output")
	var list_maps: bool       = "--list-maps" in args

	# Load project if given.
	if not project_path.is_empty():
		if not ProjectState.load_from(project_path):
			push_error("[Headless] Could not load project: %s" % project_path)
			get_tree().quit(2)
			return
	elif ProjectState.maps.is_empty():
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

	if not scenario_path.is_empty():
		await _run_scenario(scenario_path, output_path)
		return

	push_error("[Headless] No action specified. Use --scenario or --list-maps.")
	get_tree().quit(2)


func _run_scenario(path: String, output_path: String = "") -> void:
	# Build a minimal runtime scene (no window needed when --headless).
	var runtime_scene := load(_RuntimePlayerScene) as PackedScene
	if runtime_scene == null:
		push_error("[Headless] RuntimePlayer.tscn not found.")
		get_tree().quit(2)
		return

	var runtime: RuntimePlayer = runtime_scene.instantiate()
	add_child(runtime)

	var runner := _ScenarioRunner.new()
	runner.headless = true
	add_child(runner)
	runner.setup(runtime, true)

	runner.scenario_completed.connect(func(results: Dictionary) -> void:
		var json_out: String = JSON.stringify(results, "\t")
		if not output_path.is_empty():
			_write_file(output_path, json_out)
			print("[Headless] Results written to: %s" % output_path)
		var exit_code: int = 0 if results["failed"] == 0 else 1
		get_tree().quit(exit_code)
	)

	runner.run_from_file(path)


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
