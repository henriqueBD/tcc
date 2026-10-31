class_name ShadowLight
extends PointLight2D
## Registers this light so every SkewShadowSprite in range casts a shadow from it.
##
## Each frame the light compares its state (position, radius, energy, on/off) with
## what casters last saw. Only when it differs are the casters inside the old and
## new radius told to recompute, so a still light costs a few comparisons.

const LIGHT_MASK: int = 2
## Movement below this (pixels) is ignored, so sub-pixel jitter doesn't wake casters.
const MOVE_EPSILON: float = 0.01

## Every ShadowLight currently in the tree. Read-only from outside.
static var registry: Array[ShadowLight] = []

@export var cast_shadows: bool = true:
	set(value):
		cast_shadows = value
		_settings_changed = true
## Light height in pixels. A light this high, this far from a sprite,
## casts a shadow equal to the sprite's height (45°).
@export_range(1.0, 512.0) var shadow_height: float = 32.0:
	set(value):
		shadow_height = value
		_settings_changed = true
@export_range(0.0, 1.0) var shadow_strength: float = 1.0:
	set(value):
		shadow_strength = value
		_settings_changed = true
## Fraction of the radius where shadows start fading out.
@export_range(0.0, 0.95) var fade_start: float = 0.5:
	set(value):
		fade_start = value
		_settings_changed = true

var _radius: float = 0.0

# What casters saw the last time they were notified.
var _last_casting: bool = false
var _last_position: Vector2 = Vector2.ZERO
var _last_radius: float = 0.0
var _last_energy: float = 0.0
var _settings_changed: bool = false


func _enter_tree() -> void:
	if not registry.has(self):
		registry.append(self)
	range_item_cull_mask = LIGHT_MASK | 1
	_radius = _compute_radius()
	_last_casting = false # First _process notifies the casters in range.


func _ready() -> void:
	# Check after gameplay scripts have moved things this frame.
	process_priority = 1000


func _exit_tree() -> void:
	registry.erase(self)
	if _last_casting:
		SkewShadowSprite.mark_lights_dirty_in_range(_last_position, _last_radius)
		_last_casting = false


func _process(_delta: float) -> void:
	var casting: bool = is_casting()
	if not casting and not _last_casting:
		_settings_changed = false
		return # Off before and after: nothing visible changed.

	_radius = _compute_radius()
	var position_now: Vector2 = global_position
	var changed: bool = _settings_changed or casting != _last_casting \
		or position_now.distance_squared_to(_last_position) > MOVE_EPSILON * MOVE_EPSILON \
		or _radius != _last_radius or energy != _last_energy
	if not changed:
		return

	# Casters that had a shadow from the old state, and casters that get one now.
	if _last_casting:
		SkewShadowSprite.mark_lights_dirty_in_range(_last_position, _last_radius)
	if casting:
		SkewShadowSprite.mark_lights_dirty_in_range(position_now, _radius)

	_last_casting = casting
	_last_position = position_now
	_last_radius = _radius
	_last_energy = energy
	_settings_changed = false


func is_casting() -> bool:
	return cast_shadows and enabled and energy > 0.0 and is_visible_in_tree()


func toggle_enable(enable: bool) -> void:
	cast_shadows = enable
	enabled = enable


func get_shadow_radius() -> float:
	return _radius


## Shadow opacity (0..1) for a caster at this distance. Assumes distance < radius.
func get_strength_at(distance: float, radius: float) -> float:
	var falloff: float = 1.0 - smoothstep(radius * fade_start, radius, distance)
	return falloff * shadow_strength * minf(energy, 1.0)


func _compute_radius() -> float:
	if texture == null:
		return 0.0
	return texture.get_width() * 0.5 * texture_scale * absf(global_scale.x)
