extends "res://addons/addon_lib/gdsh/command_base.gd"

const ScriptUtil = preload("res://addons/addon_lib/gdsh/builtins/script/script_util.gd")

const _HELP = \
"Print the target script's resource path.
Usage: script <target> get_path"

static func get_command_name():
	return "get_path"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
	})

func _execute(ctx:Context):
	var script = ScriptUtil.get_script_from_ctx(ctx)
	if not is_instance_valid(script):
		ctx.append_error("Could not get script.")
		return ExitCode.FAIL
	if script.resource_path == "":
		# Inner classes, and scripts built from a file outside the project, have no path.
		ctx.append_output("No Path - Likely Inner Class")
	else:
		ctx.append_output(script.resource_path)
	return ExitCode.OK
