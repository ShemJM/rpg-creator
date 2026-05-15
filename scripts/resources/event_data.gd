class_name EventData
extends Resource
## A single event placed on a map. Has one or more pages.

@export var id: int = 0
@export var event_name: String = "Event"
@export var x: int = 0
@export var y: int = 0

## Self-switches for this event instance (A, B, C, D).
var self_switches: Dictionary = { "A": false, "B": false, "C": false, "D": false }

@export var pages: Array[EventPage] = []


func get_active_page() -> EventPage:
	## Returns the highest-index page whose conditions are met.
	for i in range(pages.size() - 1, -1, -1):
		if _page_conditions_met(pages[i]):
			return pages[i]
	return null


func _page_conditions_met(page: EventPage) -> bool:
	# Switch condition.
	if page.condition_switch_id >= 0:
		var switch_val: bool = GameState.get_switch(page.condition_switch_id)
		if switch_val != page.condition_switch_value:
			return false
	# Self-switch condition.
	if page.condition_self_switch != "":
		if not self_switches.get(page.condition_self_switch, false):
			return false
	# Variable condition.
	if page.condition_variable_id >= 0:
		var var_val: int = GameState.get_variable(page.condition_variable_id)
		if var_val < page.condition_variable_gte:
			return false
	return true
