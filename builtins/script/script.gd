extends "res://addons/addon_lib/gdsh/command_base.gd"

const ScriptUtil = preload("res://addons/addon_lib/gdsh/builtins/script/script_util.gd")
const URString = UtilR.Strings.URString
const URClassDetail = UtilR.Objects.URClassDetail

const _HELP = \
"Target a GDScript: a global class name, a res:// / user:// / absolute path, or a path relative
to the working directory. Member access walks into inner classes (Outer.Inner).
Usage:
  script <GlobalClass|path.gd> <command>
  <GlobalClass|path.gd> <command>    the same, with the target in command position
  script --path=res://file.gd        target a script by path
  script --class=MyClass             target a global class by name"

var script_access_path:String
var text_flag:=false

static func get_command_name() -> String:
	return "script"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--text", {
		&"help": "Output the target script's source code to stdout."
	})
	options.add_option("--path=", {
		&"help": "Target a script by path instead of the current one.",
		&"trailing_char": "",
		&"flag_completion": {"type": FlagType.FILE, "ext": ["gd"]},
	})
	options.add_option("--class=", {
		&"help": "Target a global (user) class by name instead of the current script.",
		&"trailing_char": "",
		&"flag_completion": {"type": FlagType.USER_CLASS},
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--text":
		text_flag = true
	elif flag.begins_with("--path=") or flag.begins_with("--class="):
		_set_script_access_path(_get_flag_value(flag))

## Entered explicitly as `script <target>`, or with the target itself in command position.
func _consume_self(ctx:Context) -> ExitCode:
	var token = _consume_token(ctx)
	if token == get_command_name() and not ctx.tokens_empty():
		var next:String = ctx.unconsumed_tokens.front()
		# Only a bare target is absorbed here. Flags and subcommands must reach _route, or
		# `script --path=x get_path` would consume the flag as its target.
		if not next.begins_with("-") and not next in get_commands():
			token = _consume_token(ctx)
	# Left as "script" for the explicit form, which means the host's current script.
	script_access_path = token
	if ctx.stdin != "":
		script_access_path = ctx.stdin.strip_edges()
	ctx.data["script"] = ScriptUtil.resolve_access_path(script_access_path, ctx)
	return ExitCode.OK

func _set_script_access_path(new_path:String):
	script_access_path = new_path
	_ctx_obj.data["script"] = ScriptUtil.resolve_access_path(script_access_path, _ctx_obj)

func _get_help(what:String):
	if script_access_path != "" and script_access_path != get_command_name():
		_ctx_obj.append_output(get_self_command_data().get(&"help"))
		print_available_commands()
	else:
		_ctx_obj.append_error("Unrecognized command: " + what)

func _get_completions(ctx:Completion):
	var flag_completion = _get_flag_type_completions(ctx)
	if flag_completion != null:
		return flag_completion
	if "--text" in consumed_tokens:
		return {}

	var cursor_on_access = ctx.token_before_cursor == script_access_path and ctx.char_before_cursor != " "
	if not cursor_on_access:
		var commands = get_commands(true)
		commands.merge(get_flags(true))
		return commands
	var options = Options.new()
	options.merge(get_completion_static(ctx, script_access_path))
	return options.get_options()

## Member-access completion for a partially typed target: offers the script's preloads.
static func get_completion_static(ctx:Completion, target_access_path):
	var options = Options.new()
	var cursor_on_access = ctx.token_before_cursor == target_access_path and ctx.char_before_cursor != " "
	var target_script = ScriptUtil.get_script_from_ctx(ctx.context)
	if not is_instance_valid(target_script):
		if not cursor_on_access:
			return {}
		var access_path = URString.trim_member_access_back(target_access_path)
		target_script = ScriptUtil.resolve_access_path(access_path, ctx.context)
	if not is_instance_valid(target_script):
		return {}
	if not cursor_on_access:
		return {}
	for name in URClassDetail.script_get_preloads(target_script, false, true):
		options.add_option(name, {&"trailing_char": ""})
	return options.get_options()

func _execute(ctx:Context):
	if text_flag:
		var script = ScriptUtil.get_script_from_ctx(ctx)
		if is_instance_valid(script):
			ctx.write_output(script.source_code)
		else:
			ctx.append_error("Could not get script: " + script_access_path)
			return ExitCode.FAIL
		return ExitCode.OK
	_get_help_for_token(consumed_tokens.front() if not consumed_tokens.is_empty() else get_command_name())
	return ExitCode.FAIL
