# Roadmap

Roughly ordered by dependency. Each phase should be independently shippable.

---

## Phase 1 — Save / Load ✓

The most critical gap. Nothing else matters until project data survives a session.

- [x] Serialize `ProjectState` (maps, events, pages, commands) to JSON
- [x] Write to disk at a user-chosen path; load from path on open
- [x] Recent projects list in a start screen
- [x] Auto-save on play-test

---

## Phase 2 — Real Tilesets

- [ ] Import a tileset image (PNG) and slice into tiles
- [ ] Store tile passability flag per tile (not hardcoded)
- [ ] Replace stub colour buttons in the palette with tile thumbnails
- [ ] Support multiple tilesets per project

---

## Phase 3 — Character Graphics ✓

- [x] NPC/event sprite: assign a spritesheet (charset) to an event page
- [x] Event faces the player on interaction; `MOVE_ROUTE` gains `face_*` / `turn_toward_player` steps
- [x] Player spritesheet with walk animation (4-directional)
- [x] Walk cycle in the runtime (animates only while moving)
- [x] Editor graphic picker + charset thumbnails on the map canvas

---

## Phase 3.5 — Database (Actors / Items / Equipment) ✓ (subset)

The data backbone consumed by party/inventory/shops (and later combat).

- [x] Database editor panel wired to the `Database` nav button (Maps ↔ Database switching)
- [x] Actors (name, class, level, base stats, charset) — reuses the Phase 3 graphic picker
- [x] Classes (name, base stats)
- [x] Items (name, description, price, consumable, restore-HP/MP effect data)
- [x] Weapons & Armor (unified `EquipData`, split tabs by kind, stat bonuses)
- [x] Flat `StatBlock` (hp/mp/atk/def/mat/mdf/agi/luk) shared across the above
- [x] Project schema `version` 3 + serialization; headless `--list-database`
- [ ] Skills / Enemies / Troops — deferred to the battle phase (need combat to be useful)
- [ ] Per-level stat growth curves — deferred to the battle phase

---

## Phase 4 — More Event Commands

Commands that round out the scripting system:

- [x] `MOVE_ROUTE` — move an event or the player along a path
- [ ] `SHOW_PICTURE` / `ERASE_PICTURE` — overlay images on screen
- [ ] `CHANGE_TRANSPARENT` — hide/show the player sprite
- [ ] `PLAY_BGM` / `STOP_BGM` — background music
- [ ] `PLAY_SE` (implement) — sound effect playback
- [x] `FADE_OUT` / `FADE_IN` (implement) — actual screen colour fade
- [x] `GAME_OVER` — return to title
- [x] `LABEL` / `JUMP_TO_LABEL` — loop and goto within a command list

---

## Phase 5 — Parallel Events & Event Lifecycle ✓

- [x] Parallel trigger: run event every frame without blocking the player
- [x] Event pages re-evaluate conditions when switches/variables change
- [x] `erased` state: event can be permanently removed from the map

---

## Phase 6 — Editor Polish

- [ ] Undo / redo for tile painting and event edits
- [ ] Map properties panel (resize map, rename)
- [ ] Copy / paste event pages
- [ ] Event search / jump-to by ID
- [ ] Map transfer picker — choose target map and position from a visual picker
- [ ] In-editor play-test overlay instead of full scene swap

---

## Phase 7 — Battle System (optional / stretch)

If the project grows to include a full RPG loop:

- [ ] Encounter zones — tile flag triggers a random battle
- [ ] Turn-based battle scene with party vs. enemies
- [ ] Character stats resource (`HP`, `MP`, `ATK`, `DEF`, `SPD`)
- [ ] Skills and items as resources
- [ ] `BATTLE_PROCESSING` event command — start a scripted battle
- [ ] Win/lose conditions wired back to the event system

---

## Phase 8 — Export

- [ ] Package a project as a standalone Godot `.pck` (runtime-only, no editor)
- [ ] Export to HTML5 for browser play
