extends SyntaxHighlighter
## SyntaxHighlighter wrapper around GDSh's self-contained script tokenizer.

const Palette = preload("res://addons/addon_lib/gdsh/src/ui/palette.gd")
const Logic = preload("res://addons/addon_lib/gdsh/src/ui/script_highlighter_logic.gd")

var palette := Palette.new()
var _highlighter = Logic.new()


func set_palette(value:Palette) -> void:
	palette = value if value != null else Palette.new()
	if _highlighter.text_edit != null:
		_highlighter.setup(_highlighter.text_edit, palette)
	clear_highlighting_cache()


func _bind() -> void:
	var edit = get_text_edit()
	if edit != null and _highlighter.text_edit != edit:
		_highlighter.setup(edit, palette)


func _get_line_syntax_highlighting(line:int) -> Dictionary:
	_bind()
	return _highlighter.get_line_highlighting(line)


func _clear_highlighting_cache() -> void:
	_highlighter.clear_cache()


func _update_cache() -> void:
	_highlighter.clear_cache()
	_bind()
