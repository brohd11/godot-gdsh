extends "res://addons/addon_lib/gdsh/command_base.gd"


const _HELP = \
"Built in command to run a script in a subprocess."

var script_path:String

static func get_command_name():
	return "__run_script__"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0"
	})

func _consume_self(ctx:Context) -> ExitCode:
	script_path = _complete_path(UString.unquote(_consume_token(ctx)), ctx.cwd)
	return ExitCode.OK

func _execute(ctx:Context):
	if not FileAccess.file_exists(script_path):
		ctx.append_error("File doesn't exist: " + script_path)
		ctx.exit_code = ExitCode.FAIL
		return
	var file_as_string = FileAccess.get_file_as_string(script_path)
	if not file_as_string.strip_edges(true, false).begins_with("#!gdsh"):
		ctx.append_error("File does not have #!gdsh tag: " + script_path)
		ctx.exit_code = ExitCode.FAIL
		return

	var sub_ctx = Context.new_ctx(script_path.get_file() + "-SubShell", ctx, true)
	sub_ctx.set_positional_args(script_path, positional_args)


	Execution.execute_command_multiline(file_as_string, sub_ctx)

	ctx.append_output(sub_ctx.strip_output_newlines())
	ctx.append_error(sub_ctx.strip_error_newlines())
	ctx.exit_code = sub_ctx.exit_code
	ctx.last_status = sub_ctx.exit_code
