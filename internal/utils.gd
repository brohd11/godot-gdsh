## Local utility copies. Each using tag identifies the source function for synchronization.

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
