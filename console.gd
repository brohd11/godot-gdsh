#! namespace GDSh class Console
extends "res://addons/addon_lib/gdsh/internal/console_base.gd"
## Instantiable GDSh prompt with an optional transcript.

const ConsoleInput = preload("res://addons/addon_lib/gdsh/internal/console_input.gd")

var prompt_row:HBoxContainer
var prompt_label:RichTextLabel
var input:ConsoleInput
var _input_panel:PanelContainer


func _init(initial_context:Context=null) -> void:
	super(initial_context)

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


func get_text_edit() -> CodeEdit:
	return input


func set_highlighter(syntax:SyntaxHighlighter) -> void:
	input.set_highlighter(syntax)


func get_prompt_label() -> RichTextLabel:
	return prompt_label


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


func _set_input_text(value:String) -> void:
	input.text = value
	input.set_caret_column(value.length())


## Transcript BBCode for a submitted command, colored by the input highlighter when it supports it.
func format_command(command:String) -> String:
	var syntax = input.syntax_highlighter
	if syntax != null and syntax.has_method("to_bbcode"):
		return syntax.to_bbcode(command, echo_values)
	return command.replace("[", "[lb]")


func _context_changed() -> void:
	input.context = context


func _refresh_highlighting() -> void:
	input.refresh_highlighting()


func _prompt_changed() -> void:
	if prompt_label != null:
		prompt_label.text = _prompt_bbcode


func _set_input_editable(editable:bool) -> void:
	input.editable = editable


func _suspend_input() -> void:
	input._hide_completion()
	if input._timer != null:
		input._timer.stop()


func _get_tui_controls_to_hide(_parent:Control) -> Array[Control]:
	return [_input_panel, output]


func focus_input() -> void:
	if input.is_visible_in_tree():
		input.grab_focus()
