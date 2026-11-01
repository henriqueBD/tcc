class_name SkewShadowSprite
extends Sprite2D
## Sprite that casts fake shadows from every nearby ShadowLight and from the sun.
##
## Shadows are event-driven: nothing runs while the scene is still. A caster
## recomputes at the end of the frame only when something it depends on changes:
## - it moves, is shown/hidden, or its texture/region/offset changes (automatic);
## - a ShadowLight whose range covers it moves or changes (ShadowLight notifies it);
## - the sun turns far enough (TimeManager notifies it);
## - one of its exported settings changes (setters below).
## Call mark_dirty() after changing anything else that affects the shadow,
## such as flip_h, from code.

enum ShadowStyle {
	ROTATE,
	SKEW,
}

const LIGHT_ONLY: Material = preload("uid://ddwegu1bf4g7c")
const SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.4)
const SHADOW_Z_OFFSET: int = -1
const MIN_STRENGTH: float = 0.01
const SHORT_SHADOW_FADE: float = 0.3

class ShadowSource:
	var direction: Vector2
	var length: float
	var strength: float

## Every caster in the tree. ShadowLight scans it to find the casters it reaches.
static var registry: Array[SkewShadowSprite] = []

@export_group("Sources")
@export var receive_light_shadows: bool = true:
	set(value):
		receive_light_shadows = value
		mark_lights_dirty()
@export var receive_sun: bool = true:
	set(value):
		receive_sun = value
		mark_sun_dirty()
@export_range(0, 8) var max_shadows: int = 3:
	set(value):
		max_shadows = value
		mark_lights_dirty()

@export_group("Visibility")
@export var shadow_only: bool = false:
	set(value):
		if shadow_only == value:
			return
		shadow_only = value
		if not is_node_ready():
			return # _ready() applies it.
		if value:
			self_modulate.a = 0.0
		else:
			self_modulate.a = 1.0

@export_group("Shape")
@export var style: ShadowStyle = ShadowStyle.ROTATE:
	set(value):
		style = value
		mark_dirty()
@export_range(0.0, 1.0) var perspective_squash: float = 0.71:
	set(value):
		perspective_squash = value
		mark_dirty()
@export var max_length: float = 2.5:
	set(value):
		max_length = value
		mark_dirty()
@export var foot_inset: float = 0.0:
	set(value):
		foot_inset = value
		_on_shape_changed()

var _light_shadows: Array[Sprite2D] = []
var _sun_shadow: Sprite2D
var _top: Array[ShadowSource] = []
var _top_count: int = 0

var _active: bool = true
var _lights_dirty: bool = false
var _sun_dirty: bool = false
var _flush_queued: bool = false
## Cached so lights can test range without touching the scene tree.
var _feet: Vector2 = Vector2.ZERO
var _scale_abs: Vector2 = Vector2.ONE


func _enter_tree() -> void:
	registry.append(self)
	set_notify_transform(true)
	_update_feet()
	mark_dirty()


func _exit_tree() -> void:
	registry.erase(self)


func _ready() -> void:
	if shadow_only:
		self_modulate.a = 0.0

	_resize_source_pool()
	texture_changed.connect(refresh_shadow_visuals)
	item_rect_changed.connect(_on_shape_changed)
	frame_changed.connect(_on_frame_changed)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			_update_feet()
			mark_dirty()
		NOTIFICATION_VISIBILITY_CHANGED:
			mark_dirty()


# ---------------- Public API ----------------

func set_shadows_active(active: bool) -> void:
	_active = active
	mark_dirty()


func refresh_shadow_visuals() -> void:
	for shadow: Sprite2D in _light_shadows:
		_sync_visuals(shadow)
	if _sun_shadow:
		_sync_visuals(_sun_shadow)


## Recomputes every shadow of this sprite once, at the end of the frame.
func mark_dirty() -> void:
	_lights_dirty = true
	_sun_dirty = true
	_queue_flush()


func mark_lights_dirty() -> void:
	_lights_dirty = true
	_queue_flush()


func mark_sun_dirty() -> void:
	_sun_dirty = true
	_queue_flush()


## Called by ShadowLight when a light covering this area moved or changed.
static func mark_lights_dirty_in_range(center: Vector2, radius: float) -> void:
	var radius_sq: float = radius * radius
	for caster: SkewShadowSprite in registry:
		if caster.receive_light_shadows and caster._feet.distance_squared_to(center) < radius_sq:
			caster.mark_lights_dirty()


## Called by TimeManager when the sun has changed enough to be visible.
static func mark_all_sun_dirty() -> void:
	for caster: SkewShadowSprite in registry:
		if caster.receive_sun:
			caster.mark_sun_dirty()


# ------------------------------------------------------------------------------

func _queue_flush() -> void:
	if _flush_queued or not is_inside_tree():
		return # _enter_tree() marks everything dirty anyway.
	_flush_queued = true
	_flush.call_deferred()


## Runs after every _process of the frame, so all changes are batched into one update.
func _flush() -> void:
	_flush_queued = false
	if not is_inside_tree():
		return

	var drawing: bool = _active and texture != null and is_visible_in_tree()
	if _lights_dirty:
		_lights_dirty = false
		_update_light_shadows(drawing)
	if _sun_dirty:
		_sun_dirty = false
		_update_sun_shadow(drawing)


func _update_light_shadows(drawing: bool) -> void:
	_top_count = 0
	if drawing and receive_light_shadows and max_shadows > 0 and not ShadowLight.registry.is_empty():
		if _top.size() != max_shadows:
			_resize_source_pool()
		_gather_light_sources(_feet)
		for i: int in _top_count:
			var source: ShadowSource = _top[i]
			_apply_shadow(_get_light_shadow(i), source.direction, source.length, source.strength)

	for i: int in range(_top_count, _light_shadows.size()):
		_light_shadows[i].hide()


func _update_sun_shadow(drawing: bool) -> void:
	var sun_strength: float = TimeManager.sun_strength
	if drawing and receive_sun and sun_strength > MIN_STRENGTH:
		if _sun_shadow == null:
			_sun_shadow = _create_shadow(null)
		_apply_shadow(_sun_shadow, TimeManager.sun_direction,
			minf(TimeManager.sun_length, max_length), minf(sun_strength, 1.0))
	elif _sun_shadow:
		_sun_shadow.hide()


func _apply_shadow(shadow: Sprite2D, dir: Vector2, length: float, strength: float) -> void:
	shadow.global_transform = _build_transform(_feet, dir, length, _scale_abs)
	shadow.modulate.a = SHADOW_COLOR.a * strength
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


func _update_feet() -> void:
	_feet = to_global(_get_feet_local())
	_scale_abs = global_scale.abs()


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
	shadow.z_index = SHADOW_Z_OFFSET
	shadow.material = shadow_material
	shadow.light_mask = ShadowLight.LIGHT_MASK
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


## Texture, region, offset or frame grid changed: the feet and shadow offset move.
func _on_shape_changed() -> void:
	if not is_inside_tree():
		return
	refresh_shadow_visuals()
	_update_feet()
	mark_dirty()


func _on_frame_changed() -> void:
	for shadow: Sprite2D in _light_shadows:
		shadow.frame = frame
	if _sun_shadow:
		_sun_shadow.frame = frame
