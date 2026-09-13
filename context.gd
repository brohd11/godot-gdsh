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
# Parallel source metadata keeps quoted flag-like arguments literal.
var _token_metadata:Array = []
var _function_cache:Dictionary = {}
var data := {}
## Optional host integration. Hooks must not execute commands during completion.
var scope_resolver:Callable
var raw_commands:Array[String] = []
## Host services/bindings, separate from per-command control-flow data.
var host_data:Dictionary = {}

var parent_ctx:Context

var positional_args := []
var variables := {}
var functions := {}
var aliases := {}
var scopes := {}
## Commands that resolve normally but are omitted from root completion.
var scopes_hidden := {}

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
		scopes_hidden = ResourceLoader.load("res://addons/addon_lib/gdsh/load.gd").load_builtins()


## Load a command file or directory into this Context. New registrations replace
## the same name in either visibility dictionary.
func load(path:String, hidden:=false) -> Dictionary:
	var resolved = path
	if not path.is_absolute_path():
		resolved = cwd.path_join(path).simplify_path()
	var loader = ResourceLoader.load("res://addons/addon_lib/gdsh/load.gd")
	var loaded := {}
	if resolved.get_extension().to_lower() == "gd":
		var script = loader.load_command(resolved)
		if script != null:
			loaded[script.get_command_name()] = {Types.ScopeDataKeys.SCRIPT: script}
	else:
		loaded = loader.load_directory(resolved)
	var target = scopes_hidden if hidden else scopes
	var other = scopes if hidden else scopes_hidden
	for name in loaded:
		other.erase(name)
		target[name] = loaded[name]
	return loaded


func has_scope(name:String) -> bool:
	return get_scope(name) != null


func get_scope(name:String):
	if scopes.has(name):
		return scopes[name]
	if scopes_hidden.has(name):
		return scopes_hidden[name]
	if scope_resolver.is_valid():
		return scope_resolver.call(name, self)
	return null


## Set raw_commands to the registered names whose command data declares `raw`.
## Reads static command data only; no command is instantiated.
func collect_raw_commands() -> void:
	var names:Array[String] = []
	for registry in [scopes_hidden, scopes]:
		for name in registry:
			var command = registry[name].get(Types.ScopeDataKeys.SCRIPT)
			if command == null or not (command is GDScript or command.has_method("get_self_command_data")):
				continue
			if command.get_self_command_data().get(&"raw", false) and not name in names:
				names.append(name)
	raw_commands = names

func set_positional_args(path_or_name:String, args:Array):
	variables["$0"] = path_or_name
	positional_args = args

func execute_parse():
	var tokenizer = ResourceLoader.load("res://addons/addon_lib/gdsh/internal/tokenizer.gd").new(self)
	tokenizer.execute = true
	var token_data = tokenizer.parse_command_string_execute(raw_text)
	unconsumed_tokens = token_data.expanded
	_token_metadata = token_data.metadata
	if not token_data.error.is_empty():
		ResourceLoader.load("res://addons/addon_lib/gdsh/execute.gd")._parse_error(self, token_data.error)
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
	return plain_text(stdout)

func clean_text(text:String):
	return plain_text(text)

## Text with BBCode color markup removed, as output becomes data (pipes, $(...), files).
## Text without color tags is returned unchanged; `[lb]` escapes from Utils.color_text are restored.
static func plain_text(text:String) -> String:
	if not text.contains("[color="):
		return text
	if not is_instance_valid(_clean_output_regex):
		_clean_output_regex = RegEx.new()
		_clean_output_regex.compile("\\[color=[^\\[\\]]*\\]|\\[/color\\]")
	return _clean_output_regex.sub(text, "", true).replace("[lb]", "[")


func append_error(line:String) -> void:
	if line.is_empty():
		return
	stderr += line.trim_suffix("\n") + "\n"

func strip_error_newlines():
	stderr = stderr.lstrip("\n").rstrip("\n")
	return stderr

func get_variable(name:String):
	return ResourceLoader.load("res://addons/addon_lib/gdsh/internal/tokenizer.gd").check_variable(name, self)

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
	var ctx = ResourceLoader.load("res://addons/addon_lib/gdsh/context.gd").new(text, not is_instance_valid(parent))
	if is_instance_valid(parent):
		if not sub_shell: # so that function definitions do not populate up
			ctx.parent_ctx = parent

		ctx.scope_resolver = parent.scope_resolver
		ctx.raw_commands = parent.raw_commands # Host configuration, shared rather than copied.
		ctx.host_data = parent.host_data.duplicate()
		ctx.cwd = parent.cwd
		ctx.execute = parent.execute


		ctx.variables = parent.variables.duplicate()
		ctx.functions = parent.functions.duplicate()
		ctx.aliases = parent.aliases.duplicate()
		ctx.scopes = parent.scopes.duplicate()
		ctx.scopes_hidden = parent.scopes_hidden.duplicate()

		 # non piped inherit stdin, this will be overwritten if piped
		ctx.stdin = parent.stdin
		ctx.last_status = parent.last_status
		ctx.positional_args = parent.positional_args.duplicate()

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
