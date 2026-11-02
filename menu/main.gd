extends Node

const STRESS_TEST_MENU = preload("uid://cnd0ni8ho5wyv")

@onready var menu: Menu = %Menu
@onready var camera_2d: Camera2D = %Camera2D

func _ready() -> void:
	menu.level_selected.connect(_start, CONNECT_ONE_SHOT)
	menu.menu_changed.connect(_change_menu, CONNECT_ONE_SHOT)

func _start(level: Node, spawn_player: bool, run_benchmark: bool) -> void:
	menu.queue_free()
	
	(level as ShadowBenchmark).run_on_start = run_benchmark
	%Level.add_child(level)
	
	var player: CharacterBody2D = %Player
	
	if spawn_player:
		player.show()
		player.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		player.queue_free()
	
	$TimeManager.process_mode = Node.PROCESS_MODE_INHERIT

func _change_menu() -> void:
	menu.queue_free()
	menu = STRESS_TEST_MENU.instantiate()
	menu.level_selected.connect(_start)
	add_child(menu)
