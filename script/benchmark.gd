class_name ShadowBenchmark
extends Node
## Measures the cost of each part of the lighting system in the current scene.
##
## Put this node at the top of the scene you want to measure and run the game.
## It switches between configurations, lets the day/night cycle run over the same
## stretch of in-game time in every measurement, and prints the results to the
## Output panel (or the terminal, in an exported build).
##
## Setup:
## - Nodes that draw terrain shadows with shadow.gdshader -> group "bench_sdf".
## - Extra LightOccluder2Ds used only for the native baseline -> group "bench_native".
##
## Runs automatically when `run_on_start` is on, or when the game is launched
## with `-- --benchmark`.

const BENCHMARK_UI = preload("uid://bc14jfg3yuu8t")

const GROUP_NATIVE: StringName = &"bench_native"
const output_dir: String = "user://benchmarks"


class BenchConfig:
	var name: String
	var lighting: bool ## Light2Ds, sun and CanvasModulate.
	var sun: bool      ## Sun shadows on SkewShadowSprites.
	var lights: bool   ## ShadowLight shadows on SkewShadowSprites.
	var sdf: bool      ## Terrain shadows (nodes in GROUP_SDF).
	var native: bool   ## Godot's own LightOccluder2D shadows.

	func _init(p_name: String, p_lighting: bool, p_sun: bool, p_lights: bool,
			p_sdf: bool, p_native: bool) -> void:
		name = p_name
		lighting = p_lighting
		sun = p_sun
		lights = p_lights
		sdf = p_sdf
		native = p_native


## Results of one measurement (one configuration, one repetition).
class Run:
	var frame_avg: float = 0.0
	var frame_p99: float = 0.0
	var cpu_avg: float = 0.0
	var gpu_avg: float = 0.0


@export var run_on_start: bool = false
@export var quit_on_end: bool = false
## Found automatically if left empty.

@export_group("Protocol")
## Seconds to wait after switching configuration (shader compilation, caches).
@export var warmup_seconds: float = 3.0
@export var sample_seconds: float = 15.0
## Each repetition runs every configuration once, interleaved, to spread out thermal drift.
@export_range(1, 10) var repetitions: int = 5
## Adds a baseline using Godot's native LightOccluder2D shadows.
@export var include_native: bool = true

@export_group("Day cycle")
## In-game hour at the start of every measurement.
@export_range(0.0, 24.0) var start_hour: float = 9.0
## In-game hour reached at the end of every measurement. The clock runs
## from start_hour to end_hour during the sample, at the same speed every time.
@export_range(0.0, 24.0) var end_hour: float = 15.0

var time_manager: TimeManager
var _casters: Array[SkewShadowSprite] = []
var _lights: Array[Light2D] = []
var _sdf_node: Polygon2D
var _native_nodes: Array[CanvasItem] = []
var _viewport_rid: RID
## Config name -> Array of Run, in config order.
var _results: Dictionary[String, Array] = {}

var _fps_update_counter: int
var _fps_label: Label
var _info_label: Label

var _output: String

func _ready() -> void:
	set_process(run_on_start)
	
	if not run_on_start:
		return
	
	var ui: Node = BENCHMARK_UI.instantiate()
	_fps_label = ui.get_node("%FPS")
	_info_label = ui.get_node("%Info")
	add_child(ui)
	
	
	_run.call_deferred()

func _process(_delta: float) -> void:
	if _fps_update_counter == 0:
		_fps_update_counter = 5
		_fps_label.text = "FPS: " + str(Engine.get_frames_per_second())
	_fps_update_counter -= 1

# ------------------------------------------------------------------------------

func _run() -> void:
	_prepare_engine()
	_collect_nodes()
	_print_header()

	var configs: Array[BenchConfig] = _build_configs()
	for config: BenchConfig in configs:
		_results[config.name] = []

	for rep: int in repetitions:
		for config: BenchConfig in configs:
			_info_label.text = "[bench] rep %d/%d  %s" % [rep + 1, repetitions, config.name]
			print(_info_label.text)
			_results[config.name].append(await _measure(config))

	_print_results(configs)

	var saved_path: String = _save_results(configs)
	if saved_path.is_empty():
		_info_label.text = "Benchmark completo, mas falhou ao salvar os resultados (veja o Output)."
	else:
		_info_label.text = "Benchmark completo, resultados salvos em: %s" % saved_path
		print("[bench] Resultados salvos em: %s" % saved_path)

	if quit_on_end:
		get_tree().quit()


