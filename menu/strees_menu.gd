extends Menu

const DEMO_STRESS = preload("uid://kj5sb3e1ttry")

@onready var _obj_num_label: Label = %ObjNum

@onready var _1_luz_btn: Button = %"1Luz"
@onready var _16_luz_btn: Button = %"16Luz"

var _obj_num: int
var _16_light: bool

func _ready() -> void:
	%AddObj.pressed.connect(_increment_obj.bind(10))
	%SubObj.pressed.connect(_increment_obj.bind(-10))
	%Iniciar.pressed.connect(_iniciar_press)
	
	_1_luz_btn.pressed.connect(_1_luz_press)
	_16_luz_btn.pressed.connect(_16_luz_press)

func _increment_obj(increment: int) -> void:
	_obj_num = clamp(_obj_num + increment, 0, 600)
	_obj_num_label.text = str(_obj_num)

func _1_luz_press() -> void:
	_16_light = false
	_16_luz_btn.button_pressed = false

func _16_luz_press() -> void:
	_16_light = true
	_1_luz_btn.button_pressed = false

func _iniciar_press() -> void:
	var demo_stress: StressTestBenchmark = DEMO_STRESS.instantiate()
	demo_stress.num_lights = _16_light
	demo_stress.num_objects = _obj_num
	level_selected.emit(demo_stress, false, true)
