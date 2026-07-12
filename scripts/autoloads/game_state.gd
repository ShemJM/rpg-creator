extends Node
## Runtime game state — switches, variables, party, gold, inventory.
## Reset on each play-test. All mutators emit trace signals so the event
## runner, shop UI, and battle manager share one observable emission point.

const MAX_SWITCHES: int = 100
const MAX_VARIABLES: int = 100
const EQUIP_SLOTS: Array[String] = ["weapon", "head", "body", "accessory"]
## Constant default seed so runs WITHOUT an explicit scenario "rng_seed"
## are still reproducible.
const DEFAULT_RNG_SEED: int = 0

var switches: Array[bool] = []
var variables: Array[int] = []

var gold: int = 0
var inventory: Dictionary = {}        # item_id (int) -> count (int > 0)
var equip_inventory: Dictionary = {}  # equip_id (int) -> count (int > 0)
## Ordered party members:
## { "actor_id": int, "name": String, "hp": int, "mp": int,
##   "equipment": { "weapon": -1, "head": -1, "body": -1, "accessory": -1 } }
var party: Array[Dictionary] = []

## The single source of randomness for gameplay (battle variance). Seeded in
## reset(); scenarios may re-seed via a top-level "rng_seed".
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	reset()


func reset() -> void:
	switches.clear()
	switches.resize(MAX_SWITCHES)
	switches.fill(false)
	variables.clear()
	variables.resize(MAX_VARIABLES)
	variables.fill(0)
	rng.seed = DEFAULT_RNG_SEED
	inventory.clear()
	equip_inventory.clear()
	_init_party_from_project()


# ---------------------------------------------------------------------------
# Switches / variables
# ---------------------------------------------------------------------------

func get_switch(id: int) -> bool:
	if id < 0 or id >= switches.size():
		return false
	return switches[id]


func set_switch(id: int, value: bool) -> void:
	if id >= 0 and id < switches.size():
		switches[id] = value


func get_variable(id: int) -> int:
	if id < 0 or id >= variables.size():
		return 0
	return variables[id]


func set_variable(id: int, value: int) -> void:
	if id >= 0 and id < variables.size():
		variables[id] = value


func modify_variable(id: int, op: String, value: int) -> void:
	if id < 0 or id >= variables.size():
		return
	match op:
		"set": variables[id] = value
		"add": variables[id] += value
		"sub": variables[id] -= value
		"mul": variables[id] *= value
		"div":
			if value != 0:
				variables[id] /= value


# ---------------------------------------------------------------------------
# Party
# ---------------------------------------------------------------------------

## Build the starting party from ProjectState's database + "system" settings.
## Default when no starting_party is authored: the lowest actor id.
func _init_party_from_project() -> void:
	party.clear()
	gold = 0
	if ProjectState.actors.is_empty():
		return
	var settings: Dictionary = ProjectState.system_settings
	gold = maxi(0, int(settings.get("starting_gold", 0)))
	var starting: Array = settings.get("starting_party", [])
	if starting.is_empty():
		var lowest: ActorData = null
		for a: ActorData in ProjectState.actors:
			if lowest == null or a.id < lowest.id:
				lowest = a
		starting = [lowest.id]
	for actor_id in starting:
		var actor := ProjectState.get_actor_by_id(int(actor_id))
		if actor == null:
			continue
		var member := {
			"actor_id": actor.id,
			"name": actor.actor_name,
			"hp": 0,
			"mp": 0,
			"equipment": { "weapon": -1, "head": -1, "body": -1, "accessory": -1 },
		}
		party.append(member)
		var stats := get_member_stats(actor.id)
		member["hp"] = stats["max_hp"]
		member["mp"] = stats["max_mp"]


func get_member(actor_id: int) -> Dictionary:
	for m in party:
		if m["actor_id"] == actor_id:
			return m
	return {}


## Effective stats: actor base stats + sum of equipped stat_mods.
## (Class stats are authoring-only for now; no level growth.)
func get_member_stats(actor_id: int) -> Dictionary:
	var actor := ProjectState.get_actor_by_id(actor_id)
	var member := get_member(actor_id)
	if actor == null or member.is_empty():
		return {}
	var stats: Dictionary = actor.stats.to_dict()
	for slot in EQUIP_SLOTS:
		var equip_id: int = member["equipment"].get(slot, -1)
		if equip_id < 0:
			continue
		var eq := ProjectState.get_equip_by_id(equip_id)
		if eq == null:
			continue
		var mods: Dictionary = eq.stat_mods.to_dict()
		for key in mods:
			stats[key] = int(stats.get(key, 0)) + int(mods[key])
	return stats


func is_party_defeated() -> bool:
	if party.is_empty():
		return false
	for m in party:
		if int(m["hp"]) > 0:
			return false
	return true


