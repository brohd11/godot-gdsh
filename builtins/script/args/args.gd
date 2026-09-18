extends "res://addons/addon_lib/gdsh/command_base.gd"

const ScriptUtil = preload("res://addons/addon_lib/gdsh/builtins/script/script_util.gd")

const URClassDetail = UtilR.Objects.URClassDetail
const PrintRich = UtilR.Strings.PrintRich

const _TYPE_COLOR = Color("4d819a")
const _UNTYPED_COLOR = Color("cc000c")

var show_private:=false


static func get_command_name() -> String:
	return "args"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": ScriptUtil.get_usage_string(
			"List the arguments of a method in the target script",
			"args <options> <method_name>"
		),
		&"positional_count": 1,
	})


func _get_flags():
	var options = Options.new()
	options.add_option("--private", {
		&"help": "Include private (underscore-prefixed) methods."
	})
	return options.get_options()


func _process_flag(flag:String):
	if flag == "--private":
		show_private = true


func _get_completions(ctx:Completion):
	if not is_instance_valid(ScriptUtil.get_script_from_ctx(ctx.context)):
		return {}
	var flags = get_flags(true)
	var methods = ScriptUtil.get_methods_from_ctx(ctx.context, show_private, false, false)
	if not ctx.context.unconsumed_tokens.is_empty():
		var current_name = ctx.context.unconsumed_tokens.pop_front()
		if current_name in methods:
			return {}
	methods.merge(flags)
	return methods


func _execute(ctx:Context):
	var method_name = positional_args[0]
	var script = ScriptUtil.get_script_from_ctx(ctx)
	if not is_instance_valid(script):
		ctx.append_error("Could not get script.")
		return ExitCode.FAIL
	var methods = ScriptUtil.get_methods_from_ctx(ctx, show_private, false, false)
	if not method_name in methods:
		ctx.append_error("Unrecognized method: " + method_name)
		return ExitCode.FAIL
	return list_args(script, method_name, ctx)


static func list_args(script, method_name:String, ctx:Context):
	var property_info = URClassDetail.get_member_info_by_path(script, method_name)
	if property_info is not Dictionary:
		ctx.append_error("Could not get method '%s' in script: %s" % [method_name, script])
		return ExitCode.ERR
	var args_array = property_info.get("args", [])
	if args_array.is_empty():
		ctx.append_output("No args to list.")
		return ExitCode.OK

	var pr = PrintRich.new()
	for dict in args_array:
		var arg_name = dict.get("name")
		var type = type_string(dict.get("type"))
		var color = _UNTYPED_COLOR if type == "Nil" else _TYPE_COLOR
		pr.append(arg_name + ":").append(type, color).append("  ")

	ctx.append_output(pr.get_string())
	return ExitCode.OK
