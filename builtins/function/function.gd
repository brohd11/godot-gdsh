extends "res://addons/addon_lib/gdsh/command_base.gd"

const FUNCTION_KEY = "__function__"
const RETURN_KEY = "__function_return__"

const _HELP = \
"Built in function command. Acts as glue between function and it's contents."

var function_name:String

static func get_command_name():
	return FUNCTION_KEY

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
	})

func _consume_self(ctx:Context) -> ExitCode:
	function_name = _consume_token(ctx)
	return ExitCode.OK

func _get_target_positional_count() -> int:
	return positional_args.size()

func _execute(ctx:Context):
	var function_text = ctx.functions.get(function_name)
	var new_ctx = Context.new_ctx("", ctx)
	new_ctx.title = function_name
	new_ctx.execute = true
	new_ctx.data[FUNCTION_KEY] = true

	new_ctx.set_positional_args(function_name, positional_args)
	Execution.execute_command_multiline(function_text, new_ctx)

	# i think ctx could just be passed, but this keeps the postional args of the parent unchanged
	# just need to be sure to pass the output back, function and variable propogation already handled
	ctx.append_output(new_ctx.stdout)
	ctx.append_error(new_ctx.stderr)
	ctx.exit_code = new_ctx.exit_code # ctx is the command call, not the parent process
