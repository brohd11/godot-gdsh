extends CodeEdit
## Single-line CodeEdit with GDSh completion and console key handling.

const CompletionPopup = preload("res://addons/addon_lib/gdsh/internal/completion_popup.gd")
const CompletionModel = preload("res://addons/addon_lib/gdsh/internal/console_completion.gd")
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
	var choices = CompletionModel.choices(_completion_request)
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


func _accept_completion(choice:String, data:Dictionary) -> void:
	var caret = get_caret_column()
	var replacement = CompletionModel.replacement(_completion_request, caret, choice, data)
	var start:int = replacement.start
	var insertion:String = replacement.text
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
