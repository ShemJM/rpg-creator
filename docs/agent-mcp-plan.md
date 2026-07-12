# Agent & MCP Integration Plan

## Overview

This document describes the planned interface surface for agent-driven game creation and testing in rpg-creator. The goal is to let Copilot (and any other tool-calling agent) create complete games, run deterministic playthroughs, and validate correctness — without touching the editor UI.

---

## Architecture Layers

```
┌──────────────────────────────────────────────────────┐
│  Clients                                             │
│   • Godot editor UI (existing)                       │
│   • MCP server (planned)                             │
│   • Headless scenario runner (implemented)           │
│   • CI pipeline / GitHub Actions (future)            │
└──────────────────┬───────────────────────────────────┘
                   │ calls
┌──────────────────▼───────────────────────────────────┐
│  Service APIs                                        │
│   • ProjectState — authoring service                 │
│   • RuntimePlayer — scripted control surface         │
│   • ScenarioRunner — scenario execution + assertions │
└──────────────────┬───────────────────────────────────┘
                   │ owns
┌──────────────────▼───────────────────────────────────┐
│  Engine                                              │
│   • MapData / EventData / EventPage / EventCommand   │
│   • EventRunner — command interpreter                │
│   • PlayerCharacter — physics + movement             │
│   • GameState — switches / variables                 │
│   • SignalBus — trace signals                        │
└──────────────────────────────────────────────────────┘
```

---

## What Is Already Implemented

| Capability | Location | Status |
|---|---|---|
| Project save / load JSON | `scripts/autoloads/project_state.gd` | ✅ |
| Authoring service API (maps/events) | `ProjectState.add_map_sized`, `paint_tile`, `fill_rect`, `place_event`, `append_command`, `list_maps` | ✅ |
| Authoring service API (database) | `ProjectState.add_actor/add_class/add_item/add_equip`, `get_*_by_id`, `database_summary` | ✅ |
| Scripted player movement | `PlayerCharacter.scripted_move()` | ✅ |
| Scripted interact | `RuntimePlayer.scripted_interact()` | ✅ |
| Scripted dialogue advance | `RuntimePlayer.scripted_advance_dialogue()` | ✅ |
| Scripted choice | `RuntimePlayer.scripted_make_choice(index)` | ✅ |
| Runtime snapshot | `RuntimePlayer.get_snapshot()` → Dictionary | ✅ |
| Structured trace signals | `SignalBus.trace_*` family | ✅ |
| Scenario runner | `scripts/runtime/scenario_runner.gd` | ✅ |
| Headless entrypoint | `scripts/runtime/headless_runner.gd` | ✅ |

---

## Headless Usage

