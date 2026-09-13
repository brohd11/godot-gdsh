extends "res://addons/addon_lib/gdsh/command_base.gd"


const _HELP = \
"Returns ExitCode.OK"

static func get_command_name():
	return "true"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
	})

func _execute(ctx:Context):
	ctx.exit_code = ExitCode.OK
