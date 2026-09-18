extends RefCounted
## Compatibility helpers backed by the shared lexer, parser, and word expansion.
const Lexer = preload("res://addons/addon_lib/gdsh/src/core/lexer.gd")
const Parser = preload("res://addons/addon_lib/gdsh/src/core/parser.gd")
const Expansion = preload("res://addons/addon_lib/gdsh/src/core/expansion.gd")
var active_ctx
var execute:bool = false

func _init(ctx):
	active_ctx = ctx

static func raw_tokens(text:String) -> PackedStringArray:
	var output = PackedStringArray()
	for token in Lexer.scan(text, true).tokens:
		if token.kind != "eof": output.append(token.raw)
	return output

func parse_command_string_execute(text:String) -> Dictionary:
	return _parse(text, false)

func parse_command_string_completion(text:String, allow_expand:=true) -> Dictionary:
	return _parse(text, true, allow_expand)

func _parse(text:String, completion:bool, allow_expand:=true) -> Dictionary:
	var parsed = Parser.parse(text, completion)
	var words:Array = parsed.completion.words if parsed.error.is_empty() or completion else []
	var raw:Array = []
	for word in words: raw.append(word.raw)
	var expanded = Expansion.words(words, active_ctx, completion) if allow_expand else {"values": raw, "metadata": []}
	return {"commands": raw, "expanded": expanded.values, "metadata": expanded.metadata, "error": parsed.error}

static func check_variable(name:String, ctx) -> String:
	return Expansion.variable(name, ctx, not ctx.execute)
