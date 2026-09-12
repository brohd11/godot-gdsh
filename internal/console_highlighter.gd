extends SyntaxHighlighter
## Context-based console colors, adapted from editor_console's console_syntax.gd.
## Lexical spans keep highlighting literal and never evaluate shell input.

const Context = preload("res://addons/addon_lib/gdsh/context.gd")
const Lexer = preload("res://addons/addon_lib/gdsh/internal/lexer.gd")
const Utils = preload("res://addons/addon_lib/gdsh/internal/utils.gd")
const Palette = preload("res://addons/addon_lib/gdsh/internal/palette.gd")
const _COMPARISONS = ["[", "]", "==", "!="]

var palette := Palette.new()
var context:Context
var highlight_globals:bool = false:
	set(value):
		highlight_globals = value
		clear_highlighting_cache()

var _source := ""
var _colors := PackedColorArray()
var _line_offsets := PackedInt32Array()
var _valid := false


func set_palette(value:Palette) -> void:
	palette = value if value != null else Palette.new()
	clear_highlighting_cache()


func set_context(value:Context) -> void:
	context = value
	clear_highlighting_cache()


func _clear_highlighting_cache() -> void:
	_valid = false


func _update_cache() -> void:
	_valid = false


func _get_line_syntax_highlighting(line:int) -> Dictionary:
	var edit = get_text_edit()
	if edit == null:
		return {}
	var source = edit.text
	if not _valid or source != _source:
		_build_colors(source)
	var result = {0: {"color": palette.text}}
	var offset = _line_offsets[line]
	var previous:Color = palette.text
	for column in edit.get_line(line).length():
		var color = _colors[offset + column]
		if color != previous:
			result[column] = {"color": color}
			previous = color
	return result


func _build_colors(source:String) -> void:
	_source = source
	_colors.resize(source.length())
	_colors.fill(palette.text)
	_line_offsets = PackedInt32Array([0])
	for index in source.length():
		if source[index] == "\n":
			_line_offsets.append(index + 1)
	var globals = Utils.get_all_global_class_paths() if highlight_globals else {}
	_color_tokens(Lexer.scan(source, true).tokens, globals)
	_valid = true


func _paint(start:int, end:int, color:Color) -> void:
	for index in range(start, end):
		_colors[index] = color


func _color_tokens(tokens:Array, globals:Dictionary) -> void:
	for token in tokens:
		if token.kind == "eof":
			continue
		if token.kind != "word":
			_paint(token.start, token.end, palette.symbol)
			continue
		if not token.quoted:
			_color_name(token, globals)
		for part in token.parts:
			if part.kind == "variable":
				var color = palette.variable if _known_variable(part.value) else palette.unknown_variable
				_paint(part.start, part.end, color)
			elif part.kind == "substitution":
				_paint(part.start, part.start + 2, palette.symbol)
				_color_tokens(part.tokens, globals)
				if part.closed:
					_paint(part.end - 1, part.end, palette.symbol)


func _color_name(token:Dictionary, globals:Dictionary) -> void:
	var name:String = token.raw
	if name in _COMPARISONS:
		_paint(token.start, token.end, palette.symbol)
	elif context != null and context.functions.has(name):
		_paint(token.start, token.end, palette.function_def)
	elif context != null and context.has_scope(name):
		_paint(token.start, token.end, palette.scope)
	elif context != null and context.aliases.has(name):
		_paint(token.start, token.end, palette.alias)
	elif globals.has(name.get_slice(".", 0)):
		_paint(token.start, token.start + name.get_slice(".", 0).length(), palette.global_class)


func _known_variable(name:String) -> bool:
	if context == null:
		return false
	if context.variables.has(name) or name in ["$?", "$#", "$@"]:
		return true
	var index = name.trim_prefix("$")
	return index.is_valid_int() and index.to_int() > 0 and index.to_int() <= context.positional_args.size()
