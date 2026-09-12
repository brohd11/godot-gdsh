extends RefCounted
## GDSh's script tokenizer and multiline cache. No ALib dependencies.
## Palette is structural: setup accepts GDSh and ALib palettes with the same color slots.

const STATE_NORMAL := 0
var text_edit:TextEdit
var palette
var multiline := true
var _line_states:PackedInt32Array = PackedInt32Array()
var _valid_to:int = -1


const _STATE_DQ := 1
const _STATE_SQ := 2

const _EXPECT = &"expect"

const KEYWORDS := [
	"if", "elif", "else", "while", "for", "in",
	#"return", "break", "continue", # these are actually commands...
]

## Keywords whose *next* word is a command/condition, so `if return_test {` highlights
## return_test. `for`/`in`/`return` are deliberately excluded.
const CONDITION_KEYWORDS := ["if", "elif", "while", "else"]


func _init() -> void:
	multiline = true

func _tokenize(line:int, entry_state:int, map:Dictionary) -> int:
	var text := text_edit.get_line(line)
	var n := text.length()
	var colors:Array = []
	colors.resize(n)
	for k in n:
		colors[k] = palette.text

	# Context stack seeded from the incoming state. A line that begins inside a string is not
	# in command position, matching the source's `_EXPECT: not start_in_string`.
	var stack:Array = [{
		"dq": (entry_state & _STATE_DQ) != 0,
		"sq": (entry_state & _STATE_SQ) != 0,
		_EXPECT: entry_state == STATE_NORMAL,
	}]

	var i := 0
	var after_function := false

	while i < n:
		var f:Dictionary = stack[-1]
		var c := text[i]

		# ---- single-quoted: literal, no expansion ------------------------
		if f["sq"]:
			colors[i] = palette.string
			if c == "'":
				f["sq"] = false
				f[_EXPECT] = false
			i += 1
			continue

		# ---- double-quoted: $ expands, $( opens a sub-context ------------
		if f["dq"]:
			if c == "\\" and i + 1 < n:
				colors[i] = palette.string
				colors[i + 1] = palette.string
				i += 2
				continue
			if c == "$" and i + 1 < n and text[i + 1] == "(":
				colors[i] = palette.symbol
				colors[i + 1] = palette.bracket
				stack.append({"dq": false, "sq": false, _EXPECT: true})
				i += 2
				continue
			if c == "$":
				var adv := _color_variable(text, i, colors)
				if adv > 0:
					i += adv
					continue
			colors[i] = palette.string
			if c == "\"":
				f["dq"] = false
				f[_EXPECT] = false
			i += 1
			continue

		# ---- code context ------------------------------------------------
		if c == " " or c == "\t":
			i += 1
			continue

		if c == "#" and _is_comment_start(text, i):
			for k in range(i, n):
				colors[k] = palette.comment
			break

		if c == "\"":
			colors[i] = palette.string
			f["dq"] = true
			i += 1
			continue
		if c == "'":
			colors[i] = palette.string
			f["sq"] = true
			i += 1
			continue

		if c == "$" and i + 1 < n and text[i + 1] == "(":   # command substitution
			colors[i] = palette.symbol
			colors[i + 1] = palette.bracket
			stack.append({"dq": false, "sq": false, _EXPECT: true})
			i += 2
			continue
		if c == "$":
			var v := _color_variable(text, i, colors)
			if v > 0:
				i += v
				f[_EXPECT] = false
				continue

		# multi-char operators
		var two := text.substr(i, 2)
		if two == "&&" or two == "||" or two == ";;" or two == "==" \
				or two == "!=" or two == ">>" or two == "<<":
			colors[i] = palette.string_name
			colors[i + 1] = palette.string_name
			i += 2
			if two == "&&" or two == "||" or two == ";;":
				f[_EXPECT] = true
			continue

		# single-char operators
		if c == "|" or c == ";" or c == "&":
			colors[i] = palette.string_name
			i += 1
			f[_EXPECT] = true
			continue
		if c == "=" or c == "<" or c == ">" or c == "!":
			colors[i] = palette.string_name
			i += 1
			continue

		# closing a $( ) returns to the enclosing context (its dq may resume)
		if c == ")" and stack.size() > 1:
			colors[i] = palette.bracket
			stack.pop_back()
			i += 1
			continue

		# brackets
		if c == "[" or c == "]":
			colors[i] = palette.function
			i += 1
			f[_EXPECT] = false
			continue

		if c == "{" or c == "(":
			colors[i] = palette.bracket
			i += 1
			f[_EXPECT] = true
			continue
		if c == "}" or c == ")":
			colors[i] = palette.bracket
			i += 1
			f[_EXPECT] = false
			continue

		# numbers
		if is_digit(c):
			var ns := i
			while i < n and (is_digit(text[i]) or text[i] == "."):
				i += 1
			for k in range(ns, i):
				colors[k] = palette.number
			continue

		# words: keyword / command / function / assignment / argument
		if is_identifier_start(c):
			var ws := i
			while i < n and is_identifier_char(text[i]):
				i += 1
			var word := text.substr(ws, i - ws)
			var col:Color = palette.text
			var next_expect := false

			if after_function:
				col = palette.function_def           # `function foo` style
				after_function = false
			elif word in KEYWORDS:
				col = palette.control_flow
				if word == "function":
					after_function = true
				elif word in CONDITION_KEYWORDS:
					next_expect = true           # `if cmd {`, `while cmd {`, ...
			elif f[_EXPECT]:
				if i < n and text[i] == "=" \
						and not (i + 1 < n and text[i + 1] == "="):
					col = palette.variable       # NAME=value assignment
				elif _is_function_def(text, i):
					col = palette.function_def   # name() { ... }
				else:
					col = palette.function       # command position

			for k in range(ws, i):
				colors[k] = col
			f[_EXPECT] = next_expect
			continue

		i += 1                                    # anything else

	collapse(colors, map)

	# The frame actually in effect at end of line. An unclosed $( loses its depth, which is
	# malformed input either way.
	var top:Dictionary = stack[-1]
	var state := STATE_NORMAL
	if top["dq"]:
		state |= _STATE_DQ
	if top["sq"]:
		state |= _STATE_SQ
	return state


