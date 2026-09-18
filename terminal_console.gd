#! namespace GDSh class TerminalConsole
extends "res://addons/addon_lib/gdsh/internal/console_base.gd"
## Rich-text shell: one selectable transcript, with a separately owned command buffer.
const InputModel = preload("res://addons/addon_lib/gdsh/internal/terminal_input.gd")
const CaretEffect = preload("res://addons/addon_lib/gdsh/internal/terminal_caret_effect.gd")
const Completion = preload("res://addons/addon_lib/gdsh/completion.gd")
const CompletionModel = preload("res://addons/addon_lib/gdsh/internal/console_completion.gd")
const CompletionPopup = preload("res://addons/addon_lib/gdsh/internal/completion_popup.gd")

## Editor hosts opt in to command-produced BBCode, matching their existing transcript.
var output_bbcode:=false
var completion_factory:Callable
var input_model = InputModel.new()
var _syntax:SyntaxHighlighter = Highlighter.new()
var _tail_paragraph:int = -1
var _tail_start:int
var _input_start:int
var _rendered_input:String
var _accept_input:=true
var _submission_open:=false
var _caret_effect = CaretEffect.new()
var _caret_overlay:Control
var _caret_rect:Rect2
var _caret_scroll:float
var _caret_known:=false
var _blink_on:=true
var _blink:Timer
var _completion_timer:Timer
var _popup:CompletionPopup
var _completion_request:Completion
var _completion_generation:int
var _follow_output:=true
var _updating_tail:=false


func _init(initial_context:Context=null) -> void:
	super(initial_context)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	output = RichTextLabel.new()
	output.name = "Terminal"
	output.bbcode_enabled = true
	output.selection_enabled = true
	output.context_menu_enabled = true
	output.shortcut_keys_enabled = false
	output.drag_and_drop_selection_enabled = false
	output.focus_mode = Control.FOCUS_ALL
	output.mouse_filter = Control.MOUSE_FILTER_STOP
	output.mouse_force_pass_scroll_events = false
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	output.text_direction = Control.TEXT_DIRECTION_LTR
	output.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	output.install_effect(_caret_effect)
	output.gui_input.connect(_on_terminal_input)
	output.focus_entered.connect(_reset_blink)
	output.focus_exited.connect(_on_focus_lost)
	output.resized.connect(_on_layout_changed)
	output.get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
	add_child(output)
	_caret_overlay = Control.new()
	_caret_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caret_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caret_overlay.draw.connect(_draw_caret)
	output.add_child(_caret_overlay)
	_caret_effect.positioned.connect(_on_caret_positioned)
	_blink = Timer.new()
	_blink.wait_time = 0.5
	_blink.timeout.connect(func():
		_blink_on = not _blink_on
		_caret_overlay.queue_redraw())
	add_child(_blink)
	_completion_timer = Timer.new()
	_completion_timer.one_shot = true
	_completion_timer.wait_time = 0.1
	_completion_timer.timeout.connect(request_completion.bind(false))
	add_child(_completion_timer)
	input_model.changed.connect(_on_buffer_changed)
	_context_changed()
	update_prompt()


func create_output() -> RichTextLabel:
	return output


func get_input_text() -> String:
	return input_model.text


func set_input_text(value:String) -> void:
	_set_input_text(value)


func _set_input_text(value:String) -> void:
	input_model.set_text(value)


func focus_input() -> void:
	if output.is_visible_in_tree():
		output.grab_focus()


func set_highlighter(syntax:SyntaxHighlighter) -> void:
	_syntax = syntax
	_refresh_highlighting()
	_render_tail()


func _context_changed() -> void:
	_refresh_highlighting()
	_hide_completion()


func _refresh_highlighting() -> void:
	if _syntax != null:
		if _syntax.has_method("set_context"):
			_syntax.set_context(context)
		_syntax.clear_highlighting_cache()


func format_command(command:String) -> String:
	return _format_input(command, echo_values)


