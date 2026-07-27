class_name ClearTracker
extends RefCounted

## Tracks how many things that can actually hurt the warrior are still alive in a run,
## and fires once when the last one dies.
##
## The banner this drives asserts "nothing here can hurt you any more", so the count is
## keyed on each creature's own `is_hostile()` — part of the duck-typed group-"enemies"
## contract — rather than on which spawn function produced it. That is what lets the
## per-ring roster add creatures without touching the clear logic.
##
## Peaceful ring life is deliberately NOT counted. The Pale Herd grazes, panics and
## flees; it has no aggressive state by design. Counting it would mean a ring is only
## "clear" once you have slaughtered a herd, which cuts straight against the game's
## avoidance-first design.
##
## `cleared` fires only on a decrement that REACHES zero — never on construction, never
## on a ring that spawned no hostiles at all, and never twice.

signal cleared

var _alive: int = 0
var _fired: bool = false


## Register anything from group "enemies". Non-hostile registrants are ignored
## outright: they never enter the count, so their death cannot move it either.
## Returns true if the node joined the count.
func register(node: Node) -> bool:
	if not _is_hostile(node):
		return false
	_alive += 1
	node.connect(&"enemy_died", _on_hostile_died)
	return true


func hostiles_alive() -> int:
	return _alive


# Duck-typed like the rest of the "enemies" contract. Anything that forgets to answer
# counts as hostile, so the banner can never claim a safety it cannot prove.
func _is_hostile(node: Node) -> bool:
	if node.has_method("is_hostile"):
		return bool(node.is_hostile())
	return true


func _on_hostile_died() -> void:
	if _alive <= 0:
		return
	_alive -= 1
	if _alive == 0 and not _fired:
		_fired = true
		cleared.emit()
