extends RefCounted
const Types = preload("res://addons/addon_lib/gdsh/internal/types.gd")
const Context = preload("res://addons/addon_lib/gdsh/context.gd")
const Tokenizer = preload("res://addons/addon_lib/gdsh/internal/tokenizer.gd")
const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_string.gd")
const ScopeDataKeys = Types.ScopeDataKeys
const _IS_LOOP_KEY = "__is_loop__"
const _LOOP_BREAK_KEY = "__loop_break__"
const _LOOP_CONTINUE_KEY = "__loop_continue__"

static var _func_def_regex:RegEx
static var _conditional_regex:RegEx
static var _for_loop_regex:RegEx

enum ParseState { NORMAL, IN_FUNCTION, IN_CONDITIONAL, IN_MULTILINE_STRING, IN_LOOP }

var state:= ParseState.NORMAL
var accumulated_lines: PackedStringArray = []
var block_name:String = ""
var brace_depth:int = 0
var conditional_branches: Array = []
var loop_condition:String = ""

var execution_ctx: Context
var _is_function:bool = false
var _is_loop:bool = false

var _string_maps := {}


static func execute_command_multiline(string: String, ctx: Context=null):
	if ctx == null:
		ctx = Context.new()
	if ctx.exit_requested:
		return ctx
	_initialize_regex()
	var parser := new()
	parser.execution_ctx = ctx
	parser._is_function = ctx.data.get(Types.FUNCTION_KEY, false)
	parser._is_loop = ctx.data.get(_IS_LOOP_KEY, false)
	parser.run(string)
	# not sure this distinction is really needed
	#if not parser._is_function:
	if not ctx.exit_requested:
		ctx.exit_code = ctx.last_status
	return ctx


func run(string: String):
	var lines := string.split("\n", false)
	for i in range(lines.size()):
		var line: String = lines[i]
		line = remove_comment(line, true).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var statements: PackedStringArray = [line]
		if state != ParseState.IN_MULTILINE_STRING:
			statements = _split_statements(line)
		for s:String in statements:
			s = s.strip_edges()
			match state:
				ParseState.IN_FUNCTION:
					_parse_in_function(s)
				ParseState.IN_CONDITIONAL:
					_parse_in_conditional(s)
				ParseState.IN_LOOP:
					_parse_in_loop(s)
				ParseState.IN_MULTILINE_STRING:
					_parse_in_multiline_string(s)
				ParseState.NORMAL:
					_parse_normal(s)


			if execution_ctx.exit_requested:
				if Types.PRINT_DEBUG:
					print("EXITING:", s, ":EXIT:", execution_ctx.exit_code)
				return
			if _is_function and execution_ctx.data.get(Types.RETURN_KEY, -1) > -1:
				execution_ctx.last_status = execution_ctx.data.get(Types.RETURN_KEY, -1)
				if Types.PRINT_DEBUG:
					print("FUNC RETURN::", s)
				return
			if _is_loop:
				if execution_ctx.data.get(_LOOP_CONTINUE_KEY, false):
					if Types.PRINT_DEBUG:
						print("CONTINUE:", s)
					return
				elif execution_ctx.data.get(_LOOP_BREAK_KEY, false):
					return


func reset_block():
	accumulated_lines.clear()
	block_name = ""
	brace_depth = 0


func reset_conditional():
	conditional_branches.clear()
	reset_block()

func reset_loop():
	loop_condition = ""
	reset_block()


# ---- state handlers ----

func _parse_in_function(line: String):
	if brace_depth == 1 and line.begins_with("}"):
		#execution_ctx.functions[block_name] = "\n".join(accumulated_lines)
		execution_ctx.propogate(Context.Propagate.FUNCTIONS, block_name, "\n".join(accumulated_lines))
		reset_block()
		state = ParseState.NORMAL
	else:
		brace_depth += _count_unquoted_braces(line)
		accumulated_lines.append(line)


