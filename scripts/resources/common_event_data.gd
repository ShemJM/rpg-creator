class_name CommonEventData
extends Resource
## A reusable command list, callable from any event via CALL_COMMON_EVENT, or
## run globally in the background. Commands (de)serialize through ProjectState
## like event pages, so branch/loop nesting is handled there.

## NONE     — only runs when invoked via CALL_COMMON_EVENT.
## AUTORUN  — fires once (edge-triggered) when its condition switch turns on.
## PARALLEL — loops in the background while its condition switch holds.
enum Trigger { NONE, AUTORUN, PARALLEL }

@export var id: int = 0
@export var name: String = "Common Event"
@export var trigger: Trigger = Trigger.NONE
## -1 = no condition (AUTORUN/PARALLEL then depend only on the trigger).
@export var condition_switch_id: int = -1
@export var commands: Array[EventCommand] = []
