extends SyntaxHighlighter
## Script-oriented ALib tokenizer adapted to the shared GDSh palette.

const Palette = preload("res://addons/addon_lib/gdsh/internal/palette.gd")
const GDShHighlighter = preload("res://addons/addon_lib/brohd/alib_runtime/misc/syntax_highlighters/text/types/gdsh_highlighter.gd")
const ALibPalette = preload("res://addons/addon_lib/brohd/alib_runtime/misc/syntax_highlighters/text/palette.gd")
const _SCRIPT_SLOTS = [
	"text", "comment", "string", "number", "control_flow", "function", "function_def",
	"variable", "string_name", "symbol", "bracket",
]

var palette := Palette.new()
var _highlighter = GDShHighlighter.new()
var _script_palette = ALibPalette.new()


func _init() -> void:
	_copy_palette()


func set_palette(value:Palette) -> void:
	palette = value if value != null else Palette.new()
	_copy_palette()
	clear_highlighting_cache()


func _copy_palette() -> void:
	for slot in _SCRIPT_SLOTS:
		_script_palette.set(slot, palette.get(slot))


func _bind() -> void:
	var edit = get_text_edit()
	if edit != null and _highlighter.text_edit != edit:
		_highlighter.setup(edit, _script_palette)


func _get_line_syntax_highlighting(line:int) -> Dictionary:
	_bind()
	return _highlighter.get_line_highlighting(line)


func _clear_highlighting_cache() -> void:
	_highlighter.clear_cache()


func _update_cache() -> void:
	_highlighter.clear_cache()
	_bind()
