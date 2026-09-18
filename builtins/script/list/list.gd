extends "res://addons/addon_lib/gdsh/command_base.gd"

const ScriptUtil = preload("res://addons/addon_lib/gdsh/builtins/script/script_util.gd")

const URClassDetail = UtilR.Objects.URClassDetail
const PrintRich = UtilR.Strings.PrintRich

const _ERROR_COLOR = Color("cc000c")
const _MEMBER_COLOR = Color("4d819a")

const LIST_COMMANDS_OPTIONS = ["--methods", "--signals", "--constants", "--properties", "--enums"]
const LIST_MODIFIER_OPTIONS = ["--data", "--inherited", "--pretty"]

const LIST_OPTION_HELP = {
	"--methods": {
		"help": "List the script's methods.",
		"prop": &"method_flag",
	},
	"--signals": {
		"help": "List the script's signals.",
		"prop": &"signal_flag",
	},
	"--constants": {
		"help": "List the script's constants.",
		"prop": &"const_flag",
	},
	"--properties": {
		"help": "List the script's properties.",
		"prop": &"prop_flag",
	},
	"--enums": {
		"help": "List the script's enums (requires --inherited).",
		"prop": &"enum_flag",
	},
	"--data": {
		"help": "Print each member's details.",
		"prop": &"data_flag",
	},
	"--inherited": {
		"help": "Include inherited members from the base class.",
		"prop": &"inh_flag",
	},
	"--pretty": {
		"help": "Print on a single line rather than new-lines.",
		"prop": &"pretty_flag",
	},
}

var target_all_flag:=true
var method_flag:=false
var signal_flag:=false
var const_flag:=false
var prop_flag:=false
var enum_flag:=false

var inh_flag:=false
var data_flag:=false
var pretty_flag:=false


static func get_command_name() -> String:
	return "list"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": ScriptUtil.get_usage_string(
			"List members of the target script",
			"list <options>"
		),
	})


func _get_flags() -> Dictionary:
	var options = Options.new()
	for cmd in LIST_COMMANDS_OPTIONS:
		options.add_option(cmd, {&"help": LIST_OPTION_HELP.get(cmd, {}).get("help", "")})
	options.add_separator("Modifiers")
	for cmd in LIST_MODIFIER_OPTIONS:
		options.add_option(cmd, {&"help": LIST_OPTION_HELP.get(cmd, {}).get("help", "")})
	return options.get_options()


func _process_flag(flag:String):
	var prop = LIST_OPTION_HELP.get(flag, {}).get("prop")
	if prop == null:
		return
	set(prop, true)
	if flag in LIST_COMMANDS_OPTIONS:
		target_all_flag = false


func _execute(ctx:Context):
	var script = ScriptUtil.get_script_from_ctx(ctx)
	if not is_instance_valid(script):
		ctx.append_error("Could not get script.")
		return ExitCode.FAIL
	return list_members(ctx, script)


func list_members(ctx:Context, script) -> int:
	var pr = PrintRich.new()
	for flag in LIST_OPTION_HELP.keys():
		if not flag in LIST_COMMANDS_OPTIONS:
			continue
		var prop = LIST_OPTION_HELP.get(flag).get("prop")
		if not (get(prop) == true or target_all_flag):
			continue

		var flag_raw = flag.trim_prefix("--")
		var members = _get_members(script, flag, inh_flag)
		if inh_flag:
			ctx.append_output("Class %s:" % [flag_raw])
		else:
			if flag == "--enums":
				if not target_all_flag:
					ctx.append_output("\tCannot get 'Script' enums, no API in ClassDB. Use '--inherited' option.")
				continue
			ctx.append_output("Script %s:" % [flag_raw])

		_add_to_members_to_output(ctx, members, pr)

	return ExitCode.OK


static func _get_members(script, flag:String, inherited:bool):
	match flag:
		LIST_COMMANDS_OPTIONS[0]: # methods
			return URClassDetail.class_get_all_methods(script) if inherited else URClassDetail.script_get_all_methods(script)
		LIST_COMMANDS_OPTIONS[1]: # signals
			return URClassDetail.class_get_all_signals(script) if inherited else URClassDetail.script_get_all_signals(script)
		LIST_COMMANDS_OPTIONS[2]: # constants
			return URClassDetail.class_get_all_constants(script) if inherited else URClassDetail.script_get_all_constants(script)
		LIST_COMMANDS_OPTIONS[3]: # properties
			return URClassDetail.class_get_all_properties(script) if inherited else URClassDetail.script_get_all_properties(script)
		LIST_COMMANDS_OPTIONS[4]: # enums
			return URClassDetail.class_get_all_enums(script) if inherited else {}
	return {}


func _add_to_members_to_output(ctx:Context, members:Dictionary, pr):
	if members.is_empty():
		var err_color = _ERROR_COLOR if pretty_flag else Color.TRANSPARENT
		pr.append("\tNone in script.", err_color)
		ctx.append_output(pr.get_string(true))
	elif pretty_flag and not data_flag:
		pr.append("\t" + "  ".join(members.keys()), _MEMBER_COLOR)
		ctx.append_output(pr.get_string(true))
	else:
		for m in members.keys():
			var member_color = _MEMBER_COLOR if pretty_flag else Color.TRANSPARENT
			pr.append("\t%s" % m, member_color)
			ctx.append_output(pr.get_string(true))
			if not data_flag:
				continue
			var data = members.get(m)
			if data == null:
				pr.append("\t\tNo data.")
				ctx.append_output(pr.get_string(true))
			elif data is String:
				ctx.append_output("\t\t" + data)
			elif data is Dictionary:
				for key in data.keys():
					pr.append("\t\t%s - %s" % [key, data[key]])
					ctx.append_output(pr.get_string(true))
			else:
				ctx.append_output("\t\t" + str(data))

	ctx.append_output("")
