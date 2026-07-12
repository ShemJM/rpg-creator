# CLAUDE.md

rpg-creator is an RPG Maker-style tool built in **Godot 4.6 / GDScript**. Humans use the in-engine editor UI; **agents author games by writing the project JSON directly and testing them with the headless runner** — no UI needed.

## The workflow

1. **Author** a game: write a `.rpgc`/`.rpgm` JSON file in `games/` (schema below).
2. **Validate**: `make validate P=games/<name>.rpgc` — sub-second lint with precise `path: message` errors (unknown command types, dangling transfer targets, out-of-bounds cells, bad params). Fix everything before running.
3. **Test**: write a `games/<name>_scenario.json` (scripted playthrough + assertions); validate it the same way (`make validate P=games/<name>_scenario.json`).
4. **Run**: `make run-scenario S=games/<name>_scenario.json` — exit 0 = pass, 1 = assertion failures, 2 = fatal. Read the printed assertions/trace, fix, repeat.
5. `make test` validates everything, runs every scenario in `games/`, and checks the database summary.

Setup: `make setup` resolves or downloads a Godot 4.6 binary into `bin/godot` (a SessionStart hook does this automatically in Claude Code web sessions; it needs network access to `github.com/godotengine`, or set `$GODOT` to an existing binary). There is no build step — GDScript is interpreted.

Canonical worked examples: `games/lost_crystal.rpgm` (dialogue/switch adventure) and `games/adventure_demo.rpgc` (full RPG loop: quest → shop → equip → boss battle with a mid-fight item → transfer), each with a passing `*_scenario.json`.

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
  "version": 6,
  "maps": [ ... ],
  "tileset": [ ... ],          // optional — omit to get the default 5-tile set
  "player_graphic": null,      // optional charset; null = colored-block player
  "system": { "starting_party": [0], "starting_gold": 0 },  // optional
  "common_events": [ ... ],    // optional — reusable command lists (see below)
  "database": { "actors": [], "classes": [], "items": [], "equipment": [], "enemies": [] }
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

- Event `id` must be unique within its map. **Events never block movement** — only impassable tiles do. `interact` targets the tile the player is *facing* and works even if that tile is impassable, so the door-on-a-wall pattern (event placed on a wall tile, player interacts facing it) is the way to gate progress. A blocked `move` step still turns the player to face that direction.
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
| 4 | CONDITIONAL_BRANCH | `{ "condition_type": "switch"\|"variable_gte"\|"self_switch"\|"gold_gte"\|"has_item", "id": 1, "value": true, "commands_if": [...], "commands_else": [...] }` — `switch`: `value` bool; `variable_gte`: variable[id] ≥ value; `self_switch`: `value` is the letter; `gold_gte`: gold ≥ value; `has_item`: `{ "kind": "item"\|"equip", "id": n, "value": min count }` |
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
| 16 | CHANGE_GOLD | `{ "op": "add"\|"sub"\|"set", "value": 100 }` — gold clamps at 0 |
| 17 | CHANGE_ITEMS | `{ "kind": "item"\|"equip", "id": 0, "op": "add"\|"sub"\|"set", "count": 1 }` — stock clamps at 0 |
| 18 | CHANGE_HP | `{ "actor_id": -1 (whole party) \| id, "op": "add"\|"sub"\|"set", "value": 20, "allow_ko": false }` — without `allow_ko` HP floors at 1; with it, a full party wipe triggers game over |
| 19 | CHANGE_EQUIPMENT | `{ "actor_id": 0, "slot": "weapon"\|"head"\|"body"\|"accessory", "equip_id": 3 }` — `-1` unequips; equipping consumes the piece from equip stock (grant it with CHANGE_ITEMS `kind:"equip"` first), unequipping returns it |
| 20 | USE_ITEM | `{ "item_id": 0, "actor_id": 0 }` — applies the item's `effect` `{"hp": n, "mp": n}` restore; consumables decrement; no-op (traced `ok:false`) if out of stock |
| 21 | SHOP_PROCESSING | `{ "entries": [ { "kind": "item"\|"equip", "id": 0, "price": 30 } ] }` — `price` optional (defaults to database price); sell price = floor(db price / 2); **blocks the event until the shop closes** — drive it with the `shop_buy`/`shop_sell`/`shop_close` scenario actions |
| 22 | BATTLE_PROCESSING | `{ "enemies": [enemy_id, ...], "can_flee": true, "commands_win": [...], "commands_lose": [...] }` — blocks until the battle ends; `win` splices `commands_win`, `lose` splices `commands_lose` (**empty `commands_lose` = game over**), `flee` continues past the command |
| 23 | CALL_COMMON_EVENT | `{ "id": 0 }` — runs the referenced common event's commands inline (reusable subroutine), then resumes; blocks if the common event has blocking commands |