func _parse_in_conditional(line: String):
	if brace_depth == 1 and line.begins_with("}"):
		var _match = _conditional_regex.search(line)
		if not is_instance_valid(_match):
			_handle_conditional()
			reset_conditional()
			state = ParseState.NORMAL
			return
		var type = _match.get_string("type")
		var cond = _match.get_string("cond")
		if type == "else":
			conditional_branches.append(["", PackedStringArray()])
		elif type == "elif":
			conditional_branches.append([cond, PackedStringArray()])
	else:
		brace_depth += _count_unquoted_braces(line)
		conditional_branches[-1][1].append(line)


func _parse_in_multiline_string(line: String):
	accumulated_lines.append(line)
	var full_line := "\n".join(accumulated_lines)
	if _get_unclosed_quote(full_line).is_empty():
		accumulated_lines.clear()
		state = ParseState.NORMAL
		_parse_normal(full_line)

func _parse_in_loop(line: String):
	if Types.PRINT_DEBUG:
		print("IN LOOP:", line)

	if brace_depth == 1 and line.begins_with("}"):
		# process the loop function
		var loop_ctx = Context.new_ctx("Loop", execution_ctx)
		loop_ctx.positional_args = execution_ctx.positional_args
		loop_ctx.data[_IS_LOOP_KEY] = true
		var loop = "\n".join(accumulated_lines)
		# This cannot handle command substituiton in the condition
		if loop_condition.begins_with("for"):
			var for_match = _for_loop_regex.search(loop_condition)
			var iterator = for_match.get_string("iter")
			var collection = for_match.get_string("coll")
			if iterator == "" or collection == "":
				execution_ctx.append_error("For loop syntax error: " + line)
				execution_ctx.exit_code = Types.ExitCode.ERR
				return
			var coll_val = _substitute_vars(collection)
			var coll_split = UString.string_safe_split_multi(coll_val, [" ", "\t", "\n"])
			if Types.PRINT_DEBUG:
				print(collection, " -> ", coll_val)
				print(coll_split)

			for item in coll_split:
				loop_ctx.data.erase(_LOOP_CONTINUE_KEY)
				loop_ctx.variables["$" + iterator] = item
				execute_command_multiline(loop, loop_ctx)
				if Types.PRINT_DEBUG:
					print("LOOP BREAK:", loop_ctx.data)
				if loop_ctx.data.get(_LOOP_BREAK_KEY, false):
					break

		elif loop_condition.begins_with("while"):
			var count = 0
			var condition = loop_condition.trim_prefix("while").trim_suffix("{").strip_edges()
			while _evaluate_condition(condition) and count < 100:
				count += 1
				loop_ctx.data.erase(_LOOP_CONTINUE_KEY)
				execute_command_multiline(loop, loop_ctx)
				if loop_ctx.data.get(_LOOP_BREAK_KEY, false):
					break

		if Types.PRINT_DEBUG:
			print("LOOP OUT---\n", loop_ctx.stdout, "\n---")
		loop_ctx.write_to_parent(execution_ctx)

		reset_loop()
		state = ParseState.NORMAL
		pass
	else:
		brace_depth += _count_unquoted_braces(line)
		accumulated_lines.append(line)

func _parse_normal(line: String):

	if not _get_unclosed_quote(line).is_empty():
		accumulated_lines.clear()
		accumulated_lines.append(line)
		state = ParseState.IN_MULTILINE_STRING
		return

	var func_match = _func_def_regex.search(line)
	if func_match != null:
		block_name = func_match.get_string(1)
		brace_depth = 1
		state = ParseState.IN_FUNCTION
		accumulated_lines.clear()

		var end_of_func = line.get_slice("{", 1).strip_edges()
		if end_of_func == "}":
			_parse_in_function(end_of_func)
		elif end_of_func != "":
			accumulated_lines.append(end_of_func)
		return

	var cond_match = _conditional_regex.search(line)
	if is_instance_valid(cond_match) and cond_match.get_string("type") == "if":
		var cond := cond_match.get_string("cond")
		brace_depth = 1
		state = ParseState.IN_CONDITIONAL
		conditional_branches.clear()
		conditional_branches.append([cond, PackedStringArray()])
	elif _is_assignment(line):
		if line.begins_with("alias"):
			_handle_alias_assignment(line)
		else:
			_handle_assignment(line)
	elif _is_in_loop(line):
		brace_depth = 1
		state = ParseState.IN_LOOP
		accumulated_lines.clear()
		loop_condition = line
	else:
		var _sub_ctx = execute_command(line, {
			&"parent_ctx": execution_ctx
		})


