extends Node
## Cross-system signal bus for the RPG Creator editor.

# --- Editor ---
signal map_selected(map_index: int)
signal tile_painted(layer: int, coords: Vector2i, tile_id: int)
signal tool_changed(tool_name: String)
signal layer_changed(layer: int)

# --- Play-test ---
signal playtest_requested()
signal playtest_stopped()

# --- Events (editor) ---
signal event_selected(event: EventData)
signal event_placed(event: EventData)
signal event_mode_toggled(active: bool)

# --- Project ---
signal project_loaded(path: String)
signal project_saved(path: String)

# --- Events (runtime) ---
signal dialogue_requested(text: String, speaker: String)
signal choices_requested(choices: Array, cancel_index: int)
signal choice_made(index: int)
signal dialogue_finished()
signal transfer_requested(map_id: int, x: int, y: int)

# --- Agent / scripted control ---
## Emit to advance a waiting dialogue without keyboard input.
signal scripted_dialogue_advance()
## Emit to make a choice without keyboard input.
signal scripted_choice_made(index: int)

# --- Runtime trace (structured output for agents / tests) ---
signal trace_event_started(event_name: String, event_id: int, map_id: int)
signal trace_event_finished(event_name: String, event_id: int)
signal trace_command_executed(event_id: int, command_type: String, params: Dictionary)
signal trace_switch_changed(id: int, value: bool)
signal trace_variable_changed(id: int, value: int)
signal trace_transfer(from_map_id: int, to_map_id: int, x: int, y: int)
signal trace_dialogue(speaker: String, text: String)
signal trace_choice_made(index: int, label: String)
signal trace_player_moved(grid_pos: Vector2i, map_id: int)
signal trace_assertion_failed(message: String)
