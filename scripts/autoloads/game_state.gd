extends Node
## Runtime game state — switches, variables. Reset on each play-test.

const MAX_SWITCHES: int = 100
const MAX_VARIABLES: int = 100

var switches: Array[bool] = []
var variables: Array[int] = []


func _ready() -> void:
	reset()


func reset() -> void:
	switches.clear()
	switches.resize(MAX_SWITCHES)
	switches.fill(false)
	variables.clear()
	variables.resize(MAX_VARIABLES)
	variables.fill(0)


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