func _format_input(command:String, values:=false) -> String:
	if _syntax != null and _syntax.has_method("to_bbcode"):
		return _syntax.to_bbcode(command, values)
	return command.replace("[", "[lb]")


func _prompt_changed() -> void:
	if output != null and not is_busy:
		_render_tail()


func _remove_tail() -> void:
	if _tail_paragraph < 0:
		return
	# All tags in the tail are balanced; completed paragraphs stay untouched.
	for paragraph in range(output.get_paragraph_count() - 1, _tail_paragraph - 1, -1):
		output.remove_paragraph(paragraph)
	_tail_paragraph = -1
	_caret_known = false
	_caret_effect.character = -1
	_caret_overlay.queue_redraw()


func _render_tail() -> void:
	if output == null or is_busy or _submission_open or not _accept_input:
		return
	_updating_tail = true
	var scroll = output.get_v_scroll_bar().value
	_remove_tail()
	output.push_paragraph(HORIZONTAL_ALIGNMENT_LEFT, Control.TEXT_DIRECTION_LTR)
	_tail_paragraph = output.get_paragraph_count() - 1
	_tail_start = output.get_total_character_count()
	output.push_customfx(_caret_effect, {})
	output.append_text(_prompt_bbcode)
	output.add_text(" ")
	_input_start = output.get_total_character_count()
	output.append_text(_format_input(input_model.text))
	output.pop() # effect
	output.pop() # paragraph
	_rendered_input = input_model.text
	_caret_effect.character = _input_start + input_model.caret
	output.get_v_scroll_bar().value = scroll
	_updating_tail = false
	_reset_blink()


func _on_buffer_changed() -> void:
	var text_changed = input_model.text != _rendered_input
	_hide_completion()
	_completion_timer.stop()
	if not _accept_input or is_busy:
		return
	output.deselect()
	if text_changed or _tail_paragraph < 0:
		_render_tail()
	else:
		_caret_effect.character = _input_start + input_model.caret
		_caret_known = false
		output.queue_redraw()
	_reset_blink()
	_reveal_caret.call_deferred()
	if text_changed and is_inside_tree() and output.has_focus():
		_completion_timer.start()


func _append_command(command:String) -> void:
	_submission_open = true
	_suspend_input()
	_updating_tail = true
	_remove_tail()
	output.push_paragraph(HORIZONTAL_ALIGNMENT_LEFT)
	output.append_text(_prompt_bbcode + " " + format_command(command))
	output.pop()
	output.newline()
	_updating_tail = false
	_follow_output = true


func _set_input_editable(editable:bool) -> void:
	_accept_input = editable
	if not editable:
		_suspend_input()
	_caret_overlay.queue_redraw()


func _append_result(result:Context) -> void:
	var tail = _stream_tail(result.stdout, _stream_out_len)
	var err_tail = _stream_tail(result.stderr, _stream_err_len)
	if not tail.is_empty():
		_stream_chunk(tail, false)
	if not err_tail.is_empty():
		_stream_chunk(err_tail, true)
	# Results without a final newline still leave the next prompt on its own line.
	if not output.get_parsed_text().is_empty() and not output.get_parsed_text().ends_with("\n"):
		output.newline()
	input_model.text = ""
	input_model.caret = 0
	_rendered_input = ""
	_submission_open = false
	_scroll_after_output()


func _stream_chunk(text:String, is_error:bool) -> void:
	if is_error:
		output.push_color(Color("ff6b6b"))
		if not _stream_err_header:
			_stream_err_header = true
			output.add_text("stderr:\n")
	if output_bbcode:
		output.append_text(text)
	else:
		output.add_text(text)
	if is_error:
		output.pop()


func clear_output() -> void:
	discard_pending_stream()
	output.clear()
	_tail_paragraph = -1
	_caret_known = false
	_follow_output = true
	if not is_busy:
		_render_tail()


func _scroll_after_output() -> void:
	if _follow_output:
		_scroll_to_bottom.call_deferred()


