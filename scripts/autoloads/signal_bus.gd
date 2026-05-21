extends Node
## Cross-system signal bus for the RPG Maker editor.

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
signal choices_requested(choices: Array)
signal choice_made(index: int)
signal dialogue_finished()
signal transfer_requested(map_id: int, x: int, y: int)
