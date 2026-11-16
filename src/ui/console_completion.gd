extends RefCounted
## UI-independent completion filtering and insertion shared by both console inputs.
const Options = preload("res://addons/_lib/gdsh/src/core/options.gd")

static func choices(request) -> Dictionary:
	var result = request.get_completions().duplicate(true)
	result.erase(Options.Keys.COMMAND_META)
	_filter_choices(result, needle(request))
	_clean_up_separators(result)
	return result


## The partial word being completed; empty right after whitespace.
static func needle(request) -> String:
	if request == null or request.char_before_cursor in ["", " ", "\t", "\n"]:
		return ""
	return request.token_before_cursor


## Key of the choice the popup should preselect, or "" to keep the first row.
## Exact > case-sensitive prefix > prefix > similarity; ties keep list order.
static func best_match(choices:Dictionary, word:String) -> String:
	if word.is_empty():
		return ""
	var lower = word.to_lower()
	var best := ""
	var best_score := -1.0
	for choice in choices.keys():
		var key = str(choice)
		if choice == Options.Keys.COMMAND_META or Options.Keys.get_seperator(key) != null:
			continue
		var metadata:Dictionary = choices[choice].get(Options.Keys.METADATA, {})
		for text in [key, str(metadata.get(Options.Keys.INSERT, key))]:
			var score := -1.0
			if text.to_lower() == lower:
				score = 4.0
			elif text.begins_with(word):
				score = 3.0
			elif text.to_lower().begins_with(lower):
				score = 2.0
			elif word.is_subsequence_ofn(text):
				score = word.similarity(text) # 0..1, below any prefix hit.
			if score > best_score:
				best_score = score
				best = key
	return best


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
