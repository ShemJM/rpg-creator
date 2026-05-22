# RPG Creator

A **Godot 4 in-engine RPG authoring tool** — build tile maps, place events, script dialogue and logic, and play-test without leaving Godot.

Inspired by RPG Maker MV/MZ. The editor and runtime both live inside a single Godot project.

**Engine**: Godot 4.6 (GDScript)  
**Renderer**: GL Compatibility

---

## What it does

The editor lets you:

- Paint tile maps on two layers (ground, surface) using a colour-coded tile palette
- Place events on any map cell
- Author event pages with trigger conditions and command lists
- Play-test the current map in a 2D runtime directly from the editor

---

## Architecture

### Autoloads

| Singleton | Script | Role |
|-----------|--------|------|
| `SignalBus` | `scripts/autoloads/signal_bus.gd` | Typed signals for cross-system communication |
| `ProjectState` | `scripts/autoloads/project_state.gd` | Owns all map and event data in memory |
| `GameState` | `scripts/autoloads/game_state.gd` | Runtime switches and variables (reset each play-test) |
| `DesignTokens` | `scripts/autoloads/design_tokens.gd` | Shared UI colours, spacing, radius constants |
| `ThemeBuilder` | `scripts/autoloads/theme_builder.gd` | Builds and applies Godot `Theme` resources at runtime |

### Editor

| Script | Class | Role |
|--------|-------|------|
| `scripts/editor/editor_shell.gd` | `EditorShell` | Top-level editor layout — tabs, play-test toggle |
| `scripts/editor/map_editor.gd` | `MapEditor` | Map list, tile palette, layer/tool selector, canvas |
| `scripts/editor/map_canvas.gd` | `MapCanvas` | SubViewport tile renderer + mouse input for paint/place |
| `scripts/editor/event_editor_panel.gd` | `EventEditorPanel` | Page list, trigger/condition settings, command list |

### Runtime

| Script | Class | Role |
|--------|-------|------|
| `scripts/runtime/runtime_player.gd` | `RuntimePlayer` | Builds the playable map from `ProjectState`, spawns the player |
| `scripts/runtime/player_character.gd` | `PlayerCharacter` | 2D `CharacterBody2D` — grid movement, event interaction |
| `scripts/runtime/event_runner.gd` | `EventRunner` | Interprets event command lists; pauses for dialogue and choices |
| `scripts/runtime/dialogue_box.gd` | `DialogueBox` | In-runtime dialogue/choice UI |

### Resources

| Script | Class | Role |
|--------|-------|------|
| `scripts/resources/map_data.gd` | `MapData` | Map dimensions, ground/surface layers, event list |
| `scripts/resources/event_data.gd` | `EventData` | One event — position, name, list of pages |
| `scripts/resources/event_page.gd` | `EventPage` | Trigger, conditions (switch/variable/self-switch), command list |
| `scripts/resources/event_command.gd` | `EventCommand` | Single command — type enum + params dictionary |
| `scripts/resources/tile_def.gd` | `TileDef` | Tile identity, name, passability, colour stub |

---

## Event Commands

| Command | What it does |
|---------|-------------|
| `SHOW_TEXT` | Display dialogue lines with optional speaker name |
| `SHOW_CHOICES` | Prompt the player to pick from a list of options |
| `CONTROL_SWITCHES` | Set one or more global switches on/off |
| `CONTROL_VARIABLES` | Set/add/subtract a value from one or more variables |
| `CONDITIONAL_BRANCH` | Branch on a switch, variable, or self-switch condition |
| `TRANSFER_PLAYER` | Move the player to another map at a given coordinate |
| `SET_SELF_SWITCH` | Toggle a self-switch (A/B/C/D) on the current event |
| `WAIT` | Pause execution for N frames |
| `PLAY_SE` | Play a sound effect (stub) |
| `FADE_OUT` / `FADE_IN` | Screen fade (stub) |

---

## Building & Running

Open `project.godot` in Godot 4.6. Press **F5** to launch the editor.

The **Play** button in the editor boots the 2D runtime using the currently selected map from `ProjectState`. Press it again (or press **Escape**) to return to the editor.

No external build step required.

---

## Current State

See [CURRENT_STATE.md](CURRENT_STATE.md).

## Roadmap

See [ROADMAP.md](ROADMAP.md).