func _build_configs() -> Array[BenchConfig]:
	var configs: Array[BenchConfig] = [
		#               name                lighting sun    lights sdf    native
		BenchConfig.new("sem_iluminacao",   false,   false, false, false, false),
		BenchConfig.new("so_luzes",         true,    false, false, false, false),
		BenchConfig.new("sombra_sol",       true,    true,  false, false, false),
		BenchConfig.new("sombra_luzes",     true,    false, true,  false, false),
		BenchConfig.new("sdf_terreno",      true,    false, false, true,  false),
		BenchConfig.new("completo",         true,    true,  true,  true,  false),
	]
	if include_native:
		configs.append(BenchConfig.new("nativo_occluder", true, false, false, false, true))
	return configs


func _measure(config: BenchConfig) -> Run:
	_apply(config)

	# Warm up with the clock stopped at the start hour.
	if time_manager:
		time_manager.paused = true
		time_manager.set_time(start_hour)
	await get_tree().create_timer(warmup_seconds).timeout

	# Let the day run from start_hour to end_hour during the sample.
	if time_manager:
		time_manager.set_time(start_hour)
		time_manager.time_scale = _time_scale_for_sample()
		time_manager.paused = false

	var frame_ms: PackedFloat64Array = PackedFloat64Array()
	var cpu_total: float = 0.0
	var gpu_total: float = 0.0

	var last: int = Time.get_ticks_usec()
	var end: int = last + int(sample_seconds * 1_000_000.0)
	while last < end:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		cpu_total += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		gpu_total += RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid)
		last = now

	if time_manager:
		time_manager.paused = true

	var run: Run = Run.new()
	var count: int = maxi(frame_ms.size(), 1)
	var total: float = 0.0
	for value: float in frame_ms:
		total += value
	run.frame_avg = total / count
	run.frame_p99 = _percentile(frame_ms, 0.99)
	run.cpu_avg = cpu_total / count
	run.gpu_avg = gpu_total / count
	return run


## TimeManager.time_scale that moves the clock from start_hour to end_hour in sample_seconds.
func _time_scale_for_sample() -> float:
	var hours: float = fposmod(end_hour - start_hour, 24.0)
	return hours * time_manager.day_length_seconds / (24.0 * sample_seconds)


func _apply(config: BenchConfig) -> void:
	for light: Light2D in _lights:
		light.shadow_enabled = config.native

	if time_manager:
		time_manager.visible = config.lighting # Hidden CanvasModulate = full bright.
		time_manager.sun_enabled = config.lighting

	var any_shadow: bool = config.sun or config.lights
	for sprite: SkewShadowSprite in _casters:
		sprite.receive_sun = config.sun
		sprite.receive_light_shadows = config.lights
		sprite.set_shadows_active(any_shadow)

	_sdf_node.visible = config.sdf
	for item: CanvasItem in _native_nodes:
		item.visible = config.native


# ---------------- Setup ----------------

func _prepare_engine() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	_viewport_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)


func _collect_nodes() -> void:
	_casters.clear()
	_lights.clear()
	_walk(get_tree().current_scene)
	_sdf_node = get_node("%SDF")
	_native_nodes = _canvas_items_in(GROUP_NATIVE)


func _walk(node: Node) -> void:
	if node is SkewShadowSprite:
		_casters.append(node as SkewShadowSprite)
	elif node is Light2D:
		_lights.append(node as Light2D)
	elif node is TimeManager and time_manager == null:
		time_manager = node as TimeManager
	for child: Node in node.get_children():
		_walk(child)


func _canvas_items_in(group: StringName) -> Array[CanvasItem]:
	var items: Array[CanvasItem] = []
	for node: Node in get_tree().get_nodes_in_group(group):
		var item: CanvasItem = node as CanvasItem
		if item:
			items.append(item)
	return items


# ---------------- Statistics ----------------

