class_name Menu
extends Node

signal level_selected(scene: Node)
signal menu_changed(menu: Menu)

const DEMO = preload("uid://dn2kia7y6hvw")
const DEMO_LIMITATIONS = preload("uid://bbcg04k24odhk")

func _ready() -> void:
	%Demo.pressed.connect(_change_to.bind(DEMO))
	%Limitations.pressed.connect(_change_to.bind(DEMO_LIMITATIONS))
	%Stress.pressed.connect(_stess_test_menu)

func _change_to(scene: PackedScene) -> void:
	level_selected.emit(scene.instantiate())

func _stess_test_menu() -> void:
	menu_changed.emit()
