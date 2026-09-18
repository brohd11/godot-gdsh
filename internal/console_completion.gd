extends RefCounted
## UI-independent completion filtering and insertion shared by both console inputs.
const Options = preload("res://addons/addon_lib/gdsh/options.gd")

static func choices(request) -> Dictionary:
	var result = request.get_completions().duplicate(true)
	result.erase(Options.Keys.COMMAND_META)
	var needle = "" if request.char_before_cursor in ["", " ", "\t", "\n"] else request.token_before_cursor
	_filter_choices(result, needle)
	_clean_up_separators(result)
	return result


static func replacement(request, caret:int, choice:String, data:Dictionary) -> Dictionary:
	var metadata:Dictionary = data.get(Options.Keys.METADATA, {})
	var insertion = str(metadata.get(Options.Keys.INSERT, choice))
	insertion += str(metadata.get(Options.Keys.TRAILING_CHAR, " "))
	var start = caret
	if metadata.get(Options.Keys.REPLACE_WORD, true) and request != null \
			and not request.char_before_cursor in ["", " ", "\t", "\n"]:
		start = maxi(0, caret - request.token_before_cursor.length())
	return {"start": start, "text": insertion}


static func _filter_choices(choices:Dictionary, needle:String) -> void:
	if needle.length() < 2:
		return
	for choice in choices.keys():
		if choice == Options.Keys.COMMAND_META or Options.Keys.get_seperator(str(choice)) != null:
			continue
		var metadata:Dictionary = choices[choice].get(Options.Keys.METADATA, {})
		if needle.is_subsequence_ofn(str(choice)) \
				or needle.is_subsequence_ofn(str(metadata.get(Options.Keys.INSERT, choice))):
			continue
		choices.erase(choice)


static func _clean_up_separators(choices:Dictionary) -> void:
	var keys = choices.keys()
	keys.reverse()
	var has_choice := false
	for choice in keys:
		if Options.Keys.get_seperator(str(choice)) != null:
			if not has_choice:
				choices.erase(choice)
			has_choice = false
		else:
			has_choice = true
