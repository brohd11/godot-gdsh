extends CodeEdit
## Single-line CodeEdit with GDSh completion and console key handling.

const Completion = preload("res://addons/addon_lib/gdsh/completion.gd")
const Options = preload("res://addons/addon_lib/gdsh/options.gd")
const ConsoleHighlighter = preload("res://addons/addon_lib/gdsh/internal/console_highlighter.gd")

signal submit_requested(text:String)
signal history_requested(direction:int)

const _DEBOUNCE_SECONDS = 0.1

var context
var _timer:Timer
var _popup:CompletionPopup
var _completion_request:Completion
var _normalizing_text:=false


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

	syntax_highlighter = ConsoleHighlighter.new()
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
		text = text.replace("\r\n", " ").replace("\n", " ").replace("\r", " ")
		set_caret_column(mini(caret, text.length()))
		_normalizing_text = false
	if _timer != null:
		_timer.start()


func request_completion(force:=true) -> void:
	if context == null or text.is_empty() and not force:
		_hide_completion()
		return
	_completion_request = Completion.new(text, context, get_caret_column())
	var choices = _completion_request.get_completions().duplicate(true)
	choices.erase(Options.Keys.COMMAND_META)
	var needle = "" if _completion_request.char_before_cursor in ["", " ", "\t", "\n"] \
			else _completion_request.token_before_cursor
	_filter_choices(choices, needle)
	if choices.is_empty():
		_hide_completion()
		return
	if _popup == null:
		_popup = CompletionPopup.new()
		_popup.choice_accepted.connect(_accept_completion)
		add_child(_popup)
	_popup.set_choices(choices)
	_popup.position_for_caret(self)


func _filter_choices(choices:Dictionary, needle:String) -> void:
	if needle.length() < 2:
		return
	for choice in choices.keys():
		if choice == Options.Keys.COMMAND_META or needle.is_subsequence_ofn(str(choice)):
			continue
		choices.erase(choice)


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


func _on_gui_input(event:InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var popup_visible = _popup != null and _popup.visible
	match event.keycode:
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


func _hide_completion() -> void:
	if _popup != null:
		_popup.hide()


class CompletionPopup extends PanelContainer:
	signal choice_accepted(choice:String, data:Dictionary)

	var _items = ItemList.new()
	var _choices:Array = []


	func _init() -> void:
		visible = false
		z_index = 100
		mouse_filter = Control.MOUSE_FILTER_STOP
		_items.focus_mode = Control.FOCUS_NONE
		_items.auto_height = true
		_items.item_activated.connect(_on_item_activated)
		add_child(_items)


	func set_choices(choices:Dictionary) -> void:
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
		visible = true
		reset_size()


	func position_for_caret(edit:CodeEdit) -> void:
		var caret_pos = edit.get_pos_at_line_column(edit.get_caret_line(), edit.get_caret_column())
		var width = clampf(size.x, 180.0, maxf(180.0, edit.size.x))
		var height = minf(maxf(size.y, 24.0), 240.0)
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
				_items.ensure_current_is_visible()
				return


	func _on_item_activated(index:int) -> void:
		choice_accepted.emit(str(_choices[index]), _items.get_item_metadata(index))
