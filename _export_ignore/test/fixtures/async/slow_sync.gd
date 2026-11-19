extends GDSh.CommandBase
## Busy for N ms, calling checkpoint() throughout, then prints how many frames passed. Run
## directly it yields frames; inside $(...) it must finish in the current frame.

static func get_command_name():
	return "slow_sync"

static func get_self_command_data():
	return _command_data({&"help": "Work N ms with checkpoints, then echo frames passed", &"positional_count": 1})

func _execute(ctx:Context):
	var frames = Engine.get_process_frames()
	var until = Time.get_ticks_msec() + int(positional_args[0])
	while Time.get_ticks_msec() < until:
		if await ctx.checkpoint():
			return ExitCode.CANCELLED
	ctx.append_output("frames:%d" % (Engine.get_process_frames() - frames))
	return ExitCode.OK
