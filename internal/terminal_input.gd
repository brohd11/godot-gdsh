extends RefCounted
## Single-line editing state. Display selection deliberately does not participate.
signal changed

const WORD_DELIMITERS = [" ", "\t", ".", "/", "'", '"', "="]
var text:String
var caret:int


static func normalize(value:String) -> String:
	return value.replace("\r\n", "; ").replace("\r", "; ").replace("\n", "; ").replace("\t", " ")


func set_text(value:String) -> void:
	text = normalize(value)
	caret = text.length()
	changed.emit()


func move_to(index:int) -> void:
	caret = clampi(index, 0, text.length())
	changed.emit()


func replace(start:int, end:int, value:String) -> void:
	start = clampi(start, 0, text.length())
	end = clampi(end, start, text.length())
	value = normalize(value)
	text = text.erase(start, end - start).insert(start, value)
	caret = start + value.length()
	changed.emit()


func insert(value:String) -> void:
	replace(caret, caret, value)


func word_left() -> int:
	var index = caret
	while index > 0 and text[index - 1] in [" ", "\t"]:
		index -= 1
	if index > 0 and text[index - 1] in WORD_DELIMITERS:
		index -= 1
	while index > 0 and not text[index - 1] in WORD_DELIMITERS:
		index -= 1
	return index


func word_right() -> int:
	var index = caret
	while index < text.length() and text[index] in WORD_DELIMITERS:
		index += 1
	while index < text.length() and not text[index] in WORD_DELIMITERS:
		index += 1
	return index
