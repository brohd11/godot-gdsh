## Shared command helpers, exposed as GDSh.Utils. ALib copies carry a using tag
## identifying the source function for synchronization.

const _Paths = preload("res://addons/addon_lib/gdsh/internal/paths.gd")
## String-to-typed-value conversion: Value.convert(arg, type, base_type).
const Value = preload("res://addons/addon_lib/gdsh/internal/value.gd")
## Checked method calls on a Script (static) or any object: Method.call_method(ctx, target, name, args).
const Method = preload("res://addons/addon_lib/gdsh/internal/method_call.gd")

## Whether a scope entry appears in top-level listings (root completion, `hidden`, `help`).
## Commands opt out with `&"discoverable": false`; namespace commands list them regardless.
static func is_discoverable(scope) -> bool:
	if not scope is Dictionary:
		return true
	var command = scope.get("script")
	if command == null or not (command is GDScript or command.has_method("get_self_command_data")):
		return true
	return command.get_self_command_data().get(&"discoverable", true)

## BBCode color span; `[` in text is escaped so it renders literally.
static func color_text(text:String, color:Color) -> String:
	return "[color=%s]%s[/color]" % [color.to_html(false), text.replace("[", "[lb]")]

## Host hook: project file (or directory) paths. A host may supply a cached
## `ctx.host_data["file_paths"]: Callable(directories:bool)`; otherwise res:// is walked.
static func file_paths(ctx, directories:=false) -> PackedStringArray:
	var hook = ctx.host_data.get("file_paths") if ctx != null else null
	if hook is Callable and hook.is_valid():
		return PackedStringArray(hook.call(directories))
	var result = PackedStringArray()
	_walk_all("res://", directories, result)
	return result

## Paths.walk lists resources only; utilities need plain files too. Resource names keep
## exported scripts as .gd, while export and import sidecars are skipped.
static func _walk_all(path:String, directories:bool, result:PackedStringArray) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	var files = {}
	for entry in _Paths.list_directory(path):
		if not entry.ends_with("/"):
			files[entry] = true
	for file in dir.get_files():
		if not file.get_extension() in ["remap", "import", "uid", "gdc"]:
			files[file] = true
	if not directories:
		for file in files:
			if not str(file).begins_with("."):
				result.append(path.path_join(file))
	for child in dir.get_directories():
		var full_path = path.path_join(child)
		if child.begins_with(".") or dir.is_link(full_path):
			continue
		if directories:
			result.append(full_path)
		_walk_all(full_path, directories, result)

## Host hook: notify the host that commands changed files on disk, through
## `ctx.host_data["filesystem_changed"]: Callable()`. Without one this does nothing.
static func filesystem_changed(ctx) -> void:
	var hook = ctx.host_data.get("filesystem_changed") if ctx != null else null
	if hook is Callable and hook.is_valid():
		hook.call()

#! using ALibRuntime.Utils.UString.Methods.unquote()
static func unquote(text:String):
	#return text.trim_prefix('"').trim_prefix("'").trim_suffix('"').trim_suffix("'")
	if text.begins_with("&") and is_string_or_string_name(text):
		text = text.trim_prefix("&")

	if text.begins_with("'") and text.ends_with("'"):
		return text.trim_prefix("'").trim_suffix("'")
	elif text.begins_with('"') and text.ends_with('"'):
		return text.trim_prefix('"').trim_suffix('"')
	return text

#! using ALibRuntime.Utils.UString.Methods.is_string_or_string_name()
static func is_string_or_string_name(text:String):
	if text.begins_with("r"):
		text = text.trim_prefix("r")
	elif text.begins_with("&"):
		text = text.trim_prefix("&")
	return (text.begins_with("'") and text.ends_with("'")) or (text.begins_with('"') and text.ends_with('"'))

#! using ALibRuntime.Utils.USort.sort_dict_with_priority_key()
static func sort_dict_with_priority_key(dict:Dictionary, priority_key) -> Dictionary:
	var keys = dict.keys()
	# basic sort of priorities with ref to key
	keys.sort_custom(func(a, b):
		var pri_a = dict[a].get(priority_key, 1000)
		var pri_b = dict[b].get(priority_key, 1000)
		if pri_a != pri_b:
			return pri_a < pri_b
		else:
			return false) # if they are the same, just keep order

	var result_dict: Dictionary = {}
	for i in range(keys.size()):
		var current_key = keys[i]
		result_dict[current_key] = dict[current_key]

	return result_dict

#! using ALibRuntime.Utils.UGDScript.UClassDetail.get_all_global_class_paths()
static func get_all_global_class_paths():
	var class_dict = {}
	var global_class_list = ProjectSettings.get_global_class_list()
	for dict in global_class_list:
		var name = dict.get("class")
		var path = dict.get("path", "")
		class_dict[name] = path
	return class_dict
