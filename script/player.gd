extends CharacterBody2D

@export var speed: float = 200.0
@export var friction: float = 1200.0
@export var acceleration: float = 2500.0
@export var time_manager: TimeManager
@export var level: Node

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shadow_light: ShadowLight = $ShadowLight

var _shadows_active: bool = true

func _physics_process(delta: float) -> void:
	
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()
		return
	
	# Reads directional inputs (WASD / Arrow Keys by default)
	var input_direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	if input_direction != Vector2.ZERO:
		if input_direction.x != 0.0:
			_sprite.frame = 2
		_sprite.flip_h = input_direction.x > 0.0
		
		if input_direction.y > 0.0:
			_sprite.frame = 0
		if input_direction.y < 0.0:
			_sprite.frame = 1
	
	if input_direction != Vector2.ZERO:
		# Smoothly accelerate toward max speed
		velocity = velocity.move_toward(input_direction * speed, acceleration * delta)
	else:
		# Smoothly decelerate to a stop when no keys are pressed
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	
	if Input.is_action_just_pressed("ui_accept"):
		_shadow_light.toggle_enable(_shadow_light.cast_shadows)
	
	if Input.is_action_just_pressed("ui_focus_next"):
		time_manager.paused = not time_manager.paused
	
	if Input.is_action_just_pressed("avancar_hora"):
		time_manager.offset_hour(1)
	elif Input.is_action_just_pressed("retroceder_hora"):
		time_manager.offset_hour(-1)
	
	if Input.is_action_just_pressed("toggle_sombra"):
		_shadows_active = not _shadows_active
		for sprite_shadow: SkewShadowSprite in get_tree().get_nodes_in_group("Shadows"):
			sprite_shadow.toggle_disable(_shadows_active)
		(level.get_child(0).get_node("%Occluders") as Node2D).visible = _shadows_active
	
	move_and_slide()
