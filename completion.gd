extends RefCounted
## A UI-independent completion request. Routing operates on an isolated context.

const Context = preload("res://addons/addon_lib/gdsh/context.gd")
const Parser = preload("res://addons/addon_lib/gdsh/internal/parser.gd")
const Expansion = preload("res://addons/addon_lib/gdsh/internal/expansion.gd")
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
var _redirect:bool = false
var _redirect_op:String = ""
var _redirect_word:Dictionary = {}

func _init(text:String, session:Context, caret:int=-1):
	raw_text = text
	_session = session
	caret_col = text.length() if caret < 0 else clampi(caret, 0, text.length())

func get_completions() -> Dictionary:
	_parse()
	if _redirect:
		return _redirect_completions()
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
	var scope = context.get_scope(first_word)
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
		context.scopes_hidden = _session.scopes_hidden.duplicate(true)
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
	var parsed = Parser.parse(prefix, true)
	var current = parsed.completion
	_current_command = prefix.substr(current.start).strip_edges(true, false)
	context.raw_text = _current_command
	char_before_cursor = prefix.right(1)
	_redirect = current.redirect
	_redirect_op = current.get("redirect_op", "")
	_redirect_word = current.get("redirect_word", {})
	var words:Array = current.words
	token_before_cursor = words.back().raw if not words.is_empty() else ""
	word_before_cursor = token_before_cursor
	# Alias definitions remain source fragments, but routing never executes them.
	var seen = {}
	while true:
		var changed = false
		var fragments:Array = []
		for word in words:
			if not word.quoted and context.aliases.has(word.raw) and not seen.has(word.raw):
				seen[word.raw] = true
				fragments.append(str(context.aliases[word.raw]).trim_prefix("@literal"))
				changed = true
			else:
				fragments.append(word.raw)
		if not changed: break
		words = Parser.parse(" ".join(fragments), true).completion.words
	var expanded = Expansion.words(words, context, true)
	context.unconsumed_tokens = expanded.values
	context._token_metadata = expanded.metadata

func _redirect_completions() -> Dictionary:
	var options = Options.new()
	options.add_option("discard")
	options.add_option("/dev/null")
	var target = ""
	if not _redirect_word.is_empty():
		target = Expansion.scalar([_redirect_word], context, true)
	if target in ["discard", "/dev/null"]:
		return options.get_options()
	var target_dir = context.cwd
	var insert_base = ""
	var leaf = ""
	if target.ends_with("/"):
		target_dir = target if target.is_absolute_path() else context.cwd.path_join(target).simplify_path()
		insert_base = target
	elif target.contains("/"):
		insert_base = target.get_base_dir()
		target_dir = insert_base if insert_base.is_absolute_path() else context.cwd.path_join(insert_base).simplify_path()
		leaf = target.get_file()
	else:
		leaf = target
	if not DirAccess.dir_exists_absolute(target_dir):
		return options.get_options()
	for name in DirAccess.get_directories_at(target_dir):
		if leaf.is_empty() or name.begins_with(leaf):
			var value = name if insert_base.is_empty() else insert_base.path_join(name)
			options.add_option(value, {&"trailing_char": "/"})
	for name in DirAccess.get_files_at(target_dir):
		if leaf.is_empty() or name.begins_with(leaf):
			var value = name if insert_base.is_empty() else insert_base.path_join(name)
			options.add_option(value)
	return options.get_options()

func in_arguments() -> bool:
	return payload_arg_index > -1

func get_current_command() -> String:
	return _current_command
