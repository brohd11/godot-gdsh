extends CodeEdit
## Single-line CodeEdit with GDSh completion and console key handling.

const Completion = preload("res://addons/addon_lib/gdsh/completion.gd")
const Options = preload("res://addons/addon_lib/gdsh/options.gd")
const ConsoleHighlighter = preload("res://addons/addon_lib/gdsh/internal/console_highlighter.gd")
const SourceFont = preload("res://addons/addon_lib/gdsh/internal/source_font.tres")

signal submit_requested(text:String)
signal history_requested(direction:int)

const _DEBOUNCE_SECONDS = 0.1
## Ctrl+Backspace stops at these, so path segments and flag values delete separately.
const _WORD_DELIMITERS = [" ", ".", "/", "'", '"', "="]

var completion_factory:Callable

var context:
	set(value):
		context = value
		refresh_highlighting()
var _timer:Timer
var _popup:CompletionPopup
var _completion_request:Completion
var _normalizing_text:=false
var _completion_generation:=0


func _init() -> void:
	syntax_highlighter = ConsoleHighlighter.new()


func set_highlighter(value:SyntaxHighlighter) -> void:
	syntax_highlighter = value
	refresh_highlighting()


func refresh_highlighting() -> void:
	if syntax_highlighter == null:
		return
	if syntax_highlighter.has_method("set_context"):
		syntax_highlighter.set_context(context)
	syntax_highlighter.clear_highlighting_cache()


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caret_blink = true
	auto_brace_completion_enabled = true
	code_completion_enabled = false
	wrap_mode = TextEdit.LINE_WRAPPING_NONE
	
	scroll_fit_content_height = true
	minimap_draw = false
	gutters_draw_line_numbers = false
	gutters_draw_fold_gutter = false
	gutters_draw_breakpoints_gutter = false
	add_theme_constant_override("line_spacing", 0)
	for style in ["normal", "read_only", "focus"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())

	text_changed.connect(_on_text_changed)
	gui_input.connect(_on_gui_input)
	focus_exited.connect(_hide_completion)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = _DEBOUNCE_SECONDS
	_timer.timeout.connect(request_completion.bind(false))
	add_child(_timer)


func _on_text_changed() -> void:
	if not _normalizing_text and "\n" in text:
		_normalizing_text = true
		var caret = get_caret_column()
		text = text.replace("\r\n", "; ").replace("\n", "; ").replace("\r", "; ")
		set_caret_column(mini(caret, text.length()))
		_normalizing_text = false
	if _timer != null:
		_timer.start()


func request_completion(force:=true) -> void:
	_completion_generation += 1
	var generation = _completion_generation
	if context == null or text.is_empty() and not force:
		_hide_completion()
		return
	_completion_request = completion_factory.call(text, context, get_caret_column()) if completion_factory.is_valid() \
			else Completion.new(text, context, get_caret_column())
	var choices = _completion_request.get_completions().duplicate(true)
	choices.erase(Options.Keys.COMMAND_META)
	var needle = "" if _completion_request.char_before_cursor in ["", " ", "\t", "\n"] \
			else _completion_request.token_before_cursor
	_filter_choices(choices, needle)
	_clean_up_separators(choices)
	if choices.is_empty():
		_hide_completion()
		return
	if _popup == null:
		_popup = CompletionPopup.new()
		_popup.choice_accepted.connect(_accept_completion)
		add_child(_popup)
	if await _popup.set_choices(choices, generation):
		if generation == _completion_generation:
			_popup.position_for_caret(self)


func _filter_choices(choices:Dictionary, needle:String) -> void:
	if needle.length() < 2:
		return
	for choice in choices.keys():
		if choice == Options.Keys.COMMAND_META or Options.Keys.get_seperator(str(choice)) != null:
			continue
		var metadata:Dictionary = choices[choice].get(Options.Keys.METADATA, {})
		if needle.is_subsequence_ofn(str(choice)) \
				or needle.is_subsequence_ofn(str(metadata.get(Options.Keys.INSERT, choice))):
			continue
		choices.erase(choice)


