extends RefCounted
## Parse complete input before executing its tree. Only selected nodes expand words.

const Context = preload("res://addons/addon_lib/gdsh/context.gd")
const Types = preload("res://addons/addon_lib/gdsh/internal/types.gd")
const Parser = preload("res://addons/addon_lib/gdsh/internal/parser.gd")
const Lexer = preload("res://addons/addon_lib/gdsh/internal/lexer.gd")
const Expansion = preload("res://addons/addon_lib/gdsh/internal/expansion.gd")
const _IS_LOOP_KEY = "__is_loop__"
const _LOOP_BREAK_KEY = "__loop_break__"
const _LOOP_CONTINUE_KEY = "__loop_continue__"

static func execute_command_multiline(text:String, ctx:Context=null):
	if ctx == null: ctx = Context.new()
	if ctx.exit_requested: return ctx
	var parsed = Parser.parse(text, false, ctx.raw_commands)
	if not parsed.error.is_empty():
		_parse_error(ctx, parsed.error)
		return ctx
	return _execute_tree(parsed.tree, ctx)

static func execute_command(text:String, params:Dictionary={}):
	var ctx = params.get("parent_ctx")
	if ctx == null: ctx = Context.new()
	if params.get("sub_shell", false): ctx = Context.new_ctx("Subshell", ctx, true)
	return execute_command_multiline(text, ctx)

static func source_file(file_path:String, parent_ctx:Context=null):
	if parent_ctx == null: parent_ctx = Context.new()
	if not file_path.is_absolute_path():
		file_path = parent_ctx.cwd.path_join(file_path).simplify_path()
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		parent_ctx.append_error("Cannot open GDSh script: " + file_path)
		_set_status(parent_ctx, Types.ExitCode.FAIL)
		return parent_ctx
	var text = file.get_as_text()
	if not text.strip_edges(true, false).begins_with("#!gdsh"):
		parent_ctx.append_error("Not a gdsh script: " + file_path)
		_set_status(parent_ctx, Types.ExitCode.FAIL)
		return parent_ctx
	return execute_command_multiline(text, parent_ctx)

static func _parse_error(ctx:Context, error:Dictionary):
	ctx.append_error("GDSh syntax error at %d:%d: %s" % [error.line, error.column, error.message])
	_set_status(ctx, Types.ExitCode.ERR)

static func _set_status(ctx:Context, status:int):
	ctx.last_status = status
	if not ctx.exit_requested: ctx.exit_code = status

static func _execute_tree(tree:Dictionary, ctx:Context, aliases:Dictionary={}):
	if not ctx.exit_requested:
		_run(tree, ctx, aliases)
	if not ctx.exit_requested:
		ctx.exit_code = ctx.last_status
	return ctx

static func _stopped(ctx:Context) -> bool:
	if ctx.exit_requested: return true
	var chain = ctx.get_inherited_ctxs()
	chain.push_front(ctx)
	for parent in chain:
		if parent.data.has(Types.RETURN_KEY): return true
		if parent.data.get(_LOOP_BREAK_KEY, false) or parent.data.get(_LOOP_CONTINUE_KEY, false): return true
	return false

static func _run(node:Dictionary, ctx:Context, aliases:Dictionary):
	if _stopped(ctx) or node.is_empty(): return
	# Capture output without creating a new variable scope. Nested commands inherit
	# the surrounding destination unless their own redirections route a stream.
	var previous_out = ctx.stdout
	var previous_err = ctx.stderr
	var previous_in = ctx.stdin
	ctx.stdout = ""
	ctx.stderr = ""
	var redirects = _prepare_redirections(node.get("redirs", []), ctx)
	# Expansion/open diagnostics always remain visible on the invoking stderr.
	var setup_errors = ctx.stderr
	ctx.stderr = ""
	if redirects.ok:
		if redirects.stdin_route >= 0:
			ctx.stdin = redirects.stdin
		_run_inner(node, ctx, aliases)
	else:
		_set_status(ctx, Types.ExitCode.FAIL)
	var output = ctx.stdout
	var errors = ctx.stderr
	ctx.stdin = previous_in
	var write_errors = ""
	if redirects.ok and redirects.stdout_route >= 0 and redirects.stdout_route == redirects.stderr_route:
		write_errors += _write_redirect(redirects.routes[redirects.stdout_route], output + errors)
		output = ""
		errors = ""
	elif redirects.ok:
		if redirects.stdout_route >= 0:
			write_errors += _write_redirect(redirects.routes[redirects.stdout_route], output)
			output = ""
		if redirects.stderr_route >= 0:
			write_errors += _write_redirect(redirects.routes[redirects.stderr_route], errors)
			errors = ""
	_close_redirections(redirects)
	if not write_errors.is_empty():
		_set_status(ctx, Types.ExitCode.FAIL)
	ctx.stdout = previous_out + output
	ctx.stderr = previous_err + setup_errors + errors + write_errors

