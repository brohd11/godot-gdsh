extends RefCounted
## Shared runtime colors. Constructor overrides are Color values keyed by slot name.

const SLOTS = [
	"text", "comment", "string", "number", "control_flow", "function", "function_def",
	"variable", "string_name", "symbol", "bracket", "scope", "global_class",
	"unknown_variable", "alias",
]

var text := Color("#cdcfd2")
var comment := Color("#7b7f85")
var string := Color("#ffeda1")
var number := Color("#a1ffe0")
var control_flow := Color("#ff8ccc")
var function := Color("#57b3ff")
var function_def := Color("#66e6ff")
var variable := Color("#96f442")
var string_name := Color("#ffc2a6")
var symbol := Color(0.975, 0.703, 0.585)
var bracket := Color("#d1cc52")
var scope := Color.SKY_BLUE
var global_class := Color("#c7ffed")
var unknown_variable := Color("#6d6d6d")
var alias := Color("#6d6d6d")


func _init(overrides:Dictionary={}) -> void:
	for key in overrides:
		if not str(key) in SLOTS:
			push_error("GDSh.Palette: unknown color slot: " + str(key))
		elif not overrides[key] is Color:
			push_error("GDSh.Palette: expected Color for slot: " + str(key))
		else:
			set(str(key), overrides[key])
