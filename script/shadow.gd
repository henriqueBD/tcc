class_name SkewShadowSprite
extends Sprite2D

enum ShadowStyle {
	ROTATE,
	SKEW,
}

const LIGHT_ONLY: Material = preload("uid://ddwegu1bf4g7c")
const SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.4)
const SHADOW_Z_INDEX: int = -1
const MIN_STRENGTH: float = 0.01
const SHORT_SHADOW_FADE: float = 0.3

class ShadowSource:
	var direction: Vector2
	var length: float
	var strength: float # 0..1 opacity multiplier.

@export_group("Sources")
@export var receive_light_shadows: bool = true
@export var receive_sun: bool = true
@export_range(0, 8) var max_shadows: int = 3

@export_group("Visibility")
@export var shadow_only: bool = false:
	set(value):
		if shadow_only == value:
			return
		shadow_only = value
		if not is_node_ready():
			return
		if value:
			self_modulate.a = 0.0
		else:
			self_modulate.a = 1.0

@export_group("Shape")
@export var style: ShadowStyle = ShadowStyle.ROTATE
@export_range(0.0, 1.0) var perspective_squash: float = 0.64
## Max shadow length as a multiple of sprite height.
@export var max_length: float = 2.5
## Transparent pixels between the bottom of the frame and the sprite's feet.
@export var foot_inset: float = 0.0

var _light_shadows: Array[Sprite2D] = []
var _sun_shadow: Sprite2D
## Strongest light sources this frame, sorted descending. Objects are recycled, never reallocated.
var _top: Array[ShadowSource] = []
var _top_count: int = 0


func _ready() -> void:
	add_to_group("Shadows")
	
	if shadow_only:
		self_modulate.a = 0.0

	_resize_source_pool()
	texture_changed.connect(refresh_shadow_visuals)
	frame_changed.connect(_on_frame_changed)

func _process(_delta: float) -> void:
	_update_shadows()


## Call this after changing hframes/vframes/region at runtime.
func refresh_shadow_visuals() -> void:
	for shadow: Sprite2D in _light_shadows:
		_sync_visuals(shadow)
	if _sun_shadow:
		_sync_visuals(_sun_shadow)


func toggle_disable(val: bool) -> void:
	set_process(val)
	#val = not val
	if _sun_shadow:
		_sun_shadow.visible = val
	for shadow: Sprite2D in _light_shadows:
		shadow.visible = val

# ------------------------------------------------------------------------------

func _update_shadows() -> void:
	_top_count = 0

	var drawing: bool = texture != null and is_visible_in_tree()
	var sun_strength: float = TimeManager.sun_strength
	var show_sun: bool = drawing and receive_sun and sun_strength > MIN_STRENGTH
	var check_lights: bool = drawing and receive_light_shadows and max_shadows > 0 \
		and not ShadowLight.registry.is_empty()

	if show_sun or check_lights:
		var feet: Vector2 = to_global(_get_feet_local())
		var scale_abs: Vector2 = global_scale.abs()

		if check_lights:
			if _top.size() != max_shadows:
				_resize_source_pool()
			_gather_light_sources(feet)
			for i: int in _top_count:
				var source: ShadowSource = _top[i]
				_apply_shadow(_get_light_shadow(i), feet, source.direction, source.length, source.strength, scale_abs)

		if show_sun:
			if _sun_shadow == null:
				_sun_shadow = _create_shadow(null)
			_apply_shadow(_sun_shadow, feet, TimeManager.sun_direction,
				minf(TimeManager.sun_length, max_length), minf(sun_strength, 1.0), scale_abs)

	for i: int in range(_top_count, _light_shadows.size()):
		_light_shadows[i].hide()
	if _sun_shadow and not show_sun:
		_sun_shadow.hide()


func _apply_shadow(shadow: Sprite2D, feet: Vector2, dir: Vector2, length: float,
		strength: float, scale_abs: Vector2) -> void:
	shadow.global_transform = _build_transform(feet, dir, length, scale_abs)
	shadow.modulate.a = SHADOW_COLOR.a * strength
	shadow.light_mask = ShadowLight.LIGHT_MASK
	if shadow.flip_h != flip_h:
		shadow.flip_h = flip_h
	shadow.show()