# ---- handlers ----

func _handle_assignment(line: String):
	var eq_pos := line.find("=")
	var var_name := line.substr(0, eq_pos).strip_edges()
	var is_local = var_name.begins_with("local ")
	if is_local:
		var_name = var_name.trim_prefix("local ").strip_edges()

	var literal = false
	var value := line.substr(eq_pos + 1).strip_edges()
	if UString.is_string_or_string_name(value):
		if value[0] == "'":
			literal = true

	if not literal:
		value = UString.unquote(value)
		value = _substitute_vars(value) # handle recursed vars

	if is_local:
		execution_ctx.variables["$" + var_name] = value
	else:
		# non local will propagate up
		# sub shell commands will not have parent set
		execution_ctx.propogate(Context.Propagate.VARIABLES, "$" + var_name, value)

func _handle_alias_assignment(line: String):
	var eq_pos := line.find("=")
	var var_name := line.substr(0, eq_pos).trim_prefix("alias").strip_edges()
	var value := line.substr(eq_pos + 1).strip_edges()

	execution_ctx.propogate(Context.Propagate.ALIASES, var_name, value)


func _handle_conditional():
	for branch in conditional_branches:
		var condition: String = branch[0]
		var body_lines: PackedStringArray = branch[1]
		if condition.is_empty() or _evaluate_condition(condition):
			var body := "\n".join(body_lines)
			execute_command_multiline(body, execution_ctx)
			return

func _evaluate_condition(condition: String) -> bool:
	var ctx = execute_command(condition, {
		&"parent_ctx": execution_ctx,
	})
	return ctx.last_status == Context.ExitCode.OK


func _substitute_vars(string):
	if UString.is_string_or_string_name(string):
		if string[0] == "'":
			return string

	var val = Tokenizer.check_variable(string, execution_ctx)
	return val


# ---- utility ----

static func _count_unquoted_braces(line: String) -> int:
	var depth_change := 0
	var in_single := false
	var in_double := false
	var escaped := false
	for idx in range(line.length()):
		var ch := line[idx]
		if escaped:
			escaped = false
			continue
		if ch == "\\":
			escaped = true
			continue
		if ch == "'" and not in_double:
			in_single = not in_single
		elif ch == "\"" and not in_single:
			in_double = not in_double
		elif not in_single and not in_double:
			if ch == "{":
				depth_change += 1
			elif ch == "}":
				depth_change -= 1
	return depth_change


static func _get_unclosed_quote(line: String) -> String:
	var in_single := false
	var in_double := false
	var escaped := false
	for idx in range(line.length()):
		var ch := line[idx]
		if escaped:
			escaped = false
			continue
		if ch == "\\":
			escaped = true
			continue
		if ch == "'" and not in_double:
			in_single = not in_single
		elif ch == "\"" and not in_single:
			in_double = not in_double
	if in_single:
		return "'"
	if in_double:
		return "\""
	return ""

func remove_comment(text:String, string_safe:=false, string_map=null):
	if not string_safe:
		return text.get_slice(" #", 0)
	else:
		if string_map == null:
			string_map = _get_string_map(text)
		var comment_index = UString.string_safe_find(text, " #", 0, string_map)
		if comment_index > -1:
			text = text.substr(0, comment_index)
	return text

static func _is_assignment(line: String) -> bool:
	if "=" not in line:
		return false
	var left := line.substr(0, line.find("=")).strip_edges()
	left = left.trim_prefix("local ").strip_edges()
	return left.is_valid_ascii_identifier() or left.begins_with("alias ")

static func _is_in_loop(line:String) -> bool:
	if not line.ends_with("{"):
		return false
	return line.begins_with("for ") or line.begins_with("while ")