static func _percentile(values: PackedFloat64Array, p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	var index: int = clampi(ceili(p * sorted.size()) - 1, 0, sorted.size() - 1)
	return sorted[index]


static func _mean(values: PackedFloat64Array) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / maxi(values.size(), 1)


## Sample standard deviation (n - 1).
static func _std(values: PackedFloat64Array) -> float:
	if values.size() < 2:
		return 0.0
	var mean: float = _mean(values)
	var sq: float = 0.0
	for value: float in values:
		sq += (value - mean) * (value - mean)
	return sqrt(sq / (values.size() - 1))


# ---------------- Output ----------------

func _print_header() -> void:
	_write_line("")
	_write_line("=== ShadowBenchmark ===")
	_write_line("Cena: %s" % get_tree().current_scene.scene_file_path)
	_write_line("Godot: %s | Renderizador: %s" % [Engine.get_version_info()["string"],
		ProjectSettings.get_setting("rendering/renderer/rendering_method")])
	_write_line("CPU: %s (%d threads)" % [OS.get_processor_name(), OS.get_processor_count()])
	_write_line("GPU: %s | Driver: %s" % [RenderingServer.get_video_adapter_name(),
		", ".join(OS.get_video_adapter_driver_info())])
	_write_line("SO: %s %s | Janela: %s | Build de depuração: %s" % [OS.get_name(), OS.get_version(),
		DisplayServer.window_get_size(), OS.is_debug_build()])
	_write_line("Objetos com sombra: %d | Luzes: %d" % [_casters.size(), _lights.size()])
	_write_line("Protocolo: %.0f s aquecimento, %.0f s amostra, %d repetições, relógio %s h -> %s h" % [
		warmup_seconds, sample_seconds, repetitions, start_hour, end_hour])
	_write_line("")


func _print_results(configs: Array[BenchConfig]) -> void:
	_info_label.text = "Benchmark completo, resultados salvos em: "
	var base: float = _mean(_column(configs[0].name, "frame_avg"))
	_write_line("")
	_write_line("=== Resultados (média ± desvio-padrão entre repetições, em ms) ===")
	_write_line("%-18s %16s %10s %10s %10s %10s %12s" % [
		"Configuração", "Quadro", "p99", "1% low", "CPU", "GPU", "Custo extra"])
	for config: BenchConfig in configs:
		var frame: PackedFloat64Array = _column(config.name, "frame_avg")
		var p99: float = _mean(_column(config.name, "frame_p99"))
		var frame_mean: float = _mean(frame)
		_write_line("%-18s %8.3f ± %5.3f %10.3f %7.1f fps %10.3f %10.3f %+12.3f" % [
			config.name,
			frame_mean, _std(frame),
			p99,
			1000.0 / maxf(p99, 0.001),
			_mean(_column(config.name, "cpu_avg")),
			_mean(_column(config.name, "gpu_avg")),
			frame_mean - base,
		])
	_write_line("")
	_write_line("Custo extra = quadro médio da configuração − quadro médio de %s." % configs[0].name)
	_write_line("Critério RNF01: quadro médio de 'completo' <= 16,667 ms (60 FPS).")

func _write_line(line: String) -> void:
	print(line)
	_output += "\n" + line

func _column(config_name: String, field: String) -> PackedFloat64Array:
	var values: PackedFloat64Array = PackedFloat64Array()
	for run: Run in _results[config_name]:
		values.append(run.get(field))
	return values

# ---------------- Saving ----------------

## Writes the report (.txt) and, optionally, the raw data (.csv).
## Returns the absolute path of the report, or "" on failure.
func _save_results(configs: Array[BenchConfig]) -> String:
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(output_dir)
	if dir_error != OK:
		push_error("[bench] Não foi possível criar '%s': %s" % [output_dir, error_string(dir_error)])
		return ""

	# "2026-11-01 20:46:00" -> "2026-11-01_20-46-00" (':' is not allowed on Windows).
	var stamp: String = Time.get_datetime_string_from_system(false, true) \
			.replace(":", "-").replace(" ", "_")
	var scene_name: String = get_tree().current_scene.scene_file_path.get_file().get_basename()
	var base_path: String = output_dir.path_join("bench_%s_%s" % [scene_name, stamp])

	var txt_path: String = base_path + ".txt"
	var txt_error: Error = _save_text(txt_path, _output.trim_prefix("\n") + "\n")
	if txt_error != OK:
		push_error("[bench] Não foi possível salvar '%s': %s" % [txt_path, error_string(txt_error)])
		return ""
	
	return ProjectSettings.globalize_path(txt_path)


func _save_text(path: String, text: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK
