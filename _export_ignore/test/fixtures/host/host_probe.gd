extends GDSh.CommandBase

static func get_command_name():
	return "host_probe"

static func get_self_command_data():
	return _command_data({&"help": "Print _host(), or fail under the CLI"})

func _execute(ctx:Context):
	if _host() == Host.CLI:
		return ExitCode.FAIL
	ctx.append_output("host:" + _host())
	return ExitCode.OK
