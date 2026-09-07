extends RefCounted
const Context = preload("res://addons/addon_lib/gdsh/context.gd")
const Types = preload("res://addons/addon_lib/gdsh/internal/types.gd")
const ExitCode = Types.ExitCode
static var _clean_output_regex:RegEx

enum Propagate{
	VARIABLES,
	FUNCTIONS,
	ALIASES,
	PROPERTY,
}

var title:String


var execute:bool = true
var unconsumed_tokens:= []
var data := {}

var parent_ctx:Context

var positional_args := []
var variables := {}
var functions := {}
var aliases := {}
var scopes := {}

var cwd:String = "res://"

var stdin:String
var stdout:String
var stderr:String
var last_status:int = ExitCode.OK
var exit_code:int = ExitCode.OK
var exit_requested:=false


var raw_text:String


func _init(text:="", include_builtins:=true) -> void:
	title = text if not text.is_empty() else "GDSh Context"
	raw_text = text
	if include_builtins:
		scopes = load("res://addons/addon_lib/gdsh/load.gd").load_builtins()

func set_positional_args(path_or_name:String, args:Array):
	variables["$0"] = path_or_name
	positional_args = args

func execute_parse():
	var tokenizer = load("res://addons/addon_lib/gdsh/internal/tokenizer.gd").new(self)
	tokenizer.execute = true
	var token_data = tokenizer.parse_command_string_execute(raw_text)
	unconsumed_tokens = token_data.expanded
	execute = true

func tokens_empty_and_execute() -> bool:
	return unconsumed_tokens.is_empty() and execute

func tokens_empty() -> bool:
	return unconsumed_tokens.is_empty()

func append_output(line:String) -> void:
	if  line.is_empty():
		return
	stdout += line.trim_suffix("\n") + "\n"

func strip_output_newlines():
	stdout = stdout.lstrip("\n").rstrip("\n")
	return stdout

func clean_output():
	return clean_text(stdout)

func clean_text(text:String):
	if not is_instance_valid(_clean_output_regex):
		_clean_output_regex = RegEx.new()
		_clean_output_regex.compile("\\[color=[A-Za-z0-9]*]|\\[\\/color]")
	return _clean_output_regex.sub(text, "", true)


func append_error(line:String) -> void:
	if line.is_empty():
		return
	stderr += line.trim_suffix("\n") + "\n"

func strip_error_newlines():
	stderr = stderr.lstrip("\n").rstrip("\n")
	return stderr

func get_variable(name:String):
	return load("res://addons/addon_lib/gdsh/internal/tokenizer.gd").check_variable(name, self)

func get_root_ctx():
	var inherited = get_inherited_ctxs()
	if inherited.is_empty():
		return self
	return inherited.back()

func get_inherited_ctxs():
	var inherited = []
	if not is_instance_valid(parent_ctx):
		return inherited
	var parent:Context = parent_ctx
	while is_instance_valid(parent):
		inherited.append(parent)
		parent = parent.parent_ctx

	return inherited


static func new_ctx(text:String, parent:Context=null, sub_shell:=false):
	var ctx = load("res://addons/addon_lib/gdsh/context.gd").new(text, not is_instance_valid(parent))
	if is_instance_valid(parent):
		if not sub_shell: # so that function definitions do not populate up
			ctx.parent_ctx = parent

		ctx.cwd = parent.cwd
		ctx.execute = parent.execute


		ctx.variables = parent.variables.duplicate()
		ctx.functions = parent.functions.duplicate()
		ctx.aliases = parent.aliases.duplicate()
		ctx.scopes = parent.scopes.duplicate()

		 # non piped inherit stdin, this will be overwritten if piped
		ctx.stdin = parent.stdin
		ctx.last_status = parent.last_status

	return ctx

func write_to_parent(parent:Context):
	parent.append_output(stdout.trim_suffix("\n"))
	parent.append_error(stderr.trim_suffix("\n"))
	exit_code = last_status
	parent.last_status = exit_code

func propogate(target:Propagate, key:String, value):
	var inher = get_inherited_ctxs()
	inher.append(self)
	match target:
		Propagate.VARIABLES:
			for inh:Context in inher:
				inh.variables[key] = value
		Propagate.FUNCTIONS:
			for inh:Context in inher:
				inh.functions[key] = value
		Propagate.ALIASES:
			for inh:Context in inher:
				inh.aliases[key] = value
		Propagate.PROPERTY:
			for inh:Context in inher:
				inh.set(key, value)
