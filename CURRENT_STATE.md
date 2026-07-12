# Current State

> Last updated: 2026-07-12

## What works

### Editor

- **Map editor** — tile palette with colour-coded tile buttons; paint (pencil), erase, and bucket-fill tools; two layers (ground, surface).
- **Map list** — create multiple maps per project; switch between them.
- **Event placement** — click any map cell in event mode to place or select an event.
- **Event editor panel** — multi-page events; add/remove pages via tabs; per-page trigger selector (Action Button, Player Touch, Autorun, Parallel).
- **Character graphics** — assign a spritesheet (charset) to an event page via a graphic picker (file + frame slicing + preview); events render as directional sprites on the map canvas and at runtime, with a colour-block fallback when unset.
- **Tileset import** — import a Tiled `.tsj`/`.json` tileset; per-tile passability; palette shows tile thumbnails.
- **Database editor** — reached via the `Database` nav button (Maps ↔ Database switching). Authors Actors (name/class/level/base stats/charset), Classes, Items (price/consumable/HP·MP restore), and Weapons/Armor (stat bonuses). Shared flat `StatBlock` (hp/mp/atk/def/mat/mdf/agi/luk). Persisted in the project (schema v3).
- **Page conditions** — switch condition, self-switch condition, variable condition.
- **Command list** — add commands from a dropdown; each command renders as an editable row in the list.
- **All core commands** are editable in the panel: Show Text, Show Choices, Control Switches, Control Variables, Conditional Branch, Transfer Player, Set Self Switch, Wait, Fade Out/In, Move Route, Label, Jump to Label, Erase Event, Game Over.

### Runtime (play-test)

- **Map rendering** — ground and surface layers drawn as coloured tiles; impassable tiles get static collision bodies.
- **Player movement** — 4-directional movement on passable tiles; player renders as an animated directional sprite (from `ProjectState.player_graphic`) that walks while moving and faces its heading, with a colour-block fallback.
- **Event facing** — events turn to face the player when interacted with; `MOVE_ROUTE` supports `face_up/down/left/right` and `turn_toward_player` steps.
- **Event triggering** — Action Button events fire on player interaction; Player Touch events fire on contact; Autorun events fire on map load.
- **Event runner** — sequential command execution with coroutine-style pausing for dialogue and choices.
- **Dialogue box** — shows speaker name + lines; advances on confirm input.
- **Choices** — presents a button list; branches execution based on player selection.
- **Switches & variables** — 100 global switches, 100 global variables; reset each play-test.
- **Self-switches** — A/B/C/D per event; used for page conditions.
- **Conditional branch** — branches on switch value, variable comparison, or self-switch.
- **Transfer Player** — warps player to a different map and position.
- **Screen fade** — `FADE_OUT` / `FADE_IN` tween a full-screen overlay; execution resumes when the fade completes.
- **Move routes** — `MOVE_ROUTE` walks the player or the owning event along a step list (`up`/`down`/`left`/`right`/`wait`), respecting tile passability, optionally blocking until done.
- **Labels & jumps** — `LABEL` / `JUMP_TO_LABEL` allow loops and gotos within a command list (jumps from inside a conditional branch find page-level labels).
- **Erase event** — `ERASE_EVENT` hides the event for the rest of the play-test; remaining commands still run.
- **Game over** — `GAME_OVER` ends the play-test immediately.
- **Parallel events** — pages with the Parallel trigger run in their own runner without blocking the player, looping while their conditions hold.
- **Page re-evaluation** — event pages re-evaluate when switches, variables, or self-switches change; visuals update, parallel runners start/stop, and autorun pages fire when they *become* active (edge-triggered).
- **Party & resources** — starting party from the `system` block, live HP/MP, gold, item/equipment stock, equipment slots that modify effective stats; commands `CHANGE_GOLD`, `CHANGE_ITEMS`, `CHANGE_HP`, `CHANGE_EQUIPMENT`, `USE_ITEM`; branch conditions `gold_gte` / `has_item`.
- **Shops** — `SHOP_PROCESSING` opens a buy/sell session (database or override prices, half-price sells) that blocks the event until closed; fully scriptable headlessly.
- **Battle v1** — `BATTLE_PROCESSING` runs a deterministic turn-based fight (agi order, ±10% seeded damage variance, enemy AI, items and fleeing, win/lose command branches, gold + item rewards). Managed by `BattleManager` with a minimal reactive `BattleUI`.
- **Advanced scripting** — the event interpreter is a frame stack, so nested branches, loops, and calls compose correctly. `CALL_COMMON_EVENT` invokes reusable command lists (top-level `common_events`, callable / autorun / parallel). `LOOP`/`BREAK_LOOP` are first-class. `CONTROL_VARIABLES` and `CONDITIONAL_BRANCH` take operands (constant / variable / seeded random / game-data like gold, item count, actor HP/stat) and full comparison operators. No arbitrary-code "Script" command — everything stays typed, validatable, and deterministic.

### Infrastructure

- `ProjectState` autoload holds all map/event data in memory and serializes it to JSON (`.rpgc`); save/load with a start screen and recent-projects list; also exposes an authoring service API for agents/tests. Project schema is at `version` 4 — command types and page triggers serialize as enum-name strings; older integer-typed files (v1–v3) still load, and `--resave` migrates them. Asset paths may be project-relative (portable), absolute, or `res://`.
- `GameState` autoload manages runtime switches/variables.
- `SignalBus` wires editor ↔ runtime events without direct coupling.
- `DesignTokens` + `ThemeBuilder` provide a consistent dark UI theme.

### Agent workflow (see CLAUDE.md)

- **Headless CLI** — `godot --headless --path . -- <flags>` runs scenarios, validates project/scenario files (`--validate`), runs the whole suite in one boot (`--test-all`), migrates schemas (`--resave`), and lists maps/database. `Makefile` wraps the canonical commands; `scripts/setup-godot.sh` bootstraps a Godot binary (auto-run by a Claude Code SessionStart hook).
- **Scenario tests** — JSON playthroughs with assertions (position, facing, switches, variables, dialogue content, event erasure, game over) plus a timeout watchdog; full structured trace + snapshot output for debugging.
- **Validator** — `scripts/runtime/project_validator.gd` lints raw project/scenario JSON with precise path+message errors before anything runs.
- **CI** — `.github/workflows/test.yml` runs `make test` on every push.

## Known gaps / rough edges

- **`PLAY_SE` is a stub** — advances immediately with no audio playback (no BGM/SE yet).
- **Party is fixed at play-test start** — no CHANGE_PARTY command yet; class stats are authoring-only (no level growth); no skills, no random encounter zones, no troops table (BATTLE_PROCESSING takes inline enemy ids); item effects are HP/MP restore only.
- **No editor UI yet for the v5 systems** — the party/shop/battle commands and enemies table are authorable via JSON (agents) but not yet in the event editor panel / database panel.
- **Map transfer UX** — Transfer Player command works at runtime but there is no editor UI for picking the target map by name.
- **Parallel events + dialogue** — a parallel event showing text while a blocking event also waits on dialogue can cross-talk; parallel pages are best used for switch/variable/wait/move logic.
- **No undo/redo** in the editor.