# Splits a physical line into normalized statements. Splits on unquoted ";" and,
# when a "{" actually opens a block (if/elif/else/for/while/name()), treats the
# "{" and its matching "}" as statement boundaries too. Literal braces (e.g.
# "echo {a:1}") are left intact. "} else {" / "} elif x {" stay joined so the
# conditional handler can consume them.
const _BRACE_LITERAL := 0
const _BRACE_BLOCK := 1

static func _split_statements(line: String) -> PackedStringArray:
	var out: Array = []
	var cur := ""
	var brace_stack: Array[int] = []
	var in_single := false
	var in_double := false
	var escaped := false
	var i := 0
	var n := line.length()
	while i < n:
		var ch := line[i]
		if escaped:
			cur += ch
			escaped = false
			i += 1
			continue
		if ch == "\\":
			cur += ch
			escaped = true
			i += 1
			continue
		if ch == "'" and not in_double:
			in_single = not in_single
			cur += ch
			i += 1
			continue
		if ch == "\"" and not in_single:
			in_double = not in_double
			cur += ch
			i += 1
			continue
		if in_single or in_double:
			cur += ch
			i += 1
			continue

		if ch == ";":
			_flush_statement(out, cur)
			cur = ""
		elif ch == "{":
			cur += "{"
			if _is_block_header(cur):
				_flush_statement(out, cur)
				cur = ""
				brace_stack.push_back(_BRACE_BLOCK)
			else:
				brace_stack.push_back(_BRACE_LITERAL)
		elif ch == "}":
			var is_block_close := brace_stack.is_empty() or brace_stack[-1] == _BRACE_BLOCK
			if not brace_stack.is_empty():
				brace_stack.pop_back()
			if is_block_close:
				_flush_statement(out, cur)
				cur = ""
				var rest := line.substr(i + 1).strip_edges()
				if _begins_with_keyword(rest, "else") or _begins_with_keyword(rest, "elif"):
					cur = "}"
				else:
					out.append("}")
			else:
				cur += "}"
		else:
			cur += ch
		i += 1
	_flush_statement(out, cur)
	return PackedStringArray(out)


static func _flush_statement(out: Array, text: String) -> void:
	text = text.strip_edges()
	if text != "":
		out.append(text)


static func _is_block_header(candidate: String) -> bool:
	if _func_def_regex.search(candidate) != null:
		return true
	if _conditional_regex.search(candidate) != null:
		return true
	return _is_in_loop(candidate.strip_edges())


static func _begins_with_keyword(text: String, keyword: String) -> bool:
	if not text.begins_with(keyword):
		return false
	if text.length() == keyword.length():
		return true
	var next := text[keyword.length()]
	return next == " " or next == "\t" or next == "{"

func _get_string_map(string:String):
	if _string_maps.has(string):
		return _string_maps[string]
	var sm = UString.get_string_map(string)
	_string_maps[string] = sm
	return sm


# ---- Single commands ----

static func source_file(file_path:String, parent_ctx:Context=null):
	if parent_ctx == null:
		parent_ctx = Context.new()
	if not file_path.is_absolute_path():
		file_path = parent_ctx.cwd.path_join(file_path).simplify_path()
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		parent_ctx.append_error("Cannot open GDSh script: " + file_path)
		parent_ctx.last_status = Types.ExitCode.FAIL
		parent_ctx.exit_code = Types.ExitCode.FAIL
		return parent_ctx
	var file_string = file.get_as_text()
	if not file_string.strip_edges(true, false).begins_with("#!gdsh"):
		parent_ctx.append_error("Not a gdsh script: " + file_path)
		parent_ctx.last_status = Types.ExitCode.FAIL
		parent_ctx.exit_code = Types.ExitCode.FAIL
		return parent_ctx
	return execute_command_multiline(file_string, parent_ctx)


