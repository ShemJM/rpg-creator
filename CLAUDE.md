# CLAUDE.md

rpg-creator is an RPG Maker-style tool built in **Godot 4.6 / GDScript**. Humans use the in-engine editor UI; **agents author games by writing the project JSON directly and testing them with the headless runner** — no UI needed.

## The workflow

1. **Author** a game: write a `.rpgc`/`.rpgm` JSON file in `games/` (schema below).
2. **Validate**: `make validate P=games/<name>.rpgc` — sub-second lint with precise `path: message` errors (unknown command types, dangling transfer targets, out-of-bounds cells, bad params). Fix everything before running.
3. **Test**: write a `games/<name>_scenario.json` (scripted playthrough + assertions); validate it the same way (`make validate P=games/<name>_scenario.json`).
4. **Run**: `make run-scenario S=games/<name>_scenario.json` — exit 0 = pass, 1 = assertion failures, 2 = fatal. Read the printed assertions/trace, fix, repeat.
5. `make test` validates everything, runs every scenario in `games/`, and checks the database summary.

Setup: `make setup` resolves or downloads a Godot 4.6 binary into `bin/godot` (a SessionStart hook does this automatically in Claude Code web sessions; it needs network access to `github.com/godotengine`, or set `$GODOT` to an existing binary). There is no build step — GDScript is interpreted.

Canonical worked example: `games/lost_crystal.rpgm` + `games/lost_crystal_scenario.json`.

## Headless CLI

All invocations go through the Makefile (`make help`), which wraps:

```
bin/godot --headless --path . -- \
  [--project <path>] [--scenario <path>] [--validate <path>] \
  [--list-maps] [--list-database] [--map-id <int>] [--output <results.json>]
```