func _scroll_to_bottom() -> void:
	if _leaving_tree or not _follow_output:
		return
	output.get_content_height() # Complete pending layout before setting the range.
	var bar = output.get_v_scroll_bar()
	bar.value = maxf(0, bar.max_value - bar.page)


func _on_scroll_changed(_value:float) -> void:
	if not _updating_tail:
		var bar = output.get_v_scroll_bar()
		_follow_output = bar.value >= bar.max_value - bar.page - 2
	_caret_overlay.queue_redraw()


func _reveal_caret() -> void:
	if _leaving_tree or is_busy or _tail_paragraph < 0:
		return
	output.get_content_height()
	# The insertion position at EOF is outside get_character_line's character range.
	var character = mini(_input_start + input_model.caret, output.get_total_character_count() - 1)
	var line = output.get_character_line(character)
	var first_line = output.get_character_line(_tail_start)
	if line < 0 or first_line < 0:
		return
	# get_line_offset at a paragraph boundary omits paragraph spacing in Godot 4.6.
	var top = output.get_paragraph_offset(_tail_paragraph)
	for row in range(first_line, line):
		top += output.get_line_height(row)
	var height = output.get_line_height(line)
	var bar = output.get_v_scroll_bar()
	if top < bar.value:
		bar.value = top
	elif top + height > bar.value + bar.page:
		bar.value = top + height - bar.page
	output.queue_redraw()


func _on_layout_changed() -> void:
	_caret_known = false
	if _popup != null:
		_hide_completion()
	output.queue_redraw()
	_caret_overlay.queue_redraw()


func _on_caret_positioned(rect:Rect2) -> void:
	if rect != _caret_rect or not _caret_known or _caret_scroll != output.get_v_scroll_bar().value:
		_caret_rect = rect
		_caret_scroll = output.get_v_scroll_bar().value
		_caret_known = true
		_caret_overlay.queue_redraw()


func get_caret_rect() -> Rect2:
	var rect = _caret_rect
	rect.position.y += _caret_scroll - output.get_v_scroll_bar().value
	rect.position.x = clampf(rect.position.x, 0, maxf(0, output.size.x - rect.size.x - output.get_v_scroll_bar().size.x * float(output.get_v_scroll_bar().visible)))
	return rect


func _draw_caret() -> void:
	if _caret_known and _blink_on and _accept_input and not is_busy and output.has_focus() and active_tui == null:
		_caret_overlay.draw_rect(get_caret_rect(), output.get_theme_color("default_color"))


func _reset_blink() -> void:
	_blink_on = true
	if is_inside_tree() and output.has_focus() and _accept_input:
		_blink.start()
	_caret_overlay.queue_redraw()


func _on_focus_lost() -> void:
	_suspend_input()


func _suspend_input() -> void:
	_hide_completion()
	_completion_timer.stop()
	_blink.stop()
	_caret_overlay.queue_redraw()


func _apply_theme() -> void:
	if output == null:
		return
	if _font_override != null:
		_apply_font_override(_font_override)
	else:
		_remove_font_override()
	var font_size = get_theme_font_size("font_size", "LineEdit")
	output.add_theme_font_size_override("normal_font_size", font_size)
	output.add_theme_font_size_override("mono_font_size", font_size)
	_caret_effect.font_size = font_size
	if is_instance_valid(active_tui):
		active_tui.display.add_theme_font_size_override("normal_font_size", font_size)
		active_tui.hint.add_theme_font_size_override("font_size", font_size)
	_on_layout_changed()


func _apply_font_override(font:Font) -> void:
	for slot in ["normal_font", "mono_font", "bold_font", "italics_font", "bold_italics_font"]:
		output.add_theme_font_override(slot, font)
	if is_instance_valid(active_tui):
		active_tui.display.add_theme_font_override("normal_font", font)
		active_tui.display.add_theme_font_override("mono_font", font)
		active_tui.hint.add_theme_font_override("font", font)
	_on_layout_changed()