Prefer the Makefile wrappers (`make test`, `make run-scenario S=...`, `make list-maps P=...`). Raw invocations (user args after `--` divert StartScreen into the headless runner — `--script` mode can't be used because autoloads only exist in a normal project run):

```
# List maps in a project
godot --headless --path . -- --project games/test.rpgm --list-maps

# List the project database (actors/classes/items/weapons/armor)
godot --headless --path . -- --project games/database_test.rpgc --list-database

# Run a scenario file
godot --headless --path . -- --scenario games/test_scenario.json
```

Exit codes: `0` = all assertions passed, `1` = assertion failures, `2` = fatal error.

---

## Scenario Format

```json
{
  "project": "games/test.rpgm",
  "start_map_id": 0,
  "steps": [
    { "action": "move",            "direction": "right", "times": 3 },
    { "action": "move",            "direction": "down",  "times": 2 },
    { "action": "interact" },
    { "action": "advance_dialogue" },
    { "action": "choose",          "index": 1 },
    { "action": "wait_frames",     "count": 60 },
    { "action": "expect_switch",   "id": 1,  "value": true },
    { "action": "expect_variable", "id": 0,  "value": 2 },
    { "action": "expect_position", "map_id": 1, "x": 5, "y": 7 },
    { "action": "snapshot" }
  ]
}
```

### Supported Actions

| Action | Required fields | Notes |
|---|---|---|
| `move` | `direction` (left/right/up/down), `times` (default 1) | Calls `scripted_move` per step |
| `interact` | — | Same as pressing ui_accept |
| `advance_dialogue` | — | Dismisses waiting dialogue box |
| `choose` | `index` (0-based) | Picks a choice option |
| `wait_frames` | `count` | Waits N physics frames |
| `expect_switch` | `id`, `value` | Assertion |
| `expect_variable` | `id`, `value` | Assertion |
| `expect_position` | `x`, `y`, `map_id` (optional) | Assertion on player grid position |
| `expect_player_facing` | `x`, `y` | Assertion on the player's facing vector |
| `expect_event_facing` | `id`, `x`, `y` | Assertion on an event sprite's facing vector |
| `snapshot` | — | Emits current state to trace output |

---

## MCP Tool Surface (Deferred)

> **Decision (2026-07): CLI-first.** Claude Code (the primary agent client)
> authors games by editing project JSON directly and tests them via the
> headless runner + Makefile — see `CLAUDE.md`. That covers the MCP tool
> surface below without a sidecar process. MCP remains a possible later
> addition for other agent clients; its one unique capability (a persistent
> interactive runtime session) is planned instead as a JSONL
> `--interactive` mode on the headless runner, which an MCP server could
> wrap thinly if ever needed.

The MCP server should be a thin wrapper over the service APIs. It does NOT touch scene nodes or UI directly.

### Authoring Tools

| Tool | Parameters | Returns |
|---|---|---|
| `project_create` | `name: str` | `{ project_path }` |
| `project_open` | `path: str` | `{ maps: [...] }` |
| `project_save` | `path?: str` | `{ path }` |
| `maps_list` | — | `[{ id, name, width, height, event_count }]` |
| `map_create` | `name, width, height` | `{ map_id }` |
| `map_paint_tile` | `map_id, layer, x, y, tile_id` | `{ ok }` |
| `map_fill_rect` | `map_id, layer, x, y, w, h, tile_id` | `{ ok }` |
| `event_create` | `map_id, x, y, name?` | `{ event_id }` |
| `event_add_page` | `map_id, event_id, trigger?, conditions?` | `{ page_index }` |
| `event_append_command` | `map_id, event_id, page_index, command` | `{ ok }` |

### Runtime / Test Tools

| Tool | Parameters | Returns |
|---|---|---|
| `scenario_run` | `scenario: dict or path` | `{ passed, failed, assertions, trace, snapshot }` |
| `runtime_snapshot` | — | `{ map_id, player_grid, switches_on, variables, event_running }` |
| `runtime_move` | `direction, times?` | `{ snapshot }` |
| `runtime_interact` | — | `{ snapshot }` |
| `runtime_advance_dialogue` | — | `{ snapshot }` |
| `runtime_choose` | `index` | `{ snapshot }` |
| `trace_read` | — | `[trace events since last call]` |

### Command Shape (for `event_append_command`)

> **On-disk note:** schema v4 serializes `type` as the `EventCommand.Type`
> enum name and page `trigger` as the `EventPage.Trigger` name, exactly as
> shown here. Integer ordinals (schema v3 and earlier) remain loadable for
> backward compatibility; `--resave <path>` migrates a file in place.
> The complete per-type param reference lives in `CLAUDE.md`.

```json
{ "type": "SHOW_TEXT",        "params": { "lines": ["Hello!"], "name": "NPC" } }
{ "type": "SHOW_CHOICES",     "params": { "choices": ["Yes", "No"], "cancel_index": -1 } }
{ "type": "CONTROL_SWITCHES", "params": { "ids": [1], "value": true } }
{ "type": "CONTROL_VARIABLES","params": { "ids": [2], "op": "add", "value": 5 } }
{ "type": "CONDITIONAL_BRANCH","params": { "condition_type": "switch", "id": 1, "value": true, "commands_if": [], "commands_else": [] } }
{ "type": "TRANSFER_PLAYER",  "params": { "map_id": 1, "x": 5, "y": 7 } }
{ "type": "SET_SELF_SWITCH",  "params": { "letter": "A", "value": true } }
{ "type": "WAIT",             "params": { "frames": 60 } }
```

---

## Trace Signal Reference

All signals defined in `SignalBus`. Collected automatically by `ScenarioRunner`.

| Signal | Payload |
|---|---|
| `trace_event_started` | `event_name, event_id, map_id` |
| `trace_event_finished` | `event_name, event_id` |
| `trace_command_executed` | `event_id, command_type, params` |
| `trace_switch_changed` | `id, value` |
| `trace_variable_changed` | `id, value` |
| `trace_transfer` | `from_map_id, to_map_id, x, y` |
| `trace_dialogue` | `speaker, text` |
| `trace_choice_made` | `index, label` |
| `trace_player_moved` | `grid_pos, map_id` |
| `trace_assertion_failed` | `message` |

---

## Recommended MCP Implementation Strategy

1. Write the MCP server as a Python or Node.js sidecar that communicates with Godot over a local socket or pipe.
2. The sidecar spawns `Godot --headless` for test runs and reads stdout for JSON results.
3. For authoring operations, the sidecar edits the `.rpgc` JSON file directly using the same schema that `ProjectState.serialize()` produces — no Godot process needed.
4. For runtime operations, use the headless runner.
5. Keep the MCP tool signatures stable even as internals change.

---

## Implementation Phases

| Phase | Scope | Status |
|---|---|---|
| 1 — Runtime harness | Scripted movement, interact, dialogue, snapshot | ✅ Done |
| 2 — Structured trace | `SignalBus.trace_*` signals | ✅ Done |
| 3 — Authoring service | `ProjectState` service methods | ✅ Done |
| 4 — Scenario runner | JSON scenario → assertions + trace | ✅ Done |
| 5 — Headless entrypoint | CLI launcher with exit codes | ✅ Done |
| 6 — MCP sidecar | Python/Node MCP server wrapping phases 1–5 | ⏸ Deferred (CLI-first — see above) |
| 7 — CI integration | GitHub Actions workflow running scenarios | ✅ Done (`.github/workflows/test.yml`) |
| 8 — Visual smoke tests | Screenshot capture for layout checks | 🔲 Planned (needs non-headless renderer) |
