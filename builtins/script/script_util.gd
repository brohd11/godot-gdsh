extends RefCounted
## Resolve a script target for the `script` command: a global class name, a res://, user:// or
## absolute OS path, or a path relative to ctx.cwd. Member access (Outer.Inner) walks into inner
## classes. The "current editor script" form is a host hook, so core stays editor-free.

const Options = preload("res://addons/addon_lib/gdsh/options.gd")

const URString = UtilR.Strings.URString
const URClassDetail = UtilR.Objects.URClassDetail

const CONSOLE_METHODS = ["parse", "get_completion", "execute", "complete"]

const USAGE_TEMPLATE = \
"Usage: script [--path=res://my_path.gd|--class=GlobalClass] %s
Usage: GlobalClass %s"


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


static func get_methods_from_ctx(ctx, show_private:bool, static_only:=false, hide_console_methods:=true):
	return get_method_completions(ctx.data.get("script"), show_private, static_only, hide_console_methods)


static func get_method_completions(script, show_private:bool, static_only:=false, hide_console_methods:=true):
	var options = Options.new()
	if not is_instance_valid(script):
		return options.get_options()
	for method in script.get_script_method_list():
		var name = method.get("name")
		if hide_console_methods and name in CONSOLE_METHODS:
			continue
		if not show_private and name.begins_with("_"):
			continue
		if static_only and not (method.get("flags") & METHOD_FLAG_STATIC):
			continue
		options.add_option(name, {
			&"metadata": {Options.Keys.ARG_COUNT: method.get("args").size()}
		})
	return options.get_options()
