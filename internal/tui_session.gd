extends VBoxContainer
## One temporary interactive view, owned by a Console. Drawing never enters stdout.

signal input_event(event:InputEvent)
signal closed(value:Variant)
signal frame_requested

var display:RichTextLabel
var hint:Label
var is_closed:=false
var _host:WeakRef
var _measure:RichTextLabel
var _metrics_dirty:=true
var _row_height:float
var _row_pitch:float


func _init(host:Control=null) -> void:
	_host = weakref(host) if host != null else null
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display = RichTextLabel.new()
	display.bbcode_enabled = true
	display.autowrap_mode = TextServer.AUTOWRAP_OFF
	display.focus_mode = Control.FOCUS_ALL
	display.mouse_filter = Control.MOUSE_FILTER_STOP
	display.mouse_force_pass_scroll_events = false
	display.shortcut_keys_enabled = false
	display.scroll_active = false
	display.scroll_following = false
	display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	display.add_theme_constant_override("text_highlight_h_padding", 0)
	display.add_theme_constant_override("text_highlight_v_padding", 0)
	display.gui_input.connect(_on_gui_input)
	display.resized.connect(request_frame)
	display.theme_changed.connect(_invalidate_metrics)
	add_child(display)
	# Use the same text shaping as the visible label. Font.get_height() can include
	# extra font spacing that RichTextLabel does not use for its rendered rows.
	_measure = RichTextLabel.new()
	_measure.hide()
	_measure.autowrap_mode = TextServer.AUTOWRAP_OFF
	_measure.scroll_active = false
	_measure.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_measure.size = Vector2(10000, 10000)
	_measure.text = "Mg\nMg"
	add_child(_measure)
	hint = Label.new()
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Reserve one footer line even before a program supplies its hint.
	hint.text = " "
	add_child(hint)
	set_process(false)


func request_frame() -> void:
	if not is_closed:
		set_process(true)


func _process(_delta:float) -> void:
	set_process(false)
	frame_requested.emit()


func get_viewport_size_in_cells() -> Vector2i:
	var font = display.get_theme_font("normal_font")
	var font_size = display.get_theme_font_size("normal_font_size")
	if _metrics_dirty:
		_measure.add_theme_font_override("normal_font", font)
		_measure.add_theme_font_size_override("normal_font_size", font_size)
		for setting in ["line_separation", "paragraph_separation"]:
			_measure.add_theme_constant_override(setting, display.get_theme_constant(setting))
		_row_height = _measure.get_line_height(0)
		_row_pitch = _measure.get_paragraph_offset(1) - _measure.get_paragraph_offset(0)
		_metrics_dirty = false
	var available = display.size - display.get_theme_stylebox("normal").get_minimum_size()
	var rows = 0 if available.y < _row_height else 1 + int((available.y - _row_height) / maxf(_row_pitch, 1))
	return Vector2i(maxi(0, int(available.x / maxf(font.get_char_size(77, font_size).x, 1))), maxi(0, rows))


func _invalidate_metrics() -> void:
	_metrics_dirty = true
	request_frame()


## Restore the host before waking the command. Repeated calls are harmless.
func close(value:Variant=null) -> void:
	if is_closed:
		return
	is_closed = true
	set_process(false)
	var host = _host.get_ref() if _host != null else null
	if is_instance_valid(host):
		host._end_tui(self)
	closed.emit(value)
	queue_free()


func _exit_tree() -> void:
	close()


func _on_gui_input(event:InputEvent) -> void:
	if is_closed:
		return
	# Accept before emitting: a callback can close the session and move focus.
	if event is InputEventKey or event is InputEventMouse or event is InputEventPanGesture:
		display.accept_event()
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			display.grab_focus()
		input_event.emit(event)
