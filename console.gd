extends VBoxContainer
## Instantiable GDSh prompt with an optional transcript.

const Context = preload("res://addons/addon_lib/gdsh/context.gd")
const Execute = preload("res://addons/addon_lib/gdsh/execute.gd")
const ConsoleInput = preload("res://addons/addon_lib/gdsh/console_input.gd")

signal command_submitted(text:String)
signal command_finished(text:String, result:Context)

var context:Context
var last_result:Context
var prompt_formatter:Callable:
	set(value):
		prompt_formatter = value
		update_prompt()

var prompt_row:HBoxContainer
var prompt_label:RichTextLabel
var input:ConsoleInput
var output:RichTextLabel

var command_history:Array[String] = []
var _history_index:int = -1
var _input_panel:PanelContainer


func _init(initial_context:Context=null) -> void:
	context = initial_context if initial_context != null else Context.new()
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


func _ready() -> void:
	_apply_theme()


func _notification(what:int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_apply_theme()


func _apply_theme() -> void:
	var normal = get_theme_stylebox("normal", "LineEdit")
	if normal != null:
		_input_panel.add_theme_stylebox_override("panel", normal)
	var font = get_theme_font("font", "LineEdit")
	var font_size = get_theme_font_size("font_size", "LineEdit")
	if font != null:
		prompt_label.add_theme_font_override("normal_font", font)
		input.add_theme_font_override("font", font)
	if font_size > 0:
		prompt_label.add_theme_font_size_override("normal_font_size", font_size)
		input.add_theme_font_size_override("font_size", font_size)
		_input_panel.custom_minimum_size.y = font_size + 12


func set_context(value:Context) -> void:
	context = value if value != null else Context.new()
	input.context = context
	last_result = null
	update_prompt()


func load(path:String, hidden:=false) -> Dictionary:
	return context.load(path, hidden)


func execute(text:String) -> Context:
	var command = text.strip_edges()
	if command.is_empty():
		return Context.new_ctx("Console submission", context)
	_add_to_history(command)
	command_submitted.emit(command)
	_append_command(command)

	var result = Context.new_ctx("Console submission", context)
	Execute.execute_command_multiline(command, result)
	last_result = result
	context.last_status = result.exit_code
	context.exit_code = result.exit_code
	# `exit` stops the submitted child and its descendants, not the console session.
	context.exit_requested = false

	_append_result(result)
	update_prompt()
	command_finished.emit(command, result)
	return result


func create_output() -> RichTextLabel:
	if output != null:
		return output
	output = RichTextLabel.new()
	output.name = "Output"
	output.bbcode_enabled = true
	output.selection_enabled = true
	output.context_menu_enabled = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(output)
	move_child(output, 0)
	return output


func clear_output() -> void:
	if output != null:
		output.clear()


func clear_history() -> void:
	command_history.clear()
	_history_index = -1


func update_prompt() -> void:
	if prompt_label == null:
		return
	if prompt_formatter.is_valid():
		prompt_label.text = str(prompt_formatter.call(context))
	else:
		prompt_label.text = _default_prompt(context)


static func _default_prompt(ctx:Context) -> String:
	var location = ctx.cwd.trim_suffix("/")
	if location == "res:/" or location == "res://" or location.is_empty():
		return "Console $"
	return "Console %s $" % location.get_file()


func _on_submit_requested(text:String) -> void:
	execute(text)
	input.clear()
	if input.is_inside_tree():
		input.grab_focus()


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


func _append_command(command:String) -> void:
	if output == null:
		return
	output.append_text(prompt_label.text)
	output.add_text(" " + command + "\n")


func _append_result(result:Context) -> void:
	if output == null:
		return
	if not result.stdout.is_empty():
		output.add_text(result.stdout)
	if not result.stderr.is_empty():
		output.push_color(Color("ff6b6b"))
		output.add_text("stderr:\n" + result.stderr)
		output.pop()
	output.scroll_to_line.call_deferred(maxi(0, output.get_line_count() - 1))
