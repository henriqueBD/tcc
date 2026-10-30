class_name Benchmark
extends CanvasLayer

enum State { IDLE, WARMUP, RUNNING, DONE }

@export var run: bool
@export var warmup_time: float = 2.0
@export var duration: float = 10.0
@export var disable_vsync: bool = true
@export var restart_key: Key = KEY_F5

var _state: State = State.IDLE
var _timer: float = 0.0
var _last_tick_usec: int = 0
var _frame_times_ms: PackedFloat32Array = PackedFloat32Array()
var _original_vsync: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED
var _label: Label


func _ready() -> void:
	if not run:
		set_process_unhandled_input(false)
		return
	
	print("Runing benchmark")
	
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_label = Label.new()
	_label.position = Vector2(10.0, 10.0)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)

	_original_vsync = DisplayServer.window_get_vsync_mode()

	_label.text = "Press %s to start benchmark" % OS.get_keycode_string(restart_key)


func start() -> void:
	Engine.max_fps = 0
	_frame_times_ms.clear()
	_timer = 0.0
	_last_tick_usec = Time.get_ticks_usec()
	_state = State.WARMUP
	if disable_vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _unhandled_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event and key_event.pressed and not key_event.echo and key_event.keycode == restart_key:
		start()


func _process(_delta: float) -> void:
	# Measure real elapsed time so Engine.time_scale doesn't skew results.
	var now_usec: int = Time.get_ticks_usec()
	var frame_ms: float = float(now_usec - _last_tick_usec) / 1000.0
	_last_tick_usec = now_usec

	match _state:
		State.WARMUP:
			_timer += frame_ms / 1000.0
			_label.text = "Benchmark: warming up... %.1fs" % (warmup_time - _timer)
			if _timer >= warmup_time:
				_timer = 0.0
				_state = State.RUNNING
		State.RUNNING:
			_timer += frame_ms / 1000.0
			_frame_times_ms.append(frame_ms)
			_label.text = "Benchmark: running %.1f / %.1fs\nFPS: %d" % [
				_timer, duration, Engine.get_frames_per_second()
			]
			if _timer >= duration:
				_finish()


func _finish() -> void:
	Engine.max_fps = 60
	_state = State.DONE
	if disable_vsync:
		DisplayServer.window_set_vsync_mode(_original_vsync)

	var count: int = _frame_times_ms.size()
	if count == 0:
		_label.text = "Benchmark: no frames recorded"
		return

	var sorted: PackedFloat32Array = _frame_times_ms.duplicate()
	sorted.sort()

	var total_ms: float = 0.0
	for t: float in sorted:
		total_ms += t

	var avg_ms: float = total_ms / float(count)
	var median_ms: float = sorted[count / 2]
	var min_ms: float = sorted[0]
	var max_ms: float = sorted[count - 1]

	# 1% low: average FPS of the slowest 1% of frames.
	var low_count: int = maxi(1, int(float(count) * 0.01))
	var low_total_ms: float = 0.0
	for i: int in range(count - low_count, count):
		low_total_ms += sorted[i]
	var one_percent_low_fps: float = 1000.0 / (low_total_ms / float(low_count))

	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var static_mem_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0

	var report: String = "\n".join([
		"Results",
		"Frames:        %d over %.1fs" % [count, total_ms / 1000.0],
		"Average FPS:   %.1f" % (1000.0 / avg_ms),
		"1%% Low FPS:    %.1f" % one_percent_low_fps,
		"Frame time:    avg %.2f ms | median %.2f ms" % [avg_ms, median_ms],
		"               min %.2f ms | max %.2f ms" % [min_ms, max_ms],
		"Draw calls:    %d" % draw_calls,
		"Nodes:         %d" % node_count,
		"Static memory: %.1f MB" % static_mem_mb,
		"Press %s to run again" % OS.get_keycode_string(restart_key),
	])
	
	_label.text = report
	print(report)