static func _prepare_redirections(redirs:Array, ctx:Context) -> Dictionary:
	var result = {
		"ok": true,
		"routes": [],
		"stdin_route": -1,
		"stdout_route": -1,
		"stderr_route": -1,
		"stdin": "",
	}
	for redirect in redirs:
		var values = Expansion.word_values(redirect.target, ctx)
		if values.size() != 1 or str(values[0]).is_empty():
			ctx.append_error("GDSh redirection: target must expand to exactly one non-empty path")
			result.ok = false
			return result
		var target:String = str(values[0])
		var discard = target in ["discard", "/dev/null"]
		var path = target if discard or target.is_absolute_path() else ctx.cwd.path_join(target).simplify_path()
		var route = {"discard": discard, "path": path, "file": null}
		if not discard:
			var mode = FileAccess.READ if redirect.stdin else FileAccess.WRITE
			if redirect.append and FileAccess.file_exists(path):
				mode = FileAccess.READ_WRITE
			route.file = FileAccess.open(path, mode)
			if route.file == null:
				ctx.append_error("GDSh redirection: cannot open '%s' (error %s)" % [path, FileAccess.get_open_error()])
				result.ok = false
				return result
			if redirect.append:
				route.file.seek_end()
		result.routes.append(route)
		var route_index = result.routes.size() - 1
		if redirect.stdin: result.stdin_route = route_index
		if redirect.stdout: result.stdout_route = route_index
		if redirect.stderr: result.stderr_route = route_index
	if result.stdin_route >= 0:
		var input_route = result.routes[result.stdin_route]
		if not input_route.discard:
			result.stdin = input_route.file.get_as_text()
	return result

static func _write_redirect(route:Dictionary, content:String) -> String:
	if route.discard or content.is_empty(): return ""
	if route.file.store_string(content): return ""
	return "GDSh redirection: cannot write '%s'\n" % route.path

static func _close_redirections(redirects:Dictionary):
	for route in redirects.routes:
		if route.file != null:
			route.file.close()

static func _run_inner(node:Dictionary, ctx:Context, aliases:Dictionary):
	match node.kind:
		"list":
			for item in node.items:
				if _stopped(ctx): break
				_run(item, ctx, aliases)
		"logical":
			_run(node.first, ctx, aliases)
			for link in node.links:
				if _stopped(ctx): break
				if (link.op == "&&" and ctx.last_status == 0) or (link.op == "||" and ctx.last_status != 0):
					_run(link.node, ctx, aliases)
		"pipeline":
			_pipeline(node.stages, ctx, aliases)
		"simple":
			_simple(node, ctx, aliases)
		"assignment":
			var value = Expansion.scalar(node.words, ctx)
			if node.local:
				ctx.variables["$" + node.name] = value
			else:
				ctx.propogate(Context.Propagate.VARIABLES, "$" + node.name, value)
			_set_status(ctx, 0)
		"alias":
			ctx.propogate(Context.Propagate.ALIASES, node.name, node.source)
			_set_status(ctx, 0)
		"function":
			ctx.propogate(Context.Propagate.FUNCTIONS, node.name, node.source)
			ctx.get_root_ctx()._function_cache[node.name] = {"source": node.source, "tree": node.body}
			_set_status(ctx, 0)
		"if":
			var selected = false
			for branch in node.branches:
				if not branch.condition.is_empty(): _run(branch.condition, ctx, aliases)
				if _stopped(ctx): return
				if branch.condition.is_empty() or ctx.last_status == 0:
					_run(branch.body, ctx, aliases)
					selected = true
					break
			if not selected: _set_status(ctx, 0)
		"for", "while":
			_loop(node, ctx, aliases)
		"subshell":
			var child = Context.new_ctx("Subshell", ctx, true)
			_execute_tree(node.body, child, aliases)
			ctx.append_output(child.stdout)
			ctx.append_error(child.stderr)
			_set_status(ctx, child.exit_code)

static func _pipeline(stages:Array, ctx:Context, aliases:Dictionary):
	var input = ctx.stdin
	for i in stages.size():
		if _stopped(ctx): break
		var saved_input = ctx.stdin
		var saved_output = ctx.stdout
		ctx.stdin = input
		ctx.stdout = ""
		_run(stages[i], ctx, aliases)
		input = ctx.stdout
		ctx.stdin = saved_input
		ctx.stdout = saved_output + (input if i == stages.size() - 1 else "")

static func _loop(node:Dictionary, ctx:Context, aliases:Dictionary):
	var child = Context.new_ctx("Loop", ctx)
	child.data[_IS_LOOP_KEY] = true
	var collection:Array = []
	if node.kind == "for":
		for word in node.words:
			var values = Expansion.word_values(word, ctx)
			for value in values:
				if word.quoted: collection.append(value)
				else: collection.append_array(value.replace("\t", " ").replace("\n", " ").split(" ", false))
	var count = 0
	var body_status = 0
	while not _stopped(ctx):
		if node.kind == "for":
			if count >= collection.size(): break
			child.variables["$" + node.name] = collection[count]
		else:
			if count >= 100: break # Retained GDSh loop limit.
			_run(node.condition, child, aliases)
			if _stopped(child) or child.last_status != 0: break
		count += 1
		child.data.erase(_LOOP_CONTINUE_KEY)
		_run(node.body, child, aliases)
		body_status = child.last_status
		if child.data.get(_LOOP_BREAK_KEY, false) or ctx.exit_requested: break
		# A return in a containing function must unwind the loop too.
		if _has_return(child): break
		child.data.erase(_LOOP_CONTINUE_KEY)
	ctx.append_output(child.stdout)
	ctx.append_error(child.stderr)
	_set_status(ctx, body_status)