func _remove_font_override() -> void:
	for slot in ["normal_font", "mono_font", "bold_font", "italics_font", "bold_italics_font"]:
		output.remove_theme_font_override(slot)
	if is_instance_valid(active_tui):
		active_tui.display.remove_theme_font_override("normal_font")
		active_tui.display.remove_theme_font_override("mono_font")
		active_tui.hint.remove_theme_font_override("font")
	_on_layout_changed()


func _shortcut_input(event:InputEvent) -> void:
	if event is InputEventKey and output.has_focus():
		get_viewport().set_input_as_handled()


func _on_terminal_input(event:InputEvent) -> void:
	if event is InputEventPanGesture or event is InputEventMouseButton:
		_on_output_gui_input(event)
		return # Native mouse selection still receives clicks/drags.
	if not event is InputEventKey or not event.pressed:
		return
	output.accept_event()
	var shortcut = event.ctrl_pressed or event.meta_pressed
	if shortcut and event.keycode == KEY_C:
		if not output.get_selected_text().is_empty():
			DisplayServer.clipboard_set(output.get_selected_text())
		elif not is_busy and not event.echo:
			set_input_text("")
		return
	if shortcut and event.keycode == KEY_A:
		output.select_all()
		return
	if is_busy or not _accept_input:
		return
	var popup_visible = _popup != null and _popup.visible
	var word = event.ctrl_pressed or event.alt_pressed
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if not event.echo:
				_on_submit_requested(input_model.text)
		KEY_TAB:
			if not event.echo:
				if popup_visible and _popup.has_selection():
					_popup.accept_selected()
				else:
					request_completion()
		KEY_UP, KEY_DOWN:
			if popup_visible:
				if event.keycode == KEY_UP: _popup.select_previous()
				else: _popup.select_next()
			else:
				_on_history_requested(-1 if event.keycode == KEY_UP else 1)
		KEY_LEFT:
			input_model.move_to(0 if event.meta_pressed else input_model.word_left() if word else input_model.caret - 1)
		KEY_RIGHT:
			input_model.move_to(input_model.text.length() if event.meta_pressed else input_model.word_right() if word else input_model.caret + 1)
		KEY_HOME:
			input_model.move_to(0)
		KEY_END:
			input_model.move_to(input_model.text.length())
		KEY_BACKSPACE:
			input_model.replace(input_model.word_left() if word else input_model.caret - 1, input_model.caret, "")
		KEY_DELETE:
			input_model.replace(input_model.caret, input_model.word_right() if word else input_model.caret + 1, "")
		KEY_ESCAPE:
			_hide_completion()
		_:
			if shortcut and event.keycode == KEY_V:
				if not event.echo:
					input_model.insert(DisplayServer.clipboard_get())
			elif not shortcut and event.unicode >= 32 and event.unicode != 127:
				input_model.insert(String.chr(event.unicode))


func request_completion(force:=true) -> void:
	if is_busy or not _accept_input or not is_inside_tree() or not output.has_focus():
		return
	_completion_generation += 1
	var generation = _completion_generation
	if input_model.text.is_empty() and not force:
		_hide_completion()
		return
	_completion_request = completion_factory.call(input_model.text, context, input_model.caret) if completion_factory.is_valid() \
			else Completion.new(input_model.text, context, input_model.caret)
	var choices = CompletionModel.choices(_completion_request)
	if choices.is_empty():
		_hide_completion()
		return
	if _popup == null:
		_popup = CompletionPopup.new()
		_popup.choice_accepted.connect(_accept_completion)
		output.add_child(_popup)
	if await _popup.set_choices(choices, generation):
		if generation == _completion_generation and not is_busy and output.has_focus():
			_popup.position_for_rect(get_caret_rect(), Rect2(Vector2.ZERO, output.size))


func _accept_completion(choice:String, data:Dictionary) -> void:
	if is_busy or not _accept_input:
		return
	var replacement = CompletionModel.replacement(_completion_request, input_model.caret, choice, data)
	input_model.replace(replacement.start, input_model.caret, replacement.text)
	_hide_completion()


func _hide_completion() -> void:
	_completion_generation += 1
	if _popup != null:
		_popup.cancel_pending()
