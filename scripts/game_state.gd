extends Node

const MAX_GRIEF := 10
var run_count: int = 0
var grief_reserve: int = MAX_GRIEF
var extractions: int = 0
var clock_ticks: int = 0

func starting_coherence() -> int:
	if grief_reserve >= 7:
		return 10
	elif grief_reserve >= 4:
		return 7
	return 4

func advance_clock() -> void:
	clock_ticks = mini(clock_ticks + 1, 10)

func is_last_song() -> bool:
	return clock_ticks >= 10