#! keys parent_ctx:Context sub_shell:bool
## ctx object can be passed as argument, it should have text set already.
static func execute_command(text:String, params:={}):
	var parent_ctx = params.get(&"parent_ctx")
	var sub_shell = params.get(&"sub_shell", false)

	if not is_instance_valid(parent_ctx):
		parent_ctx = Context.new()

	var active_ctx = parent_ctx
	if sub_shell:
		active_ctx = Context.new_ctx(text + "-SubShell", parent_ctx, sub_shell)

	if active_ctx.exit_requested or text.strip_edges().is_empty():
		return active_ctx
	var expand_data = expand_commands(text, active_ctx)
	if active_ctx.exit_requested:
		return active_ctx

	var condition_map = expand_data.condition_map
	var expanded_commands = expand_data.command_statements
	if expanded_commands.size() == 1 and expanded_commands[0] == "":
		return active_ctx

	var skip_current_block = false
	var last_ctx = null
	for cmd_i in condition_map.keys():
		# should this be at the end? does it matter?
		if active_ctx.exit_requested:
			break

		var cmd_data = condition_map[cmd_i]
		if skip_current_block:
			if cmd_data.post == "||" and last_ctx.exit_code != 0:
				skip_current_block = false
			elif cmd_data.post == "&&" and last_ctx.exit_code == 0:
				skip_current_block = false
			continue

		var cmd_text:String = cmd_data.get("text")
		var sub_shell_cmd = cmd_text.begins_with("(") and cmd_text.ends_with(")")
		if sub_shell_cmd:
			cmd_text = cmd_text.trim_prefix("(").trim_suffix(")").strip_edges()


		var current_ctx = Context.new_ctx(cmd_text, active_ctx, sub_shell_cmd)

		if cmd_data.pre == "|" and is_instance_valid(last_ctx):
			current_ctx.stdin = last_ctx.stdout

		if sub_shell_cmd: # ensures nested coditions will parse
			execute_command_multiline(cmd_text, current_ctx)
		else:
			current_ctx.execute_parse()
			_parse_command(current_ctx)

		if Types.PRINT_DEBUG:
			pass
			#print("STDIN:", current_ctx.stdin)
			#print("STDOUT:", current_ctx.stdout)

		if cmd_data.post == "&&":
			if current_ctx.exit_code != 0:
				skip_current_block = true  # Failed! Skip the next block.

		elif cmd_data.post == "||":
			if current_ctx.exit_code == 0:
				skip_current_block = true  # Succeeded! Skip the next block.

		active_ctx.append_error(current_ctx.stderr) # stderr never flows through a pipe, always surface
		if cmd_data.post != "|":
			active_ctx.append_output(current_ctx.stdout)
			active_ctx.last_status = current_ctx.exit_code

		# end of command
		last_ctx = current_ctx

	# returns parent or the subshell
	if not active_ctx.exit_requested:
		active_ctx.exit_code = active_ctx.last_status
	return active_ctx


static func _parse_command(ctx:Context) -> void:
	var tokens:Array = ctx.unconsumed_tokens

	if tokens.is_empty():
		return
	var c_1 = UString.unquote(tokens[0])
	if ctx.functions.has(c_1):
		_scope_parse(Types.FUNCTION_KEY, ctx)
	else:
		var parse_scopes = _scope_parse(c_1, ctx)
		if parse_scopes == Types.NO_MATCHING_COMMAND:
			if c_1.is_absolute_path():
				_scope_parse("__run_script__", ctx)
			elif ctx.unconsumed_tokens.has("==") or ctx.unconsumed_tokens.has("!="):
				ctx.unconsumed_tokens.push_front("[")
				ctx.unconsumed_tokens.push_back("]")
				_scope_parse("[", ctx)
			else:
				ctx.append_error("Unrecognized command: " + c_1)
				ctx.exit_code = 2 # 2 is err

	if ctx.scopes.is_empty():
		ctx.append_error("Need to load command set.")

	if ctx.stdout != "\n":
		ctx.stdout = ctx.stdout.rstrip("\n")


static func _scope_parse(_name:String, ctx:Context):
	var scope = ctx.scopes.get(_name)
	if scope == null:
		return Types.NO_MATCHING_COMMAND
	var script = scope.get(ScopeDataKeys.SCRIPT)
	if script is GDScript:
		script = script.new()

	if is_instance_valid(script) and script.has_method("execute"):
		script.execute(ctx) # no return, exit code and stdout are properties
	else:
		ctx.append_error("Could not parse in object: %s" % scope)
		ctx.exit_code = Types.ExitCode.ERR

	return _name

