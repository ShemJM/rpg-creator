class_name EventPage
extends Resource
## One page of an event. The active page is determined by conditions.

enum Trigger {
	ACTION_BUTTON,
	PLAYER_TOUCH,
	AUTORUN,
	PARALLEL,
}

## Conditions — all must be true for this page to be active.
@export var condition_switch_id: int = -1  ## -1 = no condition
@export var condition_switch_value: bool = true
@export var condition_self_switch: String = ""  ## "", "A", "B", "C", "D"
@export var condition_variable_id: int = -1
@export var condition_variable_gte: int = 0

@export var trigger: Trigger = Trigger.ACTION_BUTTON
@export var graphic_color: Color = Color(0.8, 0.2, 0.2)  ## Fallback when graphic is null
## Optional character spritesheet for this page. Falls back to graphic_color when null.
@export var graphic: CharacterGraphic = null
@export var commands: Array[EventCommand] = []
