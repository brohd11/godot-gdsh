#! namespace GDSh class Console
extends VBoxContainer
## Instantiable GDSh prompt with an optional transcript.

const Context = preload("res://addons/addon_lib/gdsh/context.gd")
const Execute = preload("res://addons/addon_lib/gdsh/execute.gd")
const ConsoleInput = preload("res://addons/addon_lib/gdsh/internal/console_input.gd")
const FONT_LICENSE = "res://addons/addon_lib/gdsh/internal/source_font.LICENSE.txt" #! dependency res://addons/plugin_exporter/licenses/source_font
const SourceFont = preload("res://addons/addon_lib/gdsh/internal/source_font.tres")
const Highlighter = preload("res://addons/addon_lib/gdsh/internal/console_highlighter.gd")
const ScriptHighlighter = preload("res://addons/addon_lib/gdsh/internal/script_highlighter.gd")
const Palette = preload("res://addons/addon_lib/gdsh/internal/palette.gd")
const TuiSession = preload("res://addons/addon_lib/gdsh/internal/tui_session.gd")

signal command_submitted(text:String)
signal command_finished(text:String, result:Context)
## Emitted when a submission starts and when it finishes.
signal busy_changed(busy:bool)

## True while a submission runs; input is locked until it finishes.
var is_busy:=false
var execution_handler:Callable
## `Callable() -> Context` building the session `new_ctx` resets to; a bare Context when unset.
var context_factory:Callable
## Echoed commands preview variable and alias values, as `[value]$name`.
var echo_values:=false
var context:Context
var last_result:Context
var prompt_formatter:Callable:
	set(value):
		prompt_formatter = value
		_manual_prompt = false
		update_prompt()

var prompt_row:HBoxContainer
var prompt_label:RichTextLabel
var input:ConsoleInput
var output:RichTextLabel

var command_history:Array[String] = []
var _history_index:int = -1
var _input_panel:PanelContainer
var _manual_prompt:=false
var _manual_prompt_text:String
var _manual_prompt_color:=Color.WHITE
var _font_override:Font = SourceFont
var _reset_requested:=false
## Live output: a running command's text reaches the transcript instead of only its result.
var stream_output:=true
## Chunks recorded by the sink, flushed to the transcript once per frame.
var _pending:Array = []
## How much of each stream the sink has already shown, so the result appends only the rest.
var _stream_out_len:int = 0
var _stream_err_len:int = 0
var _stream_err_header:=false
var active_tui:TuiSession
var _tui_hidden_controls:Array = []
var _leaving_tree:=false
var _submission_token:RefCounted


func _init(initial_context:Context=null) -> void:
	context = initial_context if initial_context != null else Context.new()
	context.host_data.get_or_add("clear_callback", _clear_from_command)
	context.host_data.get_or_add("new_ctx_callback", _request_reset)
	context.host_data["tui_begin"] = _begin_tui
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_input_panel = PanelContainer.new()
	_input_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_input_panel)

	prompt_row = HBoxContainer.new()
	prompt_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_panel.add_child(prompt_row)

	prompt_label = RichTextLabel.new()
	prompt_label.bbcode_enabled = true
	prompt_label.fit_content = true
	prompt_label.scroll_active = false
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.custom_minimum_size.x = 50
	prompt_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	prompt_row.add_child(prompt_label)

	input = ConsoleInput.new()
	input.context = context
	input.submit_requested.connect(_on_submit_requested)
	input.history_requested.connect(_on_history_requested)
	prompt_row.add_child(input)
	update_prompt()
	set_process(false) # Only runs while a submission is streaming.


func _ready() -> void:
	_apply_theme()


func _enter_tree() -> void:
	_leaving_tree = false


func _exit_tree() -> void:
	_leaving_tree = true
	if is_instance_valid(active_tui):
		active_tui.close()


func _notification(what:int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_apply_theme()


func _apply_theme() -> void:
	var normal = get_theme_stylebox("normal", "LineEdit")
	if normal != null:
		_input_panel.add_theme_stylebox_override("panel", normal)
	var font_size = get_theme_font_size("font_size", "LineEdit")
	if _font_override != null:
		_apply_font_override(_font_override)
	else:
		_remove_font_override()
	if font_size > 0:
		prompt_label.add_theme_font_size_override("normal_font_size", font_size)
		input.add_theme_font_size_override("font_size", font_size)
		_input_panel.custom_minimum_size.y = font_size + 12
		if is_instance_valid(active_tui):
			active_tui.display.add_theme_font_size_override("normal_font_size", font_size)
			active_tui.hint.add_theme_font_size_override("font_size", font_size)


func set_context(value:Context) -> void:
	context = value if value != null else Context.new()
	context.host_data.get_or_add("clear_callback", _clear_from_command) # A host's callback wins.
	context.host_data.get_or_add("new_ctx_callback", _request_reset)
	context.host_data["tui_begin"] = _begin_tui
	input.context = context
	last_result = null
	update_prompt()


## Replace the session with a fresh one from `context_factory`.
func reset_context() -> void:
	set_context(context_factory.call() if context_factory.is_valid() else Context.new())


func get_text_edit() -> CodeEdit:
	return input


func set_highlighter(syntax:SyntaxHighlighter) -> void:
	input.set_highlighter(syntax)


func get_prompt_label() -> RichTextLabel:
	return prompt_label


func set_prompt(text:String, color:=Color.WHITE) -> void:
	_manual_prompt = true
	_manual_prompt_text = text
	_manual_prompt_color = color
	_render_prompt(text, color)


func reset_prompt() -> void:
	_manual_prompt = false
	prompt_formatter = Callable()


func add_font_override(font:Font) -> void:
	_font_override = font
	_apply_font_override(font)


func remove_font_override() -> void:
	_font_override = null
	_remove_font_override()


func load(path:String, hidden:=false) -> Dictionary:
	var loaded = context.load(path, hidden)
	input.refresh_highlighting()
	return loaded


## Awaits async commands; input stays locked and further submissions are refused until done.
func execute(text:String) -> Context:
	var command = text.strip_edges()
	if command.is_empty():
		return Context.new_ctx("Console submission", context)
	if is_busy:
		var refused = Context.new_ctx("Console submission", context)
		refused.append_error("Console is busy: wait for the running command to finish")
		refused.exit_code = Context.ExitCode.ERR
		return refused
	_add_to_history(command)
	command_submitted.emit(command)
	_append_command(command)

	_set_busy(true)
	var result = Context.new_ctx("Console submission", context)
	_submission_token = RefCounted.new()
	result.host_data["__tui_submission"] = _submission_token
	_stream_begin(result)
	if execution_handler.is_valid():
		await execution_handler.call(command, result)
	else:
		await Execute.execute_command_multiline(command, result)
	if is_instance_valid(active_tui):
		active_tui.close()
	_submission_token = null
	if _leaving_tree:
		result.clear_output_sink()
		is_busy = false
		return result
	_stream_end(result)
	_set_busy(false)
	# `new_ctx` defers the swap so the running submission never straddles two sessions.
	if _reset_requested:
		_reset_requested = false
		reset_context()
	last_result = result
	context.last_status = result.exit_code
	context.exit_code = result.exit_code
	# `exit` stops the submitted child and its descendants, not the console session.
	context.exit_requested = false
	input.refresh_highlighting()

	_append_result(result)
	update_prompt()
	command_finished.emit(command, result)
	return result


## Host callback inherited by command contexts. Captured stdout cannot acquire a UI.
func _begin_tui(ctx:Context) -> TuiSession:
	if not is_inside_tree() or _leaving_tree:
		ctx.append_error("TUI: an interactive console view is required")
		return null
	if not ctx.execute or not is_busy or _submission_token == null \
			or ctx.host_data.get("__tui_submission") != _submission_token:
		ctx.append_error("TUI: only an active console submission can open a view")
		return null
	if ctx._capture_out > 0:
		ctx.append_error("TUI: cannot open a view while stdout is captured")
		return null
	if is_instance_valid(active_tui):
		ctx.append_error("TUI: a view is already active")
		return null
	var parent = _get_tui_parent()
	if not is_visible_in_tree() or not is_instance_valid(parent) or not parent.is_inside_tree():
		ctx.append_error("TUI: an interactive console view is required")
		return null
	_tui_hidden_controls.clear()
	for control in _get_tui_controls_to_hide(parent):
		if is_instance_valid(control):
			_tui_hidden_controls.append([weakref(control), control.visible])
			control.hide()
	input._hide_completion()
	input._timer.stop()
	active_tui = TuiSession.new(self)
	parent.add_child(active_tui)
	parent.move_child(active_tui, 0)
	if _font_override != null:
		active_tui.display.add_theme_font_override("normal_font", _font_override)
		active_tui.display.add_theme_font_override("mono_font", _font_override)
		active_tui.hint.add_theme_font_override("font", _font_override)
	var font_size = get_theme_font_size("font_size", "LineEdit")
	active_tui.display.add_theme_font_size_override("normal_font_size", font_size)
	active_tui.hint.add_theme_font_size_override("font_size", font_size)
	active_tui.display.grab_focus()
	return active_tui


## Override to host a session outside this prompt (for example, in an editor dock).
func _get_tui_parent() -> Control:
	return self if is_instance_valid(output) else null


func _get_tui_controls_to_hide(_parent:Control) -> Array[Control]:
	return [_input_panel, output]


func _end_tui(session:TuiSession) -> void:
	if active_tui != session:
		return
	active_tui = null
	session.hide()
	# An external display must be restored even while the prompt itself is leaving.
	for entry in _tui_hidden_controls:
		var control = entry[0].get_ref()
		if is_instance_valid(control):
			control.visible = entry[1]
	_tui_hidden_controls.clear()
	if not _leaving_tree and input.is_visible_in_tree():
		input.grab_focus()


func create_output() -> RichTextLabel:
	if output != null:
		return output
	output = RichTextLabel.new()
	output.name = "Output"
	output.bbcode_enabled = true
	output.selection_enabled = true
	output.context_menu_enabled = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.mouse_filter = Control.MOUSE_FILTER_STOP
	output.mouse_force_pass_scroll_events = false
	output.gui_input.connect(_on_output_gui_input)
	add_child(output)
	move_child(output, 0)
	_apply_theme()
	return output


func clear_output() -> void:
	discard_pending_stream()
	if output != null:
		output.clear()


## Drop live output that has not been shown yet, so a cleared transcript is not refilled by
## the next flush. Hosts that clear their own transcript must call this too.
func discard_pending_stream() -> void:
	_pending.clear()
	_stream_err_header = false


## Install the live channel for one submission. Counters reset here, so a console that is not
## streaming leaves them at zero and renders exactly as it did before.
func _stream_begin(result:Context) -> void:
	_pending.clear()
	_stream_out_len = 0
	_stream_err_len = 0
	_stream_err_header = false
	if not _stream_enabled():
		return
	result.set_output_sink(_on_stream_chunk)
	set_process(true)


## Final flush and teardown: covers a fully synchronous submission, and a console outside the
## tree where `_process` never runs.
func _stream_end(result:Context) -> void:
	_flush_stream()
	result.clear_output_sink()
	set_process(false)


## Whether this console streams. Subclasses combine it with their host's setting.
func _stream_enabled() -> bool:
	return stream_output


## The sink. This runs inside the running command's call stack, so it only records: it must not
## await, execute commands, or touch the context.
func _on_stream_chunk(text:String, is_error:bool) -> void:
	if is_error:
		_stream_err_len += text.length()
	else:
		_stream_out_len += text.length()
	if not _pending.is_empty() and _pending[-1][1] == is_error:
		_pending[-1][0] += text
	else:
		_pending.append([text, is_error])


func _process(_delta:float) -> void:
	if not _pending.is_empty():
		_flush_stream()


func _flush_stream() -> void:
	if _pending.is_empty():
		return
	var chunks = _pending
	_pending = []
	for chunk in chunks:
		_stream_chunk(chunk[0], chunk[1])
	if output != null:
		output.scroll_to_line.call_deferred(maxi(0, output.get_line_count() - 1))


## Render one streamed chunk. This must match `_append_result`'s rendering, or live output and
## the trailing result would look different in the same transcript.
func _stream_chunk(text:String, is_error:bool) -> void:
	if output == null:
		return
	if not is_error:
		output.add_text(text)
		return
	output.push_color(Color("ff6b6b"))
	if not _stream_err_header:
		_stream_err_header = true
		output.add_text("stderr:\n")
	output.add_text(text)
	output.pop()


## The part of a buffer the sink never showed: empty once streaming displayed all of it, and the
## whole buffer when streaming was off.
static func _stream_tail(buffer:String, streamed:int) -> String:
	if streamed <= 0:
		return buffer
	if buffer.length() <= streamed:
		return ""
	return buffer.substr(streamed)


func clear_history() -> void:
	command_history.clear()
	_history_index = -1


## Default handler for the `clear` builtin, installed unless the host supplied one.
func _clear_from_command(_ctx:Context, history:bool) -> int:
	clear_output()
	if history:
		clear_history()
	return Context.ExitCode.OK


## Default handler for the `new_ctx` builtin; `execute` applies it after the submission.
func _request_reset(_ctx:Context) -> int:
	_reset_requested = true
	return Context.ExitCode.OK


func update_prompt() -> void:
	if prompt_label == null:
		return
	if _manual_prompt:
		_render_prompt(_manual_prompt_text, _manual_prompt_color)
	elif prompt_formatter.is_valid():
		prompt_label.text = str(prompt_formatter.call(context))
	else:
		_render_prompt(_default_prompt(context), Color.LIGHT_BLUE)


func _render_prompt(text:String, color:Color) -> void:
	prompt_label.text = text if color == Color.WHITE else \
			"[color=%s]%s[/color]" % [color.to_html(), text]


func _apply_font_override(font:Font) -> void:
	prompt_label.add_theme_font_override("normal_font", font)
	input.add_theme_font_override("font", font)
	if output != null:
		output.add_theme_font_override("normal_font", font)
		output.add_theme_font_override("mono_font", font)
	if is_instance_valid(active_tui):
		active_tui.display.add_theme_font_override("normal_font", font)
		active_tui.display.add_theme_font_override("mono_font", font)
		active_tui.hint.add_theme_font_override("font", font)


func _remove_font_override() -> void:
	prompt_label.remove_theme_font_override("normal_font")
	input.remove_theme_font_override("font")
	if output != null:
		output.remove_theme_font_override("normal_font")
		output.remove_theme_font_override("mono_font")
	if is_instance_valid(active_tui):
		active_tui.display.remove_theme_font_override("normal_font")
		active_tui.display.remove_theme_font_override("mono_font")
		active_tui.hint.remove_theme_font_override("font")


static func _default_prompt(ctx:Context) -> String:
	var location = ctx.cwd.trim_suffix("/")
	if location == "res:/" or location == "res://" or location.is_empty():
		return "Console $"
	return "Console %s $" % location.get_file()


func _on_submit_requested(text:String) -> void:
	if is_busy:
		return
	await execute(text)
	if _leaving_tree:
		return
	input.clear()
	if input.is_inside_tree():
		input.grab_focus()


func _set_busy(value:bool) -> void:
	is_busy = value
	input.editable = not value
	busy_changed.emit(value)


func _on_output_gui_input(event:InputEvent) -> void:
	if event is InputEventPanGesture:
		_scroll_output(event.delta.y)
		accept_event()
	elif event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT,
	]:
		if event.pressed and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
		]:
			var direction = -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			_scroll_output(direction * maxf(event.factor, 1.0))
		accept_event()


func _scroll_output(lines:float) -> void:
	if output == null or is_zero_approx(lines):
		return
	var line_height = 16.0
	if output.get_line_count() > 0:
		line_height = maxf(output.get_line_height(0), line_height)
	output.get_v_scroll_bar().value += lines * line_height * 3.0


func _add_to_history(command:String) -> void:
	var existing = command_history.rfind(command)
	if existing >= 0:
		command_history.remove_at(existing)
	command_history.append(command)
	_history_index = -1


func _on_history_requested(direction:int) -> void:
	if command_history.is_empty():
		return
	if direction < 0:
		_history_index -= 1
		if _history_index < -1:
			_history_index = command_history.size() - 1
	else:
		_history_index += 1
		if _history_index >= command_history.size():
			_history_index = -1
	if _history_index == -1:
		_set_input_text("")
	else:
		_set_input_text(command_history[_history_index])


func _set_input_text(value:String) -> void:
	input.text = value
	input.set_caret_column(value.length())


## Transcript BBCode for a submitted command, colored by the input highlighter when it supports it.
func format_command(command:String) -> String:
	var syntax = input.syntax_highlighter
	if syntax != null and syntax.has_method("to_bbcode"):
		return syntax.to_bbcode(command, echo_values)
	return command.replace("[", "[lb]")


func _append_command(command:String) -> void:
	if output == null:
		return
	output.append_text(prompt_label.text + " " + format_command(command) + "\n")


func _append_result(result:Context) -> void:
	if output == null:
		return
	var tail = _stream_tail(result.stdout, _stream_out_len)
	var err_tail = _stream_tail(result.stderr, _stream_err_len)
	if not tail.is_empty():
		output.add_text(tail)
	if not err_tail.is_empty():
		output.push_color(Color("ff6b6b"))
		if not _stream_err_header:
			output.add_text("stderr:\n")
		output.add_text(err_tail)
		output.pop()
	output.scroll_to_line.call_deferred(maxi(0, output.get_line_count() - 1))