(User args after `--` divert `StartScreen` into `scripts/runtime/headless_runner.gd`; `godot --script` mode can't be used because autoload singletons only exist in a normal project run.)

- `--scenario` alone is enough when the scenario file has a `"project"` key.
- `--output` writes the result JSON to a file (stdout also carries Godot's banner, so parse the file, not stdout).
- Exit codes: `0` pass, `1` assertion failures, `2` fatal (bad args/file).

## Project file schema (`.rpgc` / `.rpgm`, plain JSON)

Written/read by `ProjectState.serialize()/deserialize()` (`scripts/autoloads/project_state.gd`). Top level:

```json
{
  "version": 4,
  "maps": [ ... ],
  "tileset": [ ... ],          // optional — omit to get the default 5-tile set
  "player_graphic": null,      // optional charset; null = colored-block player
  "database": { "actors": [], "classes": [], "items": [], "equipment": [] }
}
```

### Maps

```json
{
  "id": 0, "map_name": "Village", "width": 15, "height": 13,
  "ground_layer":  { "0,0": 0, "1,0": 0 },
  "surface_layer": { "3,4": 4 },
  "events": [ ... ]
}
```

- Layer keys are `"x,y"` strings → tile id (int). Cover **every** ground cell (`fill` the rect) — missing cells render empty.
- Default tileset ids: `0` Grass, `1` Dirt, `2` Stone (passable); `3` Water, `4` Wall (**impassable**). Impassable tiles on either layer block movement.
- **The player always spawns at the map center** (`width/2`, `height/2`, floored). Plan maps and `expect_position` assertions around that.

### Events → pages → commands

```json
{
  "id": 0, "event_name": "Old Man", "x": 5, "y": 4,
  "pages": [
    {
      "trigger": "ACTION_BUTTON",
      "graphic_color": [0.8, 0.2, 0.2, 1.0],
      "graphic": null,
      "condition_switch_id": -1, "condition_switch_value": true,
      "condition_self_switch": "", "condition_variable_id": -1, "condition_variable_gte": 0,
      "commands": [ { "type": "SHOW_TEXT", "params": { "lines": ["Hello!"], "name": "Old Man" } } ]
    }
  ]
}
```

- Event `id` must be unique within its map. Events sit on the map grid; an event with commands blocks movement onto its tile for Action Button triggers.
- `trigger`: `"ACTION_BUTTON"` (player presses interact while facing it), `"PLAYER_TOUCH"`, `"AUTORUN"` (fires when page becomes active), `"PARALLEL"` (loops in background). Legacy integer ordinals (0–3) also load.
- Page conditions all default to "none" (`-1` / `""`). The **last** page whose conditions hold is the active one. `condition_variable_gte` means variable ≥ value.
- `graphic_color` is a float RGBA array (0–1).

### Command types

`"type"` is the **enum name string** from `EventCommand.Type` (`scripts/resources/event_command.gd`). Legacy integer ordinals (the `#` column) also load — schema v3 and earlier used them.

| # | Type | params |
|---|------|--------|
| 0 | SHOW_TEXT | `{ "lines": ["..."], "name": "Speaker" }` |
| 1 | SHOW_CHOICES | `{ "choices": ["Yes","No"], "cancel_index": -1 }` |
| 2 | CONTROL_SWITCHES | `{ "ids": [1], "value": true }` |
| 3 | CONTROL_VARIABLES | `{ "ids": [2], "op": "set"\|"add"\|"sub"\|"mul"\|"div", "value": 5 }` |
| 4 | CONDITIONAL_BRANCH | `{ "condition_type": "switch"\|"variable_gte"\|"self_switch", "id": 1, "value": true, "commands_if": [...], "commands_else": [...] }` — for `switch`, `value` is bool; for `variable_gte`, condition is variable[id] ≥ value; for `self_switch`, `value` is the letter (`"A"`) |
| 5 | TRANSFER_PLAYER | `{ "map_id": 1, "x": 5, "y": 7 }` |
| 6 | SET_SELF_SWITCH | `{ "letter": "A", "value": true }` |
| 7 | WAIT | `{ "frames": 60 }` |
| 8 | PLAY_SE | stub — no audio yet |
| 9 | FADE_OUT | `{ "duration": 0.5 }` (seconds) |
| 10 | FADE_IN | `{ "duration": 0.5 }` |
| 11 | ERASE_EVENT | `{}` — hides event for rest of play-test |
| 12 | LABEL | `{ "name": "loop" }` |
| 13 | JUMP_TO_LABEL | `{ "name": "loop" }` |
| 14 | GAME_OVER | `{}` |
| 15 | MOVE_ROUTE | `{ "target": "player"\|"this", "steps": ["up","down","left","right","wait","face_up","face_down","face_left","face_right","turn_toward_player"], "wait_for_completion": true }` |

Follow-up branching after SHOW_CHOICES: the chosen index is written to **variable 0** — branch with CONDITIONAL_BRANCH on `condition_type: "variable"`. There are **100 switches and 100 variables** (ids 0–99), reset each play-test. Self-switches are per-event letters A–D.

### Database (authoring-only for now — not consumed at runtime)

`actors` (`actor_name`, `class_id`, `initial_level`, `stats`, `graphic`, `note`), `classes` (`class_name`, `stats`, `note`), `items` (`item_name`, `description`, `price`, `consumable`, `effect`), `equipment` (`equip_name`, `kind`: `"weapon"`/`"armor"`, `slot`, `price`, `stat_mods`, `note`). `stats`/`stat_mods` is a flat block: `max_hp, max_mp, atk, def, mat, mdf, agi, luk`. Database ids: unique, conventionally max+1.

## Scenario format (`games/*_scenario.json`)

```json
{
  "project": "games/my_game.rpgc",
  "start_map_id": 0,
  "steps": [
    { "action": "wait_frames", "count": 5 },
    { "action": "move", "direction": "right", "times": 3 },
    { "action": "interact" },
    { "action": "advance_dialogue" },
    { "action": "choose", "index": 1 },
    { "action": "expect_switch", "id": 1, "value": true },
    { "action": "expect_variable", "id": 0, "value": 1 },
    { "action": "expect_position", "map_id": 1, "x": 5, "y": 7 },
    { "action": "expect_player_facing", "x": 1, "y": 0 },
    { "action": "expect_event_facing", "id": 0, "x": -1, "y": 0 },
    { "action": "snapshot" }
  ]
}
```

Timing conventions that make scenarios deterministic:

- Start with `wait_frames: 5` so autorun/parallel events settle before you act.
- After `interact`, `advance_dialogue`, or `choose`, give the event runner frames to execute: `wait_frames` 5–10 before asserting.
- One `advance_dialogue` per SHOW_TEXT box; dialogue must be advanced before the event continues.
- Facing vectors: right `(1,0)`, left `(-1,0)`, up `(0,-1)`, down `(0,1)`.

Results JSON: `{ passed, failed, total, assertions: [{pass, message}], trace: [...], snapshot }`. The `trace` array logs every event start/finish, command, switch/variable change, transfer, dialogue line, choice, and player move — read it to debug why an assertion failed. Final `snapshot`: `{ map_id, map_name, player_grid, player_facing, event_facing, event_running, switches_on, variables }` (only non-false switches / non-zero variables listed).

## Gotchas

- **JSON only** — don't hand-write `.tscn`/`.tres` for game content; everything lives in the project file.
- Charset `source_path` is an absolute path today — **omit `graphic`/`player_graphic` (null)** for agent-built games; the colored-block fallback works everywhere including headless.
- Parallel pages that show dialogue can cross-talk with blocking events — keep parallel pages to switch/variable/wait/move logic.
- A scenario with zero `expect_*` steps exits 0 — always assert something.
- Editor UI code (`scripts/editor/`, `scenes/editor/`) is irrelevant to agent workflows; the runtime lives in `scripts/runtime/`.

## Repo map

- `scripts/autoloads/` — `ProjectState` (data + serialization + authoring API), `GameState` (switches/variables), `SignalBus` (incl. `trace_*` signals)
- `scripts/runtime/` — `runtime_player.gd` (map build + scripted control + snapshot), `event_runner.gd` (command interpreter), `scenario_runner.gd` (scenario execution), `headless_runner.gd` (CLI entry)
- `scripts/resources/` — data model (`map_data`, `event_data`, `event_page`, `event_command`, database resources)
- `games/` — game projects + scenarios; `docs/agent-mcp-plan.md` — agent interface blueprint