Follow-up branching after SHOW_CHOICES: the chosen index is written to **variable 0** — branch with CONDITIONAL_BRANCH on `condition_type: "variable"`. There are **100 switches and 100 variables** (ids 0–99), reset each play-test. Self-switches are per-event letters A–D.

### Common events (reusable logic)

Top-level `"common_events": [ { "id", "name", "trigger", "condition_switch_id", "commands": [...] } ]`. A common event is a shared command list:

- `trigger: "NONE"` — runs only when invoked via `CALL_COMMON_EVENT { "id": n }` from any event (the reusable-subroutine case). Blocks the caller if it contains blocking commands.
- `trigger: "PARALLEL"` — loops in the background while `condition_switch_id` holds (`-1` = always). Keep these to switch/variable/wait logic (no dialogue — same cross-talk caveat as parallel event pages).
- `trigger: "AUTORUN"` — fires once (edge-triggered, non-blocking) when `condition_switch_id` turns on.

Worked example: `games/common_event_demo.rpgc` (a "give gold" common called from two merchants + a parallel watcher that opens a vault at 50 gold).

### Database & party (live at runtime since v5)

`actors` (`actor_name`, `class_id`, `initial_level`, `stats`, `graphic`, `note`), `classes` (`class_name`, `stats`, `note`), `items` (`item_name`, `description`, `price`, `consumable`, `effect`: `{"hp": n, "mp": n}` restore), `equipment` (`equip_name`, `kind`: `"weapon"`/`"armor"`, `slot`: `"weapon"|"head"|"body"|"accessory"`, `price`, `stat_mods`, `note`), `enemies` (`enemy_name`, `stats`, `gold_reward`, `item_rewards`: `[{kind, id, count}]` — deterministic, no drop chances). `stats`/`stat_mods` is a flat block: `max_hp, max_mp, atk, def, mat, mdf, agi, luk`. Database ids: unique, conventionally max+1.

Runtime party rules:

- Play-test start builds the party from `system.starting_party` (default: the lowest actor id) with `system.starting_gold` (default 0). Party membership is fixed during play (no add/remove command yet).
- **Effective stats = actor base `stats` + Σ equipped `stat_mods`** (class stats are authoring-only; no level growth yet). HP/MP start at computed max.
- Items and equipment have **separate id spaces and stock pools** (`kind: "item"` vs `"equip"`).
- All changes are traced (`gold_changed`, `item_changed`, `hp_changed`, `equip_changed`, `item_used`) and visible in the snapshot: `gold`, `inventory`, `equip_inventory`, `party: [{actor_id, name, hp, max_hp, mp, max_mp, stats, equipment}]`.

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
    { "action": "expect_dialogue", "contains": "Hello", "speaker": "Old Man" },
    { "action": "expect_event_erased", "id": 0, "value": true },
    { "action": "expect_event_running", "value": false },
    { "action": "expect_game_over", "value": false },
    { "action": "expect_gold", "value": 40 },
    { "action": "expect_item_count", "kind": "item", "id": 0, "value": 2 },
    { "action": "expect_party_size", "value": 1 },
    { "action": "expect_actor_hp", "actor_id": 0, "value": 90 },
    { "action": "expect_actor_stat", "actor_id": 0, "stat": "atk", "value": 17 },
    { "action": "shop_buy", "index": 0, "count": 1 },
    { "action": "shop_sell", "kind": "item", "id": 0, "count": 1 },
    { "action": "shop_close" },
    { "action": "expect_shop_open", "value": false },
    { "action": "snapshot" }
  ]
}
```

Shop flow: `interact` with the shop event → `advance_dialogue` past any greeting → the shop opens (`expect_shop_open`) → `shop_buy` (index into the SHOP_PROCESSING entries) / `shop_sell` (any stocked item, half price) → `shop_close` resumes the event. A rejected buy (not enough gold) changes nothing and is traced with `ok: false`.

### Battle (deterministic — design scenarios around these exact rules)

- Party fights with **live HP** (battle damage persists after the battle). Each round waits for one command per living party member in party order — supply them with `battle_attack {"target": enemy_index}`, `battle_item {"item_id", "target_actor_id"?}` (consumes the turn), or `battle_flee` — then resolves synchronously.
- Turn order: `agi` descending; ties → party before enemies, then lower index. Enemy AI: basic attack on the lowest-index living party member. A dead attack target retargets to the first living one.
- **Damage** = `max(1, base * rng(90..110) / 100)` where `base = max(1, atk - def / 2)` (integer division). That rng roll is the only randomness (seed 0 unless the scenario sets `rng_seed`), so damage varies ±10% — bound assertions with `expect_enemy_hp {"index", "lte"}` / `expect_actor_hp {"gte"}`, or design HP totals so the outcome is variance-proof (e.g. 20 HP enemy vs 10–13 damage = always exactly 2 hits).
- `battle_flee` succeeds iff `can_flee` (a failed attempt wastes the turn). Win grants every enemy's `gold_reward` + `item_rewards`.
- Assertions: `expect_battle_active {value}`, `expect_battle_result {value: "win"|"lose"|"flee"}` (persists after the battle), `expect_enemy_hp {index, value|lte}`. Snapshot carries `battle: {active, round, pending_actor_id, enemies, last_result}`; the trace logs `battle_started/round/action/ended` with per-action damage.
- Worked examples: `games/battle_demo.rpgc` with `battle_demo_scenario.json` (flee, then a 2-round win) and `battle_lose_scenario.json` (unwinnable → game over).

Optional top-level `"rng_seed"` (int): gameplay randomness flows through one seeded RNG (`GameState.rng`, default seed 0), so runs are always reproducible — set `rng_seed` only to explore alternate outcomes. `expect_actor_hp` also accepts `"gte"` instead of `"value"`.

An optional top-level `"timeout_frames"` (default 6000) fails the run with a `timeout` assertion if it doesn't finish in time. `expect_dialogue` matches against **all** dialogue seen so far (lines of one box are joined with `\n`).

Timing conventions that make scenarios deterministic:

- Start with `wait_frames: 5` so autorun/parallel events settle before you act.
- After `interact`, `advance_dialogue`, or `choose`, give the event runner frames to execute: `wait_frames` 5–10 before asserting.
- One `advance_dialogue` per SHOW_TEXT box; dialogue must be advanced before the event continues.
- Facing vectors: right `(1,0)`, left `(-1,0)`, up `(0,-1)`, down `(0,1)`.

Results JSON: `{ passed, failed, total, assertions: [{pass, message}], trace: [...], snapshot }`. The `trace` array logs every event start/finish, command, switch/variable/self-switch change, transfer, dialogue line, choice, game over, player move, and every gold/item/HP/MP/equipment change — read it to debug why an assertion failed. Final `snapshot`: `{ map_id, map_name, player_grid, player_facing, event_facing, event_running, events_erased, switches_on, variables, gold, inventory, equip_inventory, party }` (only non-false switches / non-zero variables/stock listed).

`make test-scenarios` runs every scenario in `games/` inside **one** engine boot (`--test-all games`), so the suite stays fast as games accumulate.

## Gotchas

- **JSON only** — don't hand-write `.tscn`/`.tres` for game content; everything lives in the project file.
- Charset/tileset `source_path` should be **relative to the project file** (e.g. `assets/hero.png` next to the `.rpgc`) so games stay portable; absolute and `res://` paths also load. Simplest for agent-built games: **omit `graphic`/`player_graphic` (null)** — the colored-block fallback works everywhere including headless.
- Parallel pages that show dialogue can cross-talk with blocking events — keep parallel pages to switch/variable/wait/move logic.
- A scenario with zero `expect_*` steps exits 0 — always assert something.
- Editor UI code (`scripts/editor/`, `scenes/editor/`) is irrelevant to agent workflows; the runtime lives in `scripts/runtime/`.

## Repo map

- `scripts/autoloads/` — `ProjectState` (data + serialization + authoring API), `GameState` (switches/variables), `SignalBus` (incl. `trace_*` signals)
- `scripts/runtime/` — `runtime_player.gd` (map build + scripted control + snapshot), `event_runner.gd` (command interpreter), `scenario_runner.gd` (scenario execution), `headless_runner.gd` (CLI entry)
- `scripts/resources/` — data model (`map_data`, `event_data`, `event_page`, `event_command`, database resources)
- `games/` — game projects + scenarios; `docs/agent-mcp-plan.md` — agent interface blueprint
