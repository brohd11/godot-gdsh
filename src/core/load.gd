#! namespace GDSh class Load
extends RefCounted
## Load GDSh.CommandBase scripts without editor configuration or a singleton.

const Paths = preload("res://addons/addon_lib/gdsh/src/core/paths.gd")
const Types = preload("res://addons/addon_lib/gdsh/src/core/types.gd")
const CommandBase = preload("res://addons/addon_lib/gdsh/src/core/command_base.gd")
# Explicit dependencies keep builtin scripts reachable in relocated plugin exports.
const BUILTIN_SCRIPTS = [
	preload("res://addons/addon_lib/gdsh/src/core/builtins/builtins.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/hidden/hidden.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/clear/clear.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/new_ctx/new_ctx.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/break/break.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/continue/continue.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/return/return.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/exit/exit.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/shift/shift.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/true/true.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/false/false.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/comparison/comparison.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/expr/expr.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/echo/echo.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/source/source.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/cd/cd.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/cn/cn.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/pwn/pwn.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/node/node.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/script/script.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/ambiguous/ambiguous.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/help/help.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/function/function.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/gdsh/gdsh.gd"),
	preload("res://addons/addon_lib/gdsh/src/core/builtins/undoredo/undoredo.gd"),
]


## Returns null and reports an error for an invalid command.
static func load_command(path:String) -> GDScript:
	if not ResourceLoader.exists(path, "GDScript"):
		push_error("GDSh.Load: command not found: " + path)
		return null
	var script = ResourceLoader.load(path, "GDScript") as GDScript
	# Not can_instantiate(): it is false for non-@tool scripts while scripting is disabled (the editor), and for @abstract ones.
	if script == null:
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

## Commands outside res:// (user command directories) reload on use, so edits apply without a restart.
static func fresh(script:GDScript) -> GDScript:
	if script == null or script.resource_path.is_empty() or script.resource_path.begins_with("res://"):
		return script
	var reloaded = ResourceLoader.load(script.resource_path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as GDScript
	return reloaded if reloaded != null else script

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
		# A loose manifest.gd preloads the directory's commands for exporters; it is not a command.
		elif not child_directories_only and entry.ends_with(".gd") and entry != "manifest.gd":
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
	for script in BUILTIN_SCRIPTS:
		scopes[script.get_command_name()] = {Types.ScopeDataKeys.SCRIPT: script}
	return scopes
