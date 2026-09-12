extends RefCounted
## Load GDSh.CommandBase scripts without editor configuration or a singleton.

const Paths = preload("res://addons/addon_lib/gdsh/internal/paths.gd")
const Types = preload("res://addons/addon_lib/gdsh/internal/types.gd")
const CommandBase = preload("res://addons/addon_lib/gdsh/command_base.gd")
const BUILTIN_NAMES = [
	"break", "continue", "return", "exit", "shift", "true", "false", "comparison",
	"expr", "echo", "source", "cd", "help", "function", "run_script",
]

## Returns null and reports an error for an invalid command.
static func load_command(path:String) -> GDScript:
	if not ResourceLoader.exists(path, "GDScript"):
		push_error("GDSh.Load: command not found: " + path)
		return null
	var script = ResourceLoader.load(path, "GDScript") as GDScript
	if script == null or not script.can_instantiate():
		push_error("GDSh.Load: cannot instantiate command: " + path)
		return null
	var base = script.get_base_script()
	while base != null and base != CommandBase:
		base = base.get_base_script()
	if base == null:
		push_error("GDSh.Load: command must extend GDSh.CommandBase: " + path)
		return null
	var name = script.get_command_name()
	if not name is String or name.is_empty() or name == CommandBase._UNAMED:
		push_error("GDSh.Load: command has no valid name: " + path)
		return null
	return script

## Loads loose .gd files and name/name.gd entries, without flattening child commands.
## child_directories_only is used by CommandBase to discover its subcommands.
static func load_directory(path:String, child_directories_only:=false) -> Dictionary:
	var candidates: Array[String] = []
	var entries = Paths.list_directory(path)
	for entry in entries:
		if entry.ends_with("/"):
			var name = entry.trim_suffix("/")
			var candidate = path.path_join(name).path_join(name + ".gd")
			if ResourceLoader.exists(candidate, "GDScript"):
				candidates.append(candidate)
		elif not child_directories_only and entry.ends_with(".gd"):
			candidates.append(path.path_join(entry))
	candidates.sort()
	var scopes = {}
	for candidate in candidates:
		var script = load_command(candidate)
		if script == null:
			continue
		var name = script.get_command_name()
		if scopes.has(name):
			push_error("GDSh.Load: duplicate command '%s', skipping %s" % [name, candidate])
			continue
		scopes[name] = {Types.ScopeDataKeys.SCRIPT: script}
	return scopes

static func load_builtins() -> Dictionary:
	var scopes = {}
	var parent = load_command("res://addons/addon_lib/gdsh/builtins/builtins.gd")
	if parent != null:
		scopes[parent.get_command_name()] = {Types.ScopeDataKeys.SCRIPT: parent}
	for name in BUILTIN_NAMES:
		var path = "res://addons/addon_lib/gdsh/builtins/%s/%s.gd" % [name, name]
		var script = load_command(path)
		if script != null:
			scopes[script.get_command_name()] = {Types.ScopeDataKeys.SCRIPT: script}
	return scopes