## Color a $variable starting at [param i]. Returns chars consumed, or 0 if `$` is not a
## variable here.
func _color_variable(text:String, i:int, colors:Array) -> int:
	var n := text.length()
	if i + 1 >= n:
		return 0
	var c2 := text[i + 1]

	if c2 == "{":                                   # ${ ... }
		var j := i + 2
		while j < n and text[j] != "}":
			j += 1
		if j < n:
			j += 1
		for k in range(i, j):
			colors[k] = palette.variable
		return j - i

	if c2 == "(":                                   # $( ... ) handled by caller
		return 0

	if is_identifier_start(c2):                     # $name
		var j := i + 1
		while j < n and is_identifier_char(text[j]):
			j += 1
		for k in range(i, j):
			colors[k] = palette.variable
		return j - i

	# special parameters: $? $@ $# $$ $! $* $- $0..$9
	if c2 in ["?", "@", "#", "$", "!", "*", "-",
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		colors[i] = palette.variable
		colors[i + 1] = palette.variable
		return 2

	return 0


## True if what follows a word (skipping spaces) is "()".
func _is_function_def(text:String, after_word:int) -> bool:
	var n := text.length()
	var j := after_word
	while j < n and (text[j] == " " or text[j] == "\t"):
		j += 1
	if j >= n or text[j] != "(":
		return false
	j += 1
	while j < n and (text[j] == " " or text[j] == "\t"):
		j += 1
	return j < n and text[j] == ")"


## `#` only starts a comment at a token boundary (not mid-word like a#b).
func _is_comment_start(text:String, i:int) -> bool:
	if i == 0:
		return true
	var p := text[i - 1]
	return p == " " or p == "\t" or p == ";" or p == "|" \
			or p == "&" or p == "(" or p == "{"


func setup(p_text_edit:TextEdit, p_palette) -> void:
	text_edit = p_text_edit
	palette = p_palette
	clear_cache()

func clear_cache() -> void:
	_line_states.clear()
	_valid_to = -1

func get_line_highlighting(line:int) -> Dictionary:
	if text_edit == null or palette == null:
		return {}
	var map := {}
	_tokenize(line, _get_entry_state(line), map)
	return finalize(map)

func _get_entry_state(line:int) -> int:
	if not multiline or line <= 0 or text_edit == null:
		return STATE_NORMAL
	if line <= _valid_to:
		return _line_states[line]

	if _line_states.size() < line + 1:
		_line_states.resize(line + 1)
	if _valid_to < 0:
		_line_states[0] = STATE_NORMAL
		_valid_to = 0

	var scratch := {}
	var current := _valid_to
	while current < line:
		_line_states[current + 1] = _tokenize(current, _line_states[current], scratch)
		scratch.clear()
		current += 1
	_valid_to = line
	return _line_states[line]

static func collapse(colors:Array, map:Dictionary) -> void:
	var last:Variant = null
	for i in colors.size():
		var color:Color = colors[i]
		if last == null or color != last:
			map[i] = {"color": color}
			last = color

static func finalize(map:Dictionary) -> Dictionary:
	var columns := map.keys()
	var ordered := true
	for i in range(1, columns.size()):
		if columns[i] < columns[i - 1]:
			ordered = false
			break
	if ordered:
		return map
	columns.sort()
	var sorted := {}
	for column in columns:
		sorted[column] = map[column]
	return sorted

static func is_digit(c:String) -> bool:
	return c >= "0" and c <= "9"

static func is_identifier_start(c:String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")

static func is_identifier_char(c:String) -> bool:
	return is_identifier_start(c) or is_digit(c)
