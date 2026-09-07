extends SyntaxHighlighter
## Runtime wrapper around the GDSh tokenizer highlighter.

const GDShHighlighter = preload("res://addons/addon_lib/brohd/alib_runtime/misc/syntax_highlighters/text/types/gdsh_highlighter.gd")
const Palette = preload("res://addons/addon_lib/brohd/alib_runtime/misc/syntax_highlighters/text/palette.gd")

var palette = Palette.new()
var _highlighter = GDShHighlighter.new()


func _bind() -> void:
	var edit = get_text_edit()
	if edit != null:
		_highlighter.setup(edit, palette)


func _get_line_syntax_highlighting(line:int) -> Dictionary:
	_bind()
	return _highlighter.get_line_highlighting(line)


func _clear_highlighting_cache() -> void:
	_highlighter.clear_cache()


func _update_cache() -> void:
	_bind()
