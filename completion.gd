extends RefCounted
## A UI-independent completion request. Routing operates on an isolated context.

const Context = preload("res://addons/addon_lib/gdsh/context.gd")
const Tokenizer = preload("res://addons/addon_lib/gdsh/internal/tokenizer.gd")
const Options = preload("res://addons/addon_lib/gdsh/options.gd")
const Types = preload("res://addons/addon_lib/gdsh/internal/types.gd")

var raw_text:String
var caret_col:int
var char_before_cursor:String
var word_before_cursor:String
var token_before_cursor:String
var positional_args:Array = []
var positional_arg_index:int = -1
var payload_args:Array = []
var payload_arg_index:int = -1
var context:Context
var show_commands:bool = true
var show_flags:bool = true

var _session:Context
var _current_command:String

func _init(text:String, session:Context, caret:int=-1):
	raw_text = text
	_session = session
	caret_col = text.length() if caret < 0 else clampi(caret, 0, text.length())

func get_completions() -> Dictionary:
	_parse()
	var options = Options.new()
	if token_before_cursor.begins_with("@") and not char_before_cursor in [" ", "\t"]:
		for name in context.aliases:
			options.add_option(name, {&"insert": name})
		return options.get_options()
	if token_before_cursor.begins_with("$") and not token_before_cursor.begins_with("$(") and not char_before_cursor in [" ", "\t"]:
		for name in context.variables:
			options.add_option(name)
		return options.get_options()

	var first_word = context.unconsumed_tokens.front() if not context.unconsumed_tokens.is_empty() else ""
	var scope = context.scopes.get(first_word)
	if scope == null:
		if show_commands:
			for name:String in context.scopes:
				if not name.begins_with("__"):
					options.add_option(name)
			for name in context.functions:
				options.add_option(name, {&"insert": name})
		return options.get_options()
	if context.functions.has(first_word):
		return {}
	var command = scope.get(Types.ScopeDataKeys.SCRIPT)
	if command is GDScript:
		command = command.new()
	if not is_instance_valid(command) or not command.has_method("complete"):
		return {}
	var result = command.complete(self)
	if result == null:
		return {}
	if result is Object and result.has_method("get_options"):
		result = result.get_options()
	if not result is Dictionary:
		push_error("GDSh.Completion: expected an options dictionary")
		return {}
	options.set_options(result)
	var meta = result.get(Options.Keys.COMMAND_META, {})
	if payload_arg_index > -1:
		options.remove_option(Options.ARG_DELIMITER)
		if meta.get(Options.Keys.SHOW_VARIABLES, false):
			for name in context.variables:
				options.add_option(name)
	var output = options.get_options()
	for name in output.keys():
		if name == Options.Keys.COMMAND_META:
			continue
		if output[name].has(&"get_command"):
			if not show_commands:
				output.erase(name)
		elif not show_flags:
			output.erase(name)
	return output

func _parse():
	context = Context.new("", false)
	if _session != null:
		context.cwd = _session.cwd
		context.variables = _session.variables.duplicate(true)
		context.aliases = _session.aliases.duplicate(true)
		context.functions = _session.functions.duplicate(true)
		context.scopes = _session.scopes.duplicate(true)
		context.data = _session.data.duplicate(true)
		context.positional_args = _session.positional_args.duplicate(true)
		context.stdin = _session.stdin
		context.last_status = _session.last_status
	context.execute = false
	positional_args = []
	positional_arg_index = -1
	payload_args = []
	payload_arg_index = -1
	var prefix = raw_text.left(clampi(caret_col, 0, raw_text.length()))
	_current_command = _command_at_caret(prefix)
	context.raw_text = _current_command
	char_before_cursor = prefix.right(1)
	var tokenizer = Tokenizer.new(context)
	var tokens = tokenizer.parse_command_string_completion(_current_command)
	context.unconsumed_tokens = Array(tokens.expanded)
	var typed = Array(tokens.commands)
	var split = Tokenizer.split_args(_current_command)
	if split[0] != _current_command:
		context.unconsumed_tokens.append("--")
		context.unconsumed_tokens.append_array(tokens.args)
		payload_args = Array(tokens.args)
		typed.append_array(tokens.raw_args)
	token_before_cursor = typed.back() if not typed.is_empty() else ""
	word_before_cursor = token_before_cursor

func in_arguments() -> bool:
	return payload_arg_index > -1

func get_current_command() -> String:
	return _current_command

## Find the last top-level separator; quoted text and substitutions are kept intact.
static func _command_at_caret(prefix:String) -> String:
	var start = 0
	var quote = ""
	var escaped = false
	var depth = 0
	for i in prefix.length():
		var ch = prefix[i]
		if escaped:
			escaped = false
			continue
		if ch == "\\" and quote != "'":
			escaped = true
			continue
		if quote != "":
			if ch == quote:
				quote = ""
			continue
		if ch in ["'", '"']:
			quote = ch
		elif ch == "(":
			depth += 1
		elif ch == ")":
			depth = maxi(0, depth - 1)
		elif depth == 0 and ch in ["|", ";", "\n"]:
			start = i + 1
		elif depth == 0 and ch == "&" and i > 0 and prefix[i - 1] == "&":
			start = i + 1
	return prefix.substr(start).strip_edges(true, false)