func _clean_up_separators(choices:Dictionary) -> void:
	var keys = choices.keys()
	keys.reverse()
	var has_choice := false
	for choice in keys:
		if Options.Keys.get_seperator(str(choice)) != null:
			if not has_choice:
				choices.erase(choice)
			has_choice = false
		else:
			has_choice = true


func _accept_completion(choice:String, data:Dictionary) -> void:
	var metadata:Dictionary = data.get(Options.Keys.METADATA, {})
	var insertion = str(metadata.get(Options.Keys.INSERT, choice))
	insertion += str(metadata.get(Options.Keys.TRAILING_CHAR, " "))
	var caret = get_caret_column()
	var start = caret
	if metadata.get(Options.Keys.REPLACE_WORD, true) and _completion_request != null \
			and not _completion_request.char_before_cursor in ["", " ", "\t", "\n"]:
		start = maxi(0, caret - _completion_request.token_before_cursor.length())
	begin_complex_operation()
	text = text.erase(start, caret - start).insert(start, insertion)
	set_caret_column(start + insertion.length())
	end_complex_operation()
	_hide_completion()
	_on_text_changed()


func _shortcut_input(event:InputEvent) -> void:
	if event is InputEventKey and has_focus():
		get_viewport().set_input_as_handled()


func _on_gui_input(event:InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	if event.as_text_keycode() == "Ctrl+Backspace": # Repeats while held, like native deletion.
		delete_word_before_caret()
		accept_event()
		return
	var popup_visible = _popup != null and _popup.visible
	if event.echo and not (popup_visible and event.keycode in [KEY_UP, KEY_DOWN]):
		return
	match event.keycode:
		KEY_LEFT, KEY_RIGHT:
			if popup_visible: # The caret still moves.
				_hide_completion()
		KEY_ENTER, KEY_KP_ENTER:
			_hide_completion()
			submit_requested.emit(text)
			accept_event()
		KEY_TAB:
			if popup_visible and _popup.has_selection():
				_popup.accept_selected()
			else:
				request_completion(true)
			accept_event()
		KEY_UP:
			if popup_visible:
				_popup.select_previous()
			else:
				history_requested.emit(-1)
			accept_event()
		KEY_DOWN:
			if popup_visible:
				_popup.select_next()
			else:
				history_requested.emit(1)
			accept_event()
		KEY_ESCAPE:
			if popup_visible:
				_hide_completion()
				accept_event()


func delete_word_before_caret() -> void:
	var caret = get_caret_column()
	var before = text.left(caret).strip_edges(false, true)
	# A trailing delimiter belongs to the word being deleted.
	if not before.is_empty() and before.right(1) in _WORD_DELIMITERS:
		before = before.left(-1)
	var start = 0
	for delimiter in _WORD_DELIMITERS:
		start = maxi(start, before.rfind(delimiter) + 1)
	begin_complex_operation()
	text = text.erase(start, caret - start)
	set_caret_column(start)
	end_complex_operation()
	_on_text_changed()


func _hide_completion() -> void:
	_completion_generation += 1
	if _popup != null:
		_popup.cancel_pending()


class CompletionPopup extends ScrollContainer:
	signal choice_accepted(choice:String, data:Dictionary)

	var _items = ItemList.new()
	var _choices:Array = []
	var _choices_hash:int
	var _generation:int


	func _init() -> void:
		visible = false
		z_index = 100
		mouse_filter = Control.MOUSE_FILTER_STOP
		_items.focus_mode = Control.FOCUS_NONE
		_items.auto_height = true
		_items.auto_width = true
		_items.max_columns = 1
		_items.add_theme_font_override("font", SourceFont)
		_items.item_activated.connect(_on_item_activated)
		add_child(_items)


	func set_choices(choices:Dictionary, generation:int) -> bool:
		_generation = generation
		var new_hash = choices.hash()
		modulate.a = 0.0
		show() # Invisible but participating in layout while ItemList measures itself.
		if new_hash != _choices_hash:
			_choices_hash = new_hash
			custom_minimum_size = Vector2.ZERO
			size = Vector2.ZERO
			_items.custom_minimum_size = Vector2.ZERO
			_choices = choices.keys()
			_items.clear()
			for choice in _choices:
				var data:Dictionary = choices[choice]
				var separator = Options.Keys.get_seperator(str(choice))
				if separator != null:
					_items.add_item(separator)
					_items.set_item_disabled(_items.item_count - 1, true)
					_items.set_item_metadata(_items.item_count - 1, data)
					continue
				var icon = data.get(Options.Keys.ICON)
				if icon is Array and not icon.is_empty():
					icon = icon[0]
				_items.add_item(str(choice), icon if icon is Texture2D else null)
				_items.set_item_metadata(_items.item_count - 1, data)
			for index in _items.item_count:
				if not _items.is_item_disabled(index):
					_items.select(index)
					break
		await get_tree().process_frame
		if generation != _generation:
			return false
		var measured = _items.get_combined_minimum_size()
		# A ScrollContainer can clamp both the current rect and reported minimum to
		# its previous viewport. Measure each single-column row so growth and
		# shrinkage do not depend on a later container layout pass.
		var content_height = 0.0
		var font = _items.get_theme_font("font")
		var font_size = _items.get_theme_font_size("font_size")
		var minimum_row_height = maxf(24.0, font.get_height(font_size) \
				+ _items.get_theme_constant("v_separation"))
		for index in _items.item_count:
			var item_rect = _items.get_item_rect(index)
			measured.x = maxf(measured.x, item_rect.end.x)
			var item_height = maxf(item_rect.size.y, minimum_row_height)
			var icon = _items.get_item_icon(index)
			if icon != null:
				item_height = maxf(item_height, icon.get_height())
			content_height += item_height
		var panel = _items.get_theme_stylebox("panel")
		content_height += panel.get_margin(SIDE_TOP) + panel.get_margin(SIDE_BOTTOM)
		measured.y = maxf(measured.y, content_height)
		var max_height = get_window().size.y * 0.5
		_items.custom_minimum_size = measured
		custom_minimum_size = Vector2(measured.x, minf(measured.y, max_height))
		size = custom_minimum_size
		show()
		modulate.a = 1.0
		_scroll_to_selection_after_layout(generation)
		return true


	func cancel_pending() -> void:
		_generation += 1
		hide()


	func position_for_caret(edit:CodeEdit) -> void:
		var caret_pos = edit.get_pos_at_line_column(edit.get_caret_line(), edit.get_caret_column())
		var width = clampf(size.x, 180.0, maxf(180.0, edit.size.x))
		var height = maxf(size.y, 24.0)
		size = Vector2(width, height)
		position = Vector2(clampf(caret_pos.x, 0.0, maxf(0.0, edit.size.x - width)), -height)


	func has_selection() -> bool:
		return not _items.get_selected_items().is_empty()


	func accept_selected() -> void:
		var selected = _items.get_selected_items()
		if not selected.is_empty():
			_on_item_activated(selected[0])


	func select_next() -> void:
		_select_offset(1)


	func select_previous() -> void:
		_select_offset(-1)


	func _select_offset(offset:int) -> void:
		if _items.item_count == 0:
			return
		var selected = _items.get_selected_items()
		var index = selected[0] if not selected.is_empty() else 0
		for unused in _items.item_count:
			index = posmod(index + offset, _items.item_count)
			if not _items.is_item_disabled(index):
				_items.select(index)
				_scroll_to_selection()
				return


	func _scroll_to_selection_after_layout(generation:int) -> void:
		await get_tree().process_frame
		if generation == _generation:
			_scroll_to_selection()


	func _scroll_to_selection() -> void:
		if not visible or not has_selection():
			return
		# The auto-height ItemList fills the content; the outer container scrolls it.
		# Its row bounds already include the list panel's margin and share the
		# container's unscrolled content origin, independent of pending layout.
		var row = _items.get_item_rect(_items.get_selected_items()[0])
		var bar = get_v_scroll_bar()
		var target = float(scroll_vertical)
		if row.position.y < target or row.size.y > bar.page:
			target = floorf(row.position.y)
		elif row.end.y > target + bar.page:
			target = ceilf(row.end.y - bar.page)
		scroll_vertical = int(clampf(target, bar.min_value, maxf(bar.min_value, bar.max_value - bar.page)))


	func _on_item_activated(index:int) -> void:
		choice_accepted.emit(str(_choices[index]), _items.get_item_metadata(index))