static func _has_return(ctx:Context) -> bool:
	var chain = ctx.get_inherited_ctxs()
	chain.push_front(ctx)
	for parent in chain:
		if parent.data.has(Types.RETURN_KEY): return true
	return false

static func _simple(node:Dictionary, ctx:Context, aliases:Dictionary):
	# Alias sources are deliberately parsed as command fragments. Expanded variable
	# values and substitution results never pass through this source-level step.
	var source_words:Array = []
	var next_aliases = aliases.duplicate()
	var changed = false
	for word in node.words:
		if not word.quoted and ctx.aliases.has(word.raw):
			if aliases.has(word.raw):
				ctx.append_error("GDSh alias cycle: " + word.raw)
				_set_status(ctx, Types.ExitCode.ERR)
				return
			next_aliases[word.raw] = true
			source_words.append(str(ctx.aliases[word.raw]).trim_prefix("@literal"))
			changed = true
		else:
			source_words.append(word.raw)
	if changed:
		var alias_source = " ".join(source_words)
		if node.has("raw_args"): alias_source += " " + node.raw_args
		var parsed = Parser.parse(alias_source, false, ctx.raw_commands)
		if not parsed.error.is_empty():
			_parse_error(ctx, parsed.error)
		else:
			_run(parsed.tree, ctx, next_aliases)
		return
	if node.has("raw_args"):
		var command = Context.new_ctx("Raw command", ctx)
		var scope = ctx.get_scope(node.words[0].raw)
		var script = _instance(scope.get(Types.ScopeDataKeys.SCRIPT) if scope != null else null)
		if is_instance_valid(script) and script.has_method("execute_raw"):
			var status = script.execute_raw(node.raw_args, command)
			if status is int: command.exit_code = status
		else:
			command.append_error("Raw command has no execute_raw handler: " + node.words[0].raw)
			command.exit_code = Types.ExitCode.ERR
		ctx.append_output(command.stdout)
		ctx.append_error(command.stderr)
		_set_status(ctx, command.exit_code)
		return
	var expanded = Expansion.words(node.words, ctx)
	if expanded.values.is_empty(): return
	var command = Context.new_ctx("", ctx)
	command.unconsumed_tokens = expanded.values
	command._token_metadata = expanded.metadata
	command.execute = true
	_dispatch(command)
	ctx.append_output(command.stdout)
	ctx.append_error(command.stderr)
	_set_status(ctx, command.exit_code)

static func _dispatch(ctx:Context):
	var name:String = ctx.unconsumed_tokens[0]
	if ctx.functions.has(name):
		name = Types.FUNCTION_KEY
	elif not ctx.has_scope(name):
		if name.is_absolute_path():
			name = "__run_script__"
		elif ctx.unconsumed_tokens.has("==") or ctx.unconsumed_tokens.has("!="):
			ctx.unconsumed_tokens.push_front("[")
			ctx.unconsumed_tokens.push_back("]")
			ctx._token_metadata.push_front({})
			ctx._token_metadata.push_back({})
			name = "["
	var scope = ctx.get_scope(name)
	if scope == null: scope = {}
	var script = _instance(scope.get(Types.ScopeDataKeys.SCRIPT))
	if is_instance_valid(script) and script.has_method("execute"):
		script.execute(ctx)
	else:
		ctx.append_error("Unrecognized command: " + name)
		ctx.exit_code = Types.ExitCode.ERR

## Scope entries hold a command script or an existing command object.
static func _instance(command):
	if command is GDScript:
		return load("res://addons/addon_lib/gdsh/load.gd").fresh(command).new()
	return command

static func _call_function(name:String, ctx:Context, args:Array):
	var source = str(ctx.functions.get(name, ""))
	var root = ctx.get_root_ctx()
	var cached = root._function_cache.get(name, {})
	if cached.get("source") != source:
		var parsed = Parser.parse(source, false, ctx.raw_commands)
		if not parsed.error.is_empty():
			_parse_error(ctx, parsed.error)
			return
		cached = {"source": source, "tree": parsed.tree}
		root._function_cache[name] = cached
	var child = Context.new_ctx(name, ctx)
	child.data[Types.FUNCTION_KEY] = true
	child.set_positional_args(name, args)
	_execute_tree(cached.tree, child)
	if child.data.has(Types.RETURN_KEY): child.exit_code = child.data[Types.RETURN_KEY]
	ctx.append_output(child.stdout)
	ctx.append_error(child.stderr)
	ctx.exit_code = child.exit_code
