class_name TimeManager
extends CanvasModulate

@export_group("Gradient")
## Gradient for the CanvasModulate. 0.0 is midnight, 0.5 is noon, 1.0 is midnight.
## Tip: Set 0.0 and 1.0 to dark blue (night) and 0.5 to pure white (day).
@export var gradient: Gradient

@export_group("Clock")
## Real-time seconds for one full in-game day.
@export var day_length_seconds: float = 600.0
@export_range(0.0, 24.0) var start_hour: float = 8.0
@export var time_scale: float = 1.0
@export var paused: bool = false

@export_group("Sun")
## Master switch for sun shadows (turn off indoors / in caves).
@export var sun_enabled: bool = true
@export_range(0.0, 24.0) var sunrise_hour: float = 6.0
@export_range(0.0, 24.0) var sunset_hour: float = 18.0
@export_range(0.0, 1.0) var max_sun_strength: float = 1.0
## Shadow length in sprite heights at noon.
@export var noon_shadow_length: float = 0.4
## Shadow length in sprite heights right after sunrise / before sunset.
@export var horizon_shadow_length: float = 2.0
## Sun elevation (0..1) over which shadows fade in after sunrise and out before sunset.
@export_range(0.01, 1.0) var horizon_fade: float = 0.25
## Rotates the sun's path. 0 = shadows sweep west → north → east.
@export_range(-180.0, 180.0) var sun_path_rotation_degrees: float = 0.0
## Sprite shadows only update after the sun turns this much. Lower is smoother,
## higher is cheaper. 0 updates whenever anything changes.
@export_range(0.0, 5.0) var sun_update_degrees: float = 0.25

var hour: float = 0.0

## Smallest change in shadow length (sprite heights) or strength that updates shadows.
const SUN_LENGTH_STEP: float = 0.01
const SUN_STRENGTH_STEP: float = 0.005

# Read by SkewShadowSprite when it updates. Only change when the change is visible.
static var current_manager: TimeManager
static var sun_direction: Vector2 = Vector2.UP
static var sun_length: float = 0.0
static var sun_strength: float = 0.0

var _last_whole_hour: int = -1
var _was_day: bool = false
## The statics outlive this node, so the first update always publishes.
var _sun_force_publish: bool = true

func _enter_tree() -> void:
	current_manager = self

func _ready() -> void:
	hour = fposmod(start_hour, 24.0)
	_last_whole_hour = int(hour)
	_was_day = is_day()
	_update_sun()

func _process(delta: float) -> void:
	if not paused and day_length_seconds > 0.0:
		_advance(delta * time_scale * 24.0 / day_length_seconds)
	_update_sun()
	
	if gradient:
		color = gradient.sample(get_day_fraction())


# ---------------- Public API ----------------

func set_time(new_hour: float) -> void:
	hour = fposmod(new_hour, 24.0)
	_check_transitions()
	_update_sun()

func offset_hour(offset: int) -> void:
	set_time(hour + offset)

func is_day() -> bool:
	return hour >= sunrise_hour and hour < sunset_hour


func is_night() -> bool:
	return not is_day()


## 0..1 across the whole day (0 and 1 = midnight, 0.5 = noon).
func get_day_fraction() -> float:
	return hour / 24.0


# ---------------- Internals ----------------

func _advance(hours: float) -> void:
	hour += hours
	while hour >= 24.0:
		hour -= 24.0
	while hour < 0.0: # Negative time_scale rewinds.
		hour += 24.0
	_check_transitions()


func _check_transitions() -> void:
	var whole: int = int(hour)
	if whole != _last_whole_hour:
		_last_whole_hour = whole

	var day_now: bool = is_day()
	if day_now != _was_day:
		_was_day = day_now


func _update_sun() -> void:
	var direction: Vector2 = sun_direction
	var length: float = sun_length
	var strength: float = 0.0

	var progress: float = inverse_lerp(sunrise_hour, sunset_hour, hour)
	if sun_enabled and progress > 0.0 and progress < 1.0:
		# 0 at the horizon, 1 at noon.
		var elevation: float = sin(progress * PI)
		# Sun rises east, so shadows start pointing west (PI), pass north (3PI/2), end east (TAU).
		direction = Vector2.from_angle(lerpf(PI, TAU, progress) + deg_to_rad(sun_path_rotation_degrees))
		length = lerpf(horizon_shadow_length, noon_shadow_length, elevation)
		strength = max_sun_strength * smoothstep(0.0, horizon_fade, elevation)

	if not _sun_changed_enough(direction, length, strength):
		return

	sun_direction = direction
	sun_length = length
	sun_strength = strength
	# Terrain (shadow.gdshader) and sprite shadows step together, so they always match.
	RenderingServer.global_shader_parameter_set("sun_direction", direction)
	RenderingServer.global_shader_parameter_set("sun_strength", strength)
	SkewShadowSprite.mark_all_sun_dirty()


func _sun_changed_enough(direction: Vector2, length: float, strength: float) -> bool:
	if _sun_force_publish:
		_sun_force_publish = false
		return true
	if (strength > 0.0) != (sun_strength > 0.0):
		return true # Sunrise, sunset, or sun switched on/off.
	if strength == 0.0:
		return false # Night: nothing to show.
	return absf(strength - sun_strength) > SUN_STRENGTH_STEP \
		or absf(length - sun_length) > SUN_LENGTH_STEP \
		or absf(direction.angle_to(sun_direction)) > deg_to_rad(sun_update_degrees)
