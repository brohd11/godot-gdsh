extends "res://addons/addon_lib/gdsh/command_base.gd"

const NodePaths = preload("res://addons/addon_lib/gdsh/internal/node_paths.gd")

const _HELP = \
"Change the GDSh working node, the base for relative node paths (as cd is for file paths).
Usage: cn <rel or abs node path>"

static func get_command_name():
	return "cn"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": 1,
	})

func _get_completions(completion:Completion) -> Dictionary:
	return get_completion_static(completion.context, positional_args)

static func get_completion_static(ctx:Context, pos_args:Array) -> Dictionary:
	var rel_path = ""
	if pos_args.size() > 0:
		rel_path = pos_args[0]
	return _completion_node_path(ctx, rel_path)


## Child node names under the typed prefix, mirroring cd's directory completion: only the last
## segment is completed, and the prefix the user already typed is kept for insertion.
static func _completion_node_path(ctx:Context, current_rel_path:String) -> Dictionary:
	var options = Options.new()
	var insert_base = current_rel_path.left(current_rel_path.rfind("/") + 1)
	var base_path = insert_base.trim_suffix("/")
	var base:Node
	if base_path.is_empty():
		base = NodePaths.cwn_node(ctx.cwn)
	else:
		base = NodePaths.resolve(base_path, ctx.cwn)
	if base == null:
		return options.get_options()
	options.add_option("..", {&"insert": insert_base + "..", &"trailing_char": "/"})
	for child in base.get_children():
		var child_name = str(child.name)
		options.add_option(child_name, {
			&"insert": insert_base + child_name,
			&"trailing_char": "/",
		})
	return options.get_options()


func _execute(ctx:Context):
	return execute_static(ctx, positional_args)


static func execute_static(ctx:Context, pos_args:Array):
	var target = pos_args[0]
	var node = NodePaths.resolve(target, ctx.cwn)
	if node == null:
		ctx.append_error("Node does not exist: " + target)
		return ExitCode.ERR
	# Stored absolute, so a later cwd/scene change cannot re-anchor a relative value.
	ctx.propogate(Context.Propagate.PROPERTY, "cwn", NodePaths.path_of(node))
	return ExitCode.OK
