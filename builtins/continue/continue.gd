extends "res://addons/addon_lib/gdsh/command_base.gd"


const _HELP = \
"Skip to the next iteration of the current loop. Only valid inside a gdsh loop."

static func get_command_name():
	return "continue"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
	})


func _execute(ctx:Context):
	for inh in ctx.get_inherited_ctxs():
		if inh.data.has(Execution._IS_LOOP_KEY):
			inh.data[Execution._LOOP_CONTINUE_KEY] = true
			return

	ctx.append_error("Cannot continue when not in a loop.")
	ctx.exit_code = ExitCode.ERR
