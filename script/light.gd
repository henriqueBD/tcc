class_name ShadowLight
extends PointLight2D
## Registers this light so every SkewShadowSprite in range casts a shadow from it.

const LIGHT_MASK: int = 2

## Every ShadowLight currently in the tree. Read-only from outside.
static var registry: Array[ShadowLight] = []

@export var cast_shadows: bool = true
## Light height in pixels. A light this high, this far from a sprite,
## casts a shadow equal to the sprite's height (45°).
@export_range(1.0, 512.0) var shadow_height: float = 32.0
## Shadow range in pixels. 0 = derive from the light texture's size.
@export_range(0.0, 1.0) var shadow_strength: float = 1.0
## Fraction of the radius where shadows start fading out.
@export_range(0.0, 0.95) var fade_start: float = 0.5

var _radius: float = 0.0

func _enter_tree() -> void:
	if not registry.has(self):
		registry.append(self)
	range_item_cull_mask = LIGHT_MASK | 1
	
	if texture:
		_radius = texture.get_width() * 0.5 * texture_scale * absf(global_scale.x)

func _exit_tree() -> void:
	registry.erase(self)

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
