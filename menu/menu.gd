class_name Menu
extends Node

signal level_selected(scene: Node, spawn_player: bool, run_benchmark: bool)
signal menu_changed(menu: Menu)

const DEMO = preload("uid://dn2kia7y6hvw")
const DEMO_LIMITATIONS = preload("uid://bbcg04k24odhk")

var _spawn_player: bool = true
var _run_benchmark: bool = true

func _ready() -> void:
	_setup_toggles()
	%Demo.pressed.connect(_change_to.bind(DEMO))
	%Limitations.pressed.connect(_change_to.bind(DEMO_LIMITATIONS))
	%Stress.pressed.connect(_stess_test_menu)

func _setup_toggles() -> void:
	%SpanwPlayer.toggled.connect(_toggle_spawn_player)
	%Benchmark.toggled.connect(_toggle_run_benchmark)

func _change_to(scene: PackedScene) -> void:
	level_selected.emit(scene.instantiate(), _spawn_player, _run_benchmark)

func _stess_test_menu() -> void:
	menu_changed.emit()

func _toggle_spawn_player(val: bool) -> void:
	_spawn_player = val

func _toggle_run_benchmark(val: bool) -> void:
	_run_benchmark = val
