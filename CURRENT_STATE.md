# Current State

> Last updated: 2026-05-21

## What works

### Editor

- **Map editor** — tile palette with colour-coded tile buttons; paint (pencil), erase, and bucket-fill tools; two layers (ground, surface).
- **Map list** — create multiple maps per project; switch between them.
- **Event placement** — click any map cell in event mode to place or select an event.
- **Event editor panel** — multi-page events; add/remove pages via tabs; per-page trigger selector (Action Button, Player Touch, Autorun, Parallel).
- **Page conditions** — switch condition, self-switch condition, variable condition.
- **Command list** — add commands from a dropdown; each command renders as an editable row in the list.
- **All core commands** are editable in the panel: Show Text, Show Choices, Control Switches, Control Variables, Conditional Branch, Transfer Player, Set Self Switch, Wait.

### Runtime (play-test)

- **Map rendering** — ground and surface layers drawn as coloured tiles; impassable tiles get static collision bodies.
- **Player movement** — 4-directional grid-locked movement on passable tiles.
- **Event triggering** — Action Button events fire on player interaction; Player Touch events fire on contact; Autorun events fire on map load.
- **Event runner** — sequential command execution with coroutine-style pausing for dialogue and choices.
- **Dialogue box** — shows speaker name + lines; advances on confirm input.
- **Choices** — presents a button list; branches execution based on player selection.
- **Switches & variables** — 100 global switches, 100 global variables; reset each play-test.
- **Self-switches** — A/B/C/D per event; used for page conditions.
- **Conditional branch** — branches on switch value, variable comparison, or self-switch.
- **Transfer Player** — warps player to a different map and position.

### Infrastructure

- `ProjectState` autoload holds all map/event data in memory (no save/load yet).
- `GameState` autoload manages runtime switches/variables.
- `SignalBus` wires editor ↔ runtime events without direct coupling.
- `DesignTokens` + `ThemeBuilder` provide a consistent dark UI theme.

## Known gaps / rough edges

- **No save/load** — project data lives in memory only; closing Godot loses everything.
- **No real tileset** — tiles are stub colour blocks; no image import.
- **Fade commands are stubs** — `FADE_OUT` / `FADE_IN` and `PLAY_SE` advance immediately with no visual/audio effect.
- **No NPC/character sprites** — events show as coloured markers; no character graphics yet.
- **Map transfer UX** — Transfer Player command works at runtime but there is no editor UI for picking the target map by name.
- **Parallel events** — trigger type exists in the data model but is not yet processed by the runtime (only sequential autorun/action events run).
- **No undo/redo** in the editor.
