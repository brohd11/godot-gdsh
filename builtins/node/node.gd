extends "res://addons/addon_lib/gdsh/command_base.gd"

const NodePaths = preload("res://addons/addon_lib/gdsh/internal/node_paths.gd")

const _HELP = \
"Target a node in the SceneTree. Paths are absolute, or relative to the working node (see cn).
With no subcommand the node's absolute path is printed, so it pipes into tree commands.
Usage:
  node <node path>              print the node's absolute path
  <node path>                   the same, when the path is not a registered command
  node <node path> <command>    run a subcommand against the node"

## The token this command was invoked on, resolved or not, so failures can name it.
var requested:String = ""
## Set only once the node resolved; also gates help from the error path.
var node_path:String = ""


static func get_command_name() -> String:
	return "node"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
	})


## Entered two ways: explicitly (`node <path>`) or with the path itself in
## command position, in which case token 0 is already the path.
func _consume_self(ctx:Context) -> ExitCode:
	ctx.data.erase("script")
	ctx.data.erase("node")
	var token = _consume_token(ctx)
	if token == get_command_name():
		# Nothing to route: fall through to _execute, which prints help.
		if ctx.tokens_empty() or ctx.unconsumed_tokens.front().begins_with("-") or ctx.unconsumed_tokens.front() in get_commands():
			return ExitCode.OK
		token = _consume_token(ctx)
	requested = token
	var node = NodePaths.resolve(token, ctx.cwn)
	if node != null:
		node_path = token
		ctx.data["node"] = node
	return ExitCode.OK


func _get_help(what:String):
	if node_path != "":
		_ctx_obj.append_output(get_self_command_data().get(&"help"))
		print_available_commands()
	else:
		_ctx_obj.append_error("Unrecognized command: " + what)


func _execute(ctx:Context):
	if requested.is_empty():
		ctx.append_output(get_help_string(true))
		return ExitCode.OK
	var node = ctx.data.get("node")
	if not is_instance_valid(node):
		ctx.append_error("Node not found: " + requested)
		return ExitCode.FAIL
	ctx.append_output(NodePaths.path_of(node))
	return ExitCode.OK


func _get_commands() -> Dictionary:
	var commands = {}
	for command in [
		preload("res://addons/addon_lib/gdsh/builtins/script/call/call.gd"),
		preload("res://addons/addon_lib/gdsh/builtins/script/list/list.gd"),
		preload("res://addons/addon_lib/gdsh/builtins/script/args/args.gd"),
		preload("res://addons/addon_lib/gdsh/builtins/script/get_path/get_path.gd"),
	]:
		Options.add_command_script_to_dict(command, commands)
	return commands
