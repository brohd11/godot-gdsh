extends "res://addons/addon_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Returns ExitCode.FAIL"

static func get_command_name():
	return "false"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
	})

func _execute(ctx:Context):
	ctx.exit_code = ExitCode.FAIL
