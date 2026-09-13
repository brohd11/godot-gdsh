extends SyntaxHighlighter
## Context-based console colors, adapted from editor_console's console_syntax.gd.
## Lexical spans keep highlighting literal and never evaluate shell input.

const Context = preload("res://addons/addon_lib/gdsh/context.gd")
const Lexer = preload("res://addons/addon_lib/gdsh/internal/lexer.gd")
const Utils = preload("res://addons/addon_lib/gdsh/internal/utils.gd")
const Palette = preload("res://addons/addon_lib/gdsh/internal/palette.gd")
const Expansion = preload("res://addons/addon_lib/gdsh/internal/expansion.gd")
const _COMPARISONS = ["[", "]", "==", "!="]
const _PREVIEW_LENGTH = 20
const _UNDEFINED_COLOR = Color("ff6b6b")

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


## BBCode for a submitted line, painted with the input colors. With show_values,
## variables and aliases are prefixed by a grey [value] preview. Previews read
## values only; substitutions are never evaluated and raw arguments get none.
func to_bbcode(source:String, show_values:=false) -> String:
	_build_colors(source)
	_valid = false # The color cache belongs to the input text, not this line.
	var previews = {}
	if show_values and context != null:
		var raw_names:Array[String] = context.raw_commands
		_collect_previews(Lexer.scan(source, true, raw_names).tokens, previews)
	var out = ""
	var run_start = 0
	for index in source.length() + 1:
		var at_end = index == source.length()
		if index > run_start and (at_end or previews.has(index) or _colors[index] != _colors[run_start]):
			out += Utils.color_text(source.substr(run_start, index - run_start), _colors[run_start])
			run_start = index
		if not at_end and previews.has(index):
			out += previews[index]
	return out


func _collect_previews(tokens:Array, previews:Dictionary) -> void:
	for token in tokens:
		if token.kind != "word":
			continue
		if not token.quoted and context.aliases.has(token.raw):
			previews[token.start] = _preview(str(context.aliases[token.raw]).trim_prefix("@literal").strip_edges())
		for part in token.parts:
			if part.kind == "variable":
				previews[part.start] = _preview(Expansion.variable(part.value, context, true)) \
						if _known_variable(part.value) else _preview("undef", true)
			elif part.kind == "substitution":
				_collect_previews(part.tokens, previews)


func _preview(value:String, undefined:=false) -> String:
	value = value.replace("\n", " ")
	if value.length() > _PREVIEW_LENGTH:
		value = value.left(_PREVIEW_LENGTH) + "…"
	var bracket = palette.unknown_variable.to_html(false)
	var color = _UNDEFINED_COLOR if undefined else palette.text
	return "[color=%s][lb][/color]%s[color=%s]][/color]" % [bracket, Utils.color_text(value, color), bracket]


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
