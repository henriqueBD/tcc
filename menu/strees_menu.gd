extends Node

@onready var _obj_num_label: Label = %ObjNum

@onready var _1_luz: Button = %"1Luz"
@onready var _16_luz: Button = %"16Luz"

var _obj_num: int
var _16_light: bool

func _ready() -> void:
	%AddObj.pressed.connect(_increment_obj.bind(10))
	%SubObj.pressed.connect(_increment_obj.bind(-10))
	%Iniciar.pressed.connect(_iniciar_press)

func _increment_obj(increment: int) -> void:
	_obj_num = clamp(_obj_num + increment, 0, 200)
	_obj_num_label.text = str(_obj_num)
	
	_1_luz.pressed.connect(_1_luz_press)

func _1_luz_press() -> void:
	_16_light = false
	_16_luz.button_pressed = false

func _16_luz_press() -> void:
	_16_light = true
	_1_luz.button_pressed = false

func _iniciar_press() -> void:
	print("Yipee")
