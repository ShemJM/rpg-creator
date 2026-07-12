# RPG Creator

A **Godot 4 in-engine RPG authoring tool** — build tile maps, place events, script dialogue and logic, and play-test without leaving Godot.

Inspired by RPG Maker MV/MZ. The editor and runtime both live inside a single Godot project.

Games can be built two ways: interactively in the editor UI, or **by agents** (Claude Code) that author the project JSON directly and verify it with the headless scenario test harness — see [CLAUDE.md](CLAUDE.md) for the full agent workflow, schema reference, and CLI.

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
| `scripts/editor/editor_shell.gd` | `EditorShell` | Top-level editor layout — Maps/Database nav, play-test toggle |
| `scripts/editor/map_editor.gd` | `MapEditor` | Map list, tile palette, layer/tool selector, canvas |
| `scripts/editor/map_canvas.gd` | `MapCanvas` | SubViewport tile renderer + mouse input for paint/place |
| `scripts/editor/event_editor_panel.gd` | `EventEditorPanel` | Page list, trigger/condition settings, command list |
| `scripts/editor/database_panel.gd` | `DatabasePanel` | Database editor — actors, classes, items, weapons, armor |
| `scripts/editor/graphic_picker.gd` | `GraphicPicker` | Shared charset-authoring popup (event pages + actors) |

### Runtime

| Script | Class | Role |
|--------|-------|------|
| `scripts/runtime/runtime_player.gd` | `RuntimePlayer` | Builds the playable map from `ProjectState`, spawns the player |
| `scripts/runtime/player_character.gd` | `PlayerCharacter` | 2D `CharacterBody2D` — grid movement, event interaction |
| `scripts/runtime/event_runner.gd` | `EventRunner` | Interprets event command lists; pauses for dialogue and choices |
| `scripts/runtime/dialogue_box.gd` | `DialogueBox` | In-runtime dialogue/choice UI |
| `scripts/runtime/character_sprite.gd` | `CharacterSprite` | Reusable directional/animated character sprite (charset or colour fallback) for the player and events |

### Resources

| Script | Class | Role |
|--------|-------|------|
| `scripts/resources/map_data.gd` | `MapData` | Map dimensions, ground/surface layers, event list |
| `scripts/resources/event_data.gd` | `EventData` | One event — position, name, list of pages |
| `scripts/resources/event_page.gd` | `EventPage` | Trigger, conditions (switch/variable/self-switch), command list, optional character graphic |
| `scripts/resources/event_command.gd` | `EventCommand` | Single command — type enum + params dictionary |
| `scripts/resources/tile_def.gd` | `TileDef` | Tile identity, name, passability, colour stub |
| `scripts/resources/character_graphic.gd` | `CharacterGraphic` | Spritesheet (charset) — source path, frame slicing, direction rows, walk frames |
| `scripts/resources/stat_block.gd` | `StatBlock` | The 8 core stats (hp/mp/atk/def/mat/mdf/agi/luk); shared by actors/classes/equipment |
| `scripts/resources/actor_data.gd` | `ActorData` | Playable character — name, class, level, stats, charset |
| `scripts/resources/class_data.gd` | `ClassData` | Character class — name, base stats |
| `scripts/resources/item_data.gd` | `ItemData` | Item — name, description, price, consumable, effect |
| `scripts/resources/equip_data.gd` | `EquipData` | Weapon or armor (by `kind`) — slot, price, stat bonuses |

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

### Headless / agents / CI

```
make setup            # download or locate a Godot 4.6 binary (bin/godot)
make test             # validate + run every scenario in games/ + fixtures
make validate P=games/my_game.rpgc
make run-scenario S=games/my_game_scenario.json
```

Game projects are plain JSON (`games/*.rpgc`); scenarios (`games/*_scenario.json`) script a playthrough with assertions. CI (`.github/workflows/test.yml`) runs the whole suite on every push. `CLAUDE.md` documents the schema and workflow; `docs/agent-mcp-plan.md` records the interface design.

---

## Current State

See [CURRENT_STATE.md](CURRENT_STATE.md).

## Roadmap

See [ROADMAP.md](ROADMAP.md).
