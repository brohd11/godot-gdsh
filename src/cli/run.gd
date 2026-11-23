extends SceneTree
## Runs a gdsh line without the editor, exiting with its status.
##     godot --headless --path . --script res://addons/_lib/gdsh/src/cli/run.gd -- -c '<line>'
## Offers the builtins, utils and the ~/.gdsh / res://.gdsh roots. Editor-only commands still
## load, and fail with their own error when run. install.gd sets up the `gdsh` wrapper for this.

const Context = preload("res://addons/_lib/gdsh/src/core/context.gd")
const Execute = preload("res://addons/_lib/gdsh/src/core/execute.gd")
const Host = preload("res://addons/_lib/gdsh/src/core/host.gd")

const UTILS_CMD_DIR = "res://addons/_lib/gdsh_lib/utils/cmd"

const _USAGE = \
"Usage: run.gd -- -c '<line>' | -f <file.gdsh>
  -c  run a command line (pipes, quoting and variables work)
  -f  run a .gdsh script"


func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] not in ["-c", "-f"]:
		printerr(_USAGE)
		quit(1)
		return
	# root isn't inside the tree during _initialize, so node lookups would error.
	await process_frame

	# Host resolves the user roots (rebuilt against this gdsh), so a ctx can take its scopes.
	# utils is its own package, so a project may have gdsh core alone.
	var dirs = [UTILS_CMD_DIR] if DirAccess.dir_exists_absolute(UTILS_CMD_DIR) else []
	var host = Host.new({"default_dirs": true, "command_dirs": dirs})
	var ctx = Context.new("gdsh cli")
	ctx.scopes.merge(host.get_scopes(), true)

	if args[0] == "-c":
		await Execute.execute_command_multiline(args[1], ctx)
	else:
		await Execute.source_file(args[1], ctx)

	var out = Context.plain_text(ctx.stdout)
	var err = Context.plain_text(ctx.stderr)
	if not out.is_empty():
		printraw(out if out.ends_with("\n") else out + "\n")
	if not err.is_empty():
		printerr(err.rstrip("\n"))
	quit(ctx.exit_code)