func _gather_light_sources(feet: Vector2) -> void:
	for light: ShadowLight in ShadowLight.registry:
		if not light.is_casting():
			continue

		var to_feet: Vector2 = feet - light.global_position
		var dist_sq: float = to_feet.length_squared()
		var radius: float = light.get_shadow_radius()
		if dist_sq >= radius * radius or dist_sq < 0.0001:
			continue

		var dist: float = sqrt(dist_sq)
		var length: float = minf(dist / light.shadow_height, max_length)
		var strength: float = light.get_strength_at(dist, radius) * smoothstep(0.0, SHORT_SHADOW_FADE, length)
		if strength > MIN_STRENGTH:
			_push_source(to_feet / dist, length, strength)

## Inserts into the sorted top-N list, recycling the weakest slot.
func _push_source(direction: Vector2, length: float, strength: float) -> void:
	var index: int = _top_count
	while index > 0 and _top[index - 1].strength < strength:
		index -= 1
	if index >= max_shadows:
		return

	var last: int = mini(_top_count, max_shadows - 1)
	var slot: ShadowSource = _top[last]
	for j: int in range(last, index, -1):
		_top[j] = _top[j - 1]
	_top[index] = slot

	slot.direction = direction
	slot.length = length
	slot.strength = strength
	_top_count = mini(_top_count + 1, max_shadows)


func _resize_source_pool() -> void:
	_top.resize(max_shadows)
	for i: int in max_shadows:
		if _top[i] == null:
			_top[i] = ShadowSource.new()
	_top_count = 0


func _build_transform(feet: Vector2, dir: Vector2, length: float, scale_abs: Vector2) -> Transform2D:
	# Shadow sprite extends toward local -Y, so -y_axis is where its "head" lands.
	var y_axis: Vector2 = -dir * (length * scale_abs.y)
	var x_axis: Vector2
	if style == ShadowStyle.ROTATE:
		x_axis = Vector2(-dir.y, dir.x) * scale_abs.x
	else:
		x_axis = Vector2(scale_abs.x, 0.0)
	# Project onto the tilted ground plane.
	x_axis.y *= perspective_squash
	y_axis.y *= perspective_squash
	return Transform2D(x_axis, y_axis, feet)


func _get_feet_local() -> Vector2:
	var rect: Rect2 = get_rect() # Already accounts for centered, offset, frames and region.
	return Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y - foot_inset)


func _get_light_shadow(index: int) -> Sprite2D:
	while _light_shadows.size() <= index:
		_light_shadows.append(_create_shadow(LIGHT_ONLY))
	return _light_shadows[index]


func _create_shadow(shadow_material: Material) -> Sprite2D:
	var shadow: Sprite2D = Sprite2D.new()
	shadow.centered = false
	shadow.show_behind_parent = true
	shadow.z_as_relative = true
	shadow.z_index = SHADOW_Z_INDEX
	shadow.z_as_relative = false
	shadow.material = shadow_material
	shadow.modulate = SHADOW_COLOR
	if not shadow_material:
		shadow.modulate.a = 0.1
	_sync_visuals(shadow)
	# Internal children don't show up in get_children() and are never saved.
	add_child(shadow, false, Node.INTERNAL_MODE_FRONT)
	return shadow


func _sync_visuals(shadow: Sprite2D) -> void:
	shadow.texture = texture
	shadow.region_enabled = region_enabled
	shadow.region_rect = region_rect
	shadow.hframes = hframes
	shadow.vframes = vframes
	shadow.frame = frame
	shadow.flip_h = flip_h
	var size: Vector2 = get_rect().size
	shadow.offset = Vector2(-size.x * 0.5, -(size.y - foot_inset))


func _on_frame_changed() -> void:
	for shadow: Sprite2D in _light_shadows:
		shadow.frame = frame
	if _sun_shadow:
		_sun_shadow.frame = frame