#! keys condition_map:Dictionary command_statements:Array display:String
static func expand_commands(text:String, parent:Context, display:=false):
	var tokenizer = Tokenizer.new(parent)
	tokenizer.execute = true
	var token_data = tokenizer.parse_command_string_execute(text, display)
	var all_expanded_text = " ".join(token_data.expanded)

	if token_data.expanded.is_empty():
		parent.exit_code = Context.ExitCode.FAIL
		parent.exit_requested = true
		return {}

	if token_data.expanded[token_data.expanded.size() - 1] in ["&&", "||", "|"]:
		parent.append_error("Token ends on operator: " + token_data.expanded[token_data.expanded.size() - 1])
		parent.exit_code = Context.ExitCode.FAIL
		parent.exit_requested = true
		return {}
	# logical statements
	var valid_expanded_command_statements = [all_expanded_text]


	var all_exp_length = all_expanded_text.length()
	var last_condition = ""
	var condition_map = {}
	if not (all_expanded_text.contains(" && ") or all_expanded_text.contains(" || ") or all_expanded_text.contains(" | ")):
		condition_map[0] = {"text": all_expanded_text, "pre":"", "post":""}
	else:
		valid_expanded_command_statements.clear()
		var string_map = UString.get_string_map(all_expanded_text)
		var working_start = 0
		var valid_command_start = 0
		var count = 0
		while working_start < all_expanded_text.length():# and count < 10:

			var and_i = UString.string_safe_find(all_expanded_text, " && ", working_start, string_map)
			var or_i = UString.string_safe_find(all_expanded_text, " || ", working_start, string_map)
			var pipe_i = UString.string_safe_find(all_expanded_text, " | ", working_start, string_map)
			var bracket_i = UString.string_safe_find(all_expanded_text, "(", working_start, string_map)

			if and_i == -1:  and_i  = all_exp_length
			if or_i == -1:   or_i   = all_exp_length
			if pipe_i == -1: pipe_i = all_exp_length
			var min_i = min(and_i, or_i, pipe_i)

			#print("&& %s || %s | %s ( %s" % [and_i, or_i, pipe_i, bracket_i])
			if bracket_i > -1 and bracket_i < min_i:
				var end = string_map.bracket_map[bracket_i]
				if end > min_i:
					working_start = end
					continue

			if min_i == all_exp_length:
				var final_command = all_expanded_text.substr(valid_command_start)
				final_command = final_command.strip_edges()
				condition_map[count] = {
					"text": final_command,
					"pre": last_condition,
					"post": ""
				}
				valid_expanded_command_statements.append(final_command)
				break

			var cond_match = ""
			match min_i:
				and_i: cond_match = "&&"
				or_i: cond_match = "||"
				pipe_i: cond_match = "|"

			var idx = min(and_i, or_i, pipe_i)
			var command = all_expanded_text.substr(valid_command_start, idx - valid_command_start)
			command = command.strip_edges()
			condition_map[count] = {
				"text": command,
				"pre": last_condition,
				"post": cond_match
			}
			valid_expanded_command_statements.append(command)
			last_condition = cond_match

			working_start = idx + cond_match.length() + 2
			valid_command_start = working_start

			count += 1

	return {
		&"command_statements": valid_expanded_command_statements,
		&"display": token_data.display,
		&"condition_map": condition_map
	}

static func _initialize_regex():
	if not is_instance_valid(_func_def_regex):
		_func_def_regex = RegEx.new()
		_func_def_regex.compile(
			r"^[ \t]*(\w+)\s*\(\s*\)\s*\{" #$"
		)

	if not is_instance_valid(_conditional_regex):
		_conditional_regex = RegEx.new()
		_conditional_regex.compile(
			r"^\s*(?:\}\s*)?(?<type>if|elif|else)\b(?<cond>[^{]*)\{"
		)

	if not is_instance_valid(_for_loop_regex):
		_for_loop_regex = RegEx.new()
		_for_loop_regex.compile(r"^for\s+(?<iter>\w+)\s+in\s+(?<coll>[$A-Za-z0-9 ]*)\s*{")
