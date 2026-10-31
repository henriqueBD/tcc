extends ShadowBenchmark

const OBJ_1: PackedScene = preload("uid://ck1jq44eyptk") # 12 x 12
const OBJ_2: PackedScene = preload("uid://dl72x54g36b23") # 16 x 14
const OBJ_3: PackedScene = preload("uid://xucopepmltut") # 19 x 16
const LIGHT_TEXTURE: Texture2D = preload("uid://c7lb1bihvx3fv")

@export var num_objects: int = 400
@export var num_lights: bool #false = 1 true = 16
@export var scatter_area: Rect2 = Rect2(-184.0, -160.0, 384.0, 304.0)

@export_group("Lights")
## Radians per second.
@export var orbit_speed: float = 1.0
## Orbit radius as a fraction of each light's grid cell.
@export_range(0.0, 0.5) var orbit_radius_ratio: float = 0.35
## Same for 1 and 16 lights, so the two configurations stay comparable.

var _light_nodes: Array[ShadowLight] = []
var _orbit_centers: PackedVector2Array = PackedVector2Array()
var _orbit_phases: PackedFloat32Array = PackedFloat32Array()
var _orbit_radius: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	super()
	var objects_node: Node = get_node("%Objects")
	_scatter_on_grid(objects_node)

	var single: Node2D = $"1Light"
	var multi: Node2D = $"16Light"
	if num_lights:
		_spawn_lights(multi, 16)
		single.queue_free()
	else:
		_spawn_lights(single, 1)
		multi.queue_free()
	_place_lights()


func _physics_process(delta: float) -> void:
	_time += delta
	_place_lights()


# ---------------- Objects ----------------

func _scatter_on_grid(parent: Node) -> void:
	if num_objects <= 0 or not scatter_area.has_area():
		return
	var scenes: Array[PackedScene] = [OBJ_1, OBJ_2, OBJ_3]
	# Pick columns so cells come out roughly square for the area's aspect ratio.
	var aspect: float = scatter_area.size.x / scatter_area.size.y
	var cols: int = maxi(1, ceili(sqrt(num_objects * aspect)))
	var rows: int = ceili(float(num_objects) / cols)
	var cell: Vector2 = scatter_area.size / Vector2(cols, rows)

	for i: int in num_objects:
		var col: int = i % cols
		var row: int = i / cols
		# (col + row) mixes the sizes diagonally instead of in stripes.
		var stone: Node2D = scenes[(col + row) % scenes.size()].instantiate() as Node2D
		stone.position = scatter_area.position + cell * Vector2(col + 0.5, row + 0.5)
		parent.add_child(stone)


# ---------------- Lights ----------------

## Lights sit on an n x n grid over the area; each one orbits the center of its cell.
func _spawn_lights(container: Node2D, count: int) -> void:
	var side: int = ceili(sqrt(float(count)))
	var cell: Vector2 = scatter_area.size / float(side)
	_orbit_radius = minf(cell.x, cell.y) * orbit_radius_ratio

	for i: int in count:
		var light: ShadowLight = ShadowLight.new()
		light.name = "ShadowLight%d" % i
		light.texture = LIGHT_TEXTURE
		light.color = Color.DARK_ORANGE
		container.add_child(light)
		_light_nodes.append(light)
		_orbit_centers.append(scatter_area.position + cell * Vector2(i % side + 0.5, i / side + 0.5))
		_orbit_phases.append(TAU * i / count) # Spread out so they don't move in lockstep.


func _place_lights() -> void:
	for i: int in _light_nodes.size():
		var angle: float = _time * orbit_speed + _orbit_phases[i]
		_light_nodes[i].position = _orbit_centers[i] + Vector2.from_angle(angle) * _orbit_radius
