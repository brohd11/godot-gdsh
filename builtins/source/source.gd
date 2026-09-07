extends "res://addons/addon_lib/gdsh/command_base.gd"


const _HELP = \
"Run script in the current process."

static func get_command_name():
	return "source"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
		&"positional_count": 1
	})

func _execute(ctx:Context):
	var path = _complete_path(positional_args[0], ctx.cwd)
	if not FileAccess.file_exists(path):
		ctx.exit_code = ExitCode.FAIL
		ctx.append_error("File doesn't exist, cannot source: " + path)
		return
	var source_history = ctx.data.get_or_add("source_history", {})
	if source_history.has(path):
		return
	source_history[path] = true
	Execution.source_file(path, ctx)

