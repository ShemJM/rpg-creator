# Current State

> Last updated: 2026-06-09

## What works

### Editor

- **Map editor** — tile palette with colour-coded tile buttons; paint (pencil), erase, and bucket-fill tools; two layers (ground, surface).
- **Map list** — create multiple maps per project; switch between them.
- **Event placement** — click any map cell in event mode to place or select an event.
- **Event editor panel** — multi-page events; add/remove pages via tabs; per-page trigger selector (Action Button, Player Touch, Autorun, Parallel).
- **Page conditions** — switch condition, self-switch condition, variable condition.
- **Command list** — add commands from a dropdown; each command renders as an editable row in the list.
- **All core commands** are editable in the panel: Show Text, Show Choices, Control Switches, Control Variables, Conditional Branch, Transfer Player, Set Self Switch, Wait, Fade Out/In, Move Route, Label, Jump to Label, Erase Event, Game Over.

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
- **Screen fade** — `FADE_OUT` / `FADE_IN` tween a full-screen overlay; execution resumes when the fade completes.
- **Move routes** — `MOVE_ROUTE` walks the player or the owning event along a step list (`up`/`down`/`left`/`right`/`wait`), respecting tile passability, optionally blocking until done.
- **Labels & jumps** — `LABEL` / `JUMP_TO_LABEL` allow loops and gotos within a command list (jumps from inside a conditional branch find page-level labels).
- **Erase event** — `ERASE_EVENT` hides the event for the rest of the play-test; remaining commands still run.
- **Game over** — `GAME_OVER` ends the play-test immediately.
- **Parallel events** — pages with the Parallel trigger run in their own runner without blocking the player, looping while their conditions hold.
- **Page re-evaluation** — event pages re-evaluate when switches, variables, or self-switches change; visuals update, parallel runners start/stop, and autorun pages fire when they *become* active (edge-triggered).

### Infrastructure

- `ProjectState` autoload holds all map/event data in memory (no save/load yet).
- `GameState` autoload manages runtime switches/variables.
- `SignalBus` wires editor ↔ runtime events without direct coupling.
- `DesignTokens` + `ThemeBuilder` provide a consistent dark UI theme.

## Known gaps / rough edges

- **No save/load** — project data lives in memory only; closing Godot loses everything.
- **No real tileset** — tiles are stub colour blocks; no image import.
- **`PLAY_SE` is a stub** — advances immediately with no audio playback.
- **No NPC/character sprites** — events show as coloured markers; no character graphics yet.
- **Map transfer UX** — Transfer Player command works at runtime but there is no editor UI for picking the target map by name.
- **Parallel events + dialogue** — a parallel event showing text while a blocking event also waits on dialogue can cross-talk; parallel pages are best used for switch/variable/wait/move logic.
- **No undo/redo** in the editor.
