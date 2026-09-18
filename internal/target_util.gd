extends RefCounted
## Resolve script and node targets and enumerate their members. Script paths accept a global
## class name, a res://, user:// or absolute OS path, or a path relative to ctx.cwd.
## Member access (Outer.Inner) walks into inner classes. The "current editor script" form is a host hook, so core stays editor-free.

const Options = preload("res://addons/addon_lib/gdsh/options.gd")

const URString = UtilR.Strings.URString
const URClassDetail = UtilR.Objects.URClassDetail

const USAGE_TEMPLATE = \
"Usage: script <class|path.gd> %s
Usage: node <node path> %s"


static func get_usage_string(preamble:String, commands:String):
	return preamble + "\n" + USAGE_TEMPLATE % [commands, commands]


## Host hook: the script the editor currently has open, through
## `ctx.host_data["current_script"]: Callable() -> Script`. Null without a host.
static func host_current_script(ctx):
	var hook = ctx.host_data.get("current_script") if ctx != null else null
	return hook.call() if hook is Callable and hook.is_valid() else null


## A token naming a file rather than a global class.
static func _looks_like_path(text:String) -> bool:
	return text.is_absolute_path() or text.contains("/") or text.get_extension().to_lower() == "gd"


static func _complete(path:String, ctx) -> String:
	if path.is_absolute_path() or ctx == null:
		return path
	return ctx.cwd.path_join(path).simplify_path()


## Load a script by path. The editor's cwd is a globalized OS path, so localize first and use
## the resource loader whenever the file is inside the project; a genuinely external file has no
## resource path and is built from its source instead.
static func _load_script(path:String):
	var localized = ProjectSettings.localize_path(path)
	if localized.begins_with("res://") or localized.begins_with("user://"):
		return load(localized) if ResourceLoader.exists(localized) else null
	if not FileAccess.file_exists(path):
		return null
	var script = GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path)
	return script if script.reload() == OK else null


static func resolve_access_path(access_path:String, ctx=null):
	var current_script
	if URString.get_member_access_front(access_path) == "script":
		current_script = host_current_script(ctx)
		if current_script == null:
			return null
	if access_path == "script":
		return current_script

	if _looks_like_path(access_path):
		var resolved = _complete(access_path, ctx)
		var script_path_data = URString.get_script_path_and_suffix(resolved)
		if script_path_data.is_empty():
			return _load_script(resolved)
		current_script = _load_script(script_path_data[0])
		if current_script == null:
			return null
		if script_path_data[1] == "":
			return current_script
		access_path = script_path_data[1]
	else:
		var front = URString.get_member_access_front(access_path)
		if front != "script":
			var global_script = URClassDetail.get_global_class_script(front)
			if global_script == null:
				return null
			current_script = global_script
		if not access_path.contains("."):
			return current_script
		access_path = URString.trim_member_access_front(access_path)

	var final_script = current_script
	var parts = access_path.split(".", false)
	for i in range(parts.size()):
		var part = parts[i]
		var script_check = URClassDetail.get_member_info_by_path(final_script, part)
		if script_check != null:
			final_script = script_check
		else:
			if i != parts.size() - 1:
				return null
			break
	return final_script


static func get_script_from_ctx(ctx):
	return ctx.data.get("script")


## Routing sets exactly one target; no fallback to a stale target from another command.
static func get_target(ctx):
	return ctx.data.get("node") if ctx.data.has("node") else ctx.data.get("script")


static func get_methods_from_ctx(ctx, show_private:bool, static_only:=false,
		inherited:=false, engine:=false):
	var target = get_target(ctx)
	var options = Options.new()
	var methods = get_members(target, "methods", show_private, inherited, engine)
	for name in methods:
		var method = methods[name]
		if static_only and target is Script and not (method.get("flags", 0) & METHOD_FLAG_STATIC):
			continue
		var count = -1 if method.get("flags", 0) & METHOD_FLAG_VARARG else method.get("args", []).size()
		options.add_option(name, {&"metadata": {Options.Keys.ARG_COUNT: count}})
	return options.get_options()


static func get_method_info(target, name:String, inherited:=false, engine:=false) -> Dictionary:
	return get_members(target, "methods", true, inherited, engine).get(name, {})


## The default is the target's own script; --inherited adds base scripts and --engine
## adds the native surface. Instances supply live metadata, including dynamic properties.
static func get_members(target, kind:String, show_private:=false, inherited:=false, engine:=false) -> Dictionary:
	if not is_instance_valid(target):
		return {}
	var script = target if target is Script else target.get_script()
	var members = _script_members(script, kind, inherited or engine) if script != null else {}
	if engine:
		var base_type = script.get_instance_base_type() if target is Script else target.get_class()
		var hint = {"methods": "method", "properties": "property", "signals": "signal",
				"constants": "const", "enums": "enum"}.get(kind, "")
		# Keep the nearest script declaration when it overrides an engine member.
		members.merge(URClassDetail.get_members_of_base_type(base_type, [hint]))
	if target is Node:
		var live:Array = []
		match kind:
			"methods": live = target.get_method_list()
			"signals": live = target.get_signal_list()
			"properties": live = target.get_property_list()
		for info in live:
			var name = str(info.get("name", ""))
			# Property metadata can be supplied dynamically by the instance. Method metadata
			# above already preserves derived overrides, unlike the duplicate live entries.
			if kind == "properties" and (engine or members.has(name)):
				members[name] = info
			elif engine and not members.has(name):
				members[name] = info
	for name in members.keys():
		if name.is_empty() or (not show_private and name.begins_with("_")):
			members.erase(name)
		elif kind == "properties" and members[name].get("usage", 0) & (
				PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_INTERNAL):
			members.erase(name)
	return members


static func _script_members(script:Script, kind:String, inherited:bool) -> Dictionary:
	var members = {}
	if kind == "constants" or kind == "enums":
		var current = script
		while current != null:
			members.merge(current.get_script_constant_map())
			current = current.get_base_script() if inherited else null
		if kind == "enums":
			for name in members.keys():
				if not members[name] is Dictionary or not URClassDetail.check_dict_is_enum(members[name]):
					members.erase(name)
		return members
	var getter = {"methods": "get_script_method_list", "signals": "get_script_signal_list",
			"properties": "get_script_property_list"}.get(kind, "")
	if getter.is_empty():
		return members
	var entries:Array = script.call(getter)
	var base = script.get_base_script()
	if not inherited and base != null:
		# GDScript appends the complete base list after its own declarations (including
		# overrides). Remove that suffix before indexing, without relying on source code
		# or editor-only metadata, so this also works in binary exports.
		var base_entries:Array = base.call(getter)
		entries.resize(entries.size() - base_entries.size())
	for entry in entries:
		var name = str(entry.get("name", ""))
		if not members.has(name):
			members[name] = entry # Derived declarations precede their inherited counterparts.
	return members
