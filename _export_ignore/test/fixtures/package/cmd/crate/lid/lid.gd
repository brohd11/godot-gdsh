extends GDSh.CommandBase

static func get_command_name():
	return "lid"

static func get_self_command_data():
	return _command_data({&"help": "Package fixture leaf"})

func _execute(ctx:Context):
	ctx.append_output("lid:open")
	return ExitCode.OK