# ---------------------------------------------------------------------------
# Gold / stock
# ---------------------------------------------------------------------------

func change_gold(op: String, value: int) -> void:
	var before := gold
	match op:
		"set": gold = value
		"add": gold += value
		"sub": gold -= value
	gold = maxi(0, gold)
	SignalBus.trace_gold_changed.emit(gold, gold - before)


func get_stock(kind: String, id: int) -> int:
	var pool := equip_inventory if kind == "equip" else inventory
	return int(pool.get(id, 0))


## Adjust item ("item") or equipment ("equip") stock. Clamped at 0; zero
## counts are removed from the dictionary.
func change_stock(kind: String, id: int, op: String, count: int) -> void:
	var pool := equip_inventory if kind == "equip" else inventory
	var current: int = int(pool.get(id, 0))
	match op:
		"set": current = count
		"add": current += count
		"sub": current -= count
	current = maxi(0, current)
	if current == 0:
		pool.erase(id)
	else:
		pool[id] = current
	SignalBus.trace_item_changed.emit(kind, id, current)


# ---------------------------------------------------------------------------
# HP / MP / items / equipment
# ---------------------------------------------------------------------------

## Change one member's (or with actor_id -1 the whole party's) HP.
## HP clamps to 0..max_hp; without allow_ko it floors at 1 instead.
func change_hp(actor_id: int, op: String, value: int, allow_ko: bool = false) -> void:
	for m in party:
		if actor_id >= 0 and int(m["actor_id"]) != actor_id:
			continue
		var stats := get_member_stats(int(m["actor_id"]))
		var max_hp: int = int(stats.get("max_hp", 1))
		var hp: int = int(m["hp"])
		match op:
			"set": hp = value
			"add": hp += value
			"sub": hp -= value
		hp = clampi(hp, 0, max_hp)
		if not allow_ko:
			hp = maxi(hp, 1)
		m["hp"] = hp
		SignalBus.trace_hp_changed.emit(int(m["actor_id"]), hp, max_hp)


func change_mp(actor_id: int, op: String, value: int) -> void:
	for m in party:
		if actor_id >= 0 and int(m["actor_id"]) != actor_id:
			continue
		var stats := get_member_stats(int(m["actor_id"]))
		var max_mp: int = int(stats.get("max_mp", 0))
		var mp: int = int(m["mp"])
		match op:
			"set": mp = value
			"add": mp += value
			"sub": mp -= value
		m["mp"] = clampi(mp, 0, max_mp)
		SignalBus.trace_mp_changed.emit(int(m["actor_id"]), int(m["mp"]), max_mp)


## Apply an item's effect ({"hp": n, "mp": n} restore) to a party member.
## Consumables decrement stock. Returns false (and traces ok=false) when the
## item is missing from stock, unknown, or the actor isn't in the party.
func use_item(item_id: int, actor_id: int) -> bool:
	var item := ProjectState.get_item_by_id(item_id)
	var member := get_member(actor_id)
	var ok := item != null and not member.is_empty() and get_stock("item", item_id) > 0
	if ok:
		var effect: Dictionary = item.effect
		if int(effect.get("hp", 0)) != 0:
			change_hp(actor_id, "add", int(effect.get("hp", 0)))
		if int(effect.get("mp", 0)) != 0:
			change_mp(actor_id, "add", int(effect.get("mp", 0)))
		if item.consumable:
			change_stock("item", item_id, "sub", 1)
	SignalBus.trace_item_used.emit(item_id, actor_id, ok)
	return ok


## Equip equip_id into a slot (consuming it from equip_inventory) or pass -1
## to unequip (returning the piece to equip_inventory). Returns success.
func equip(actor_id: int, slot: String, equip_id: int) -> bool:
	var member := get_member(actor_id)
	if member.is_empty() or not EQUIP_SLOTS.has(slot):
		return false
	if equip_id >= 0:
		var eq := ProjectState.get_equip_by_id(equip_id)
		if eq == null or get_stock("equip", equip_id) < 1:
			return false
	var previous: int = int(member["equipment"].get(slot, -1))
	if previous >= 0:
		change_stock("equip", previous, "add", 1)
	if equip_id >= 0:
		change_stock("equip", equip_id, "sub", 1)
	member["equipment"][slot] = equip_id
	SignalBus.trace_equip_changed.emit(actor_id, slot, equip_id)
	# Equipment can raise max_hp/max_mp; keep current values in range.
	var stats := get_member_stats(actor_id)
	member["hp"] = mini(int(member["hp"]), int(stats.get("max_hp", 1)))
	member["mp"] = mini(int(member["mp"]), int(stats.get("max_mp", 0)))
	return true
