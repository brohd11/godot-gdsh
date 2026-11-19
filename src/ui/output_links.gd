extends RefCounted
## Turns res:// and user:// file paths in command output into clickable links, so commands print
## plain text and every console renders the same links. Metas are always "path:line" (":0" when
## no line was given): EditorLog only opens metas with a line, and 0 there means "don't jump".

const _PATH_PATTERN = "(?:res|user)://[^\\s\\[\\]\"'<>(){},;:]+\\.\\w+(?::\\d+)?"
const _TAG_PATTERN = "\\[[^\\[\\]]*\\]"
## BBCode blocks whose contents must stay as written: wrapping inside them breaks the tag.
const _OPAQUE_TAGS = ["url", "img"]

static var _path_regex:RegEx
static var _tag_regex:RegEx


## Plain text as [{text, meta}] segments; meta is "" for text that is not a path.
static func split(text:String) -> Array:
	var segments = []
	var start = 0
	for m in _paths().search_all(text):
		if m.get_start() > start:
			segments.append({"text": text.substr(start, m.get_start() - start), "meta": ""})
		segments.append({"text": m.get_string(), "meta": _meta_for(m.get_string())})
		start = m.get_end()
	if start < text.length():
		segments.append({"text": text.substr(start), "meta": ""})
	return segments


## Wraps paths in BBCode text as [url]. Tags themselves and url/img contents are left alone.
static func to_bbcode(text:String) -> String:
	var out = ""
	var start = 0
	var opaque = ""
	for tag in _tags().search_all(text):
		var between = text.substr(start, tag.get_start() - start)
		out += between if opaque != "" else _wrap(between)
		var name = tag.get_string().trim_prefix("[").trim_suffix("]").get_slice("=", 0).get_slice(" ", 0).to_lower()
		if opaque == "" and name in _OPAQUE_TAGS:
			opaque = name
		elif opaque != "" and name == "/" + opaque:
			opaque = ""
		out += tag.get_string()
		start = tag.get_end()
	var rest = text.substr(start)
	return out + (rest if opaque != "" else _wrap(rest))


## Adds plain (non-BBCode) text to a RichTextLabel with its paths as meta links.
static func add_plain(rtl:RichTextLabel, text:String) -> void:
	for segment in split(text):
		if segment.meta.is_empty():
			rtl.add_text(segment.text)
		else:
			rtl.push_meta(segment.meta)
			rtl.add_text(segment.text)
			rtl.pop()


## {path, line} for a meta made here, or {} for any other meta.
static func parse_meta(meta) -> Dictionary:
	var text = str(meta)
	if not (text.begins_with("res://") or text.begins_with("user://")):
		return {}
	var parts = text.rsplit(":", true, 1)
	if parts.size() != 2 or not parts[1].is_valid_int():
		return {}
	return {"path": parts[0], "line": parts[1].to_int()}


static func _wrap(text:String) -> String:
	var out = ""
	for segment in split(text):
		out += segment.text if segment.meta.is_empty() else "[url=%s]%s[/url]" % [segment.meta, segment.text]
	return out


static func _meta_for(path:String) -> String:
	var tail = path.get_slice("://", 1)
	return path if tail.contains(":") else path + ":0"


static func _paths() -> RegEx:
	if _path_regex == null:
		_path_regex = RegEx.create_from_string(_PATH_PATTERN)
	return _path_regex


static func _tags() -> RegEx:
	if _tag_regex == null:
		_tag_regex = RegEx.create_from_string(_TAG_PATTERN)
	return _tag_regex
