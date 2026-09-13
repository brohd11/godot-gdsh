# Commands and completion

Commands extend `GDSh.CommandBase`, and their execution hook receives a
`GDSh.Context`:

```gdscript
extends GDSh.CommandBase

static func get_command_name() -> String:
    return "greet"

static func get_self_command_data() -> Dictionary:
    return _command_data({&"help": "Greet the player"})

func _execute(ctx: GDSh.Context):
    ctx.append_output("Hello!")
    return ExitCode.OK
```

## Loading and command trees

```gdscript
var context = GDSh.Context.new()
context.load("res://commands/greet.gd")
context.load("res://commands")
context.load("res://debug_commands", true) # Hidden from root completion.
```

`load(path, hidden=false)` accepts one command `.gd` file or a directory and
returns its scope dictionary. Relative paths resolve from `context.cwd`. Each load
adds a layer: matching names replace earlier commands and move between visible
and hidden scopes according to the newest load.

`Context.scopes` contains visible commands and `Context.scopes_hidden` contains
hidden commands. `has_scope()` and `get_scope()` search both, preferring a visible
entry if a host inserts the same name into each. The lower-level
`GDSh.Load.load_command()`, `load_directory()`, and `load_builtins()` helpers are
available when direct scope construction is useful.

`load_builtins()` includes the `builtins` and `hidden` parents and the direct
built-in registrations. Both `echo hello` and `builtins echo hello` work; namespaced
calls use the bundled command even when a host overrides its top-level name.
`builtins ` completes public built-ins, and `builtins --help` lists them.

Command data may set `&"discoverable": false`. Root completion, `help`, and the
`hidden` listing omit such commands, but they still run by name and namespace
commands (directory children) list them. Built-in children are non-discoverable, so
`hidden` lists `builtins` rather than every built-in; use `hidden builtins echo`.
`hidden` routes to the context's discoverable `scopes_hidden` entries (except `__`
internals) by registered name, including host-loaded hidden commands.

Directory loading recognizes loose `.gd` files and `name/name.gd` entries. A loose
`manifest.gd` is skipped; it may preload the directory's commands so exporters
that follow preloads include them. A
directory-backed command automatically discovers subcommands stored as
`child/child.gd`; loose command files do not acquire sibling directories as
children. Override `_get_commands()` to provide a custom command tree.

Command scripts must extend `GDSh.CommandBase` and return a non-empty name. Invalid
commands report an error and are skipped. Directory loading is sorted and rejects
duplicate names after the first valid match. Loading uses Godot's resource cache,
so it does not provide hot reloading.

Command metadata, flags, positional counts, `--` payloads, and per-command
`--help` use the Editor Console command format. `GDSh.Options` builds the
dictionaries used by routing and completion. Icons are host-provided values;
hosts are responsible for filtering and rendering suggestions. Internal scripts
are implementation details, with public entry points exposed through `GDSh`.

## Completion

```gdscript
var completion = GDSh.Completion.new("greet ", context)
var choices = completion.get_completions()

# An optional third argument identifies the caret offset.
var at_caret = GDSh.Completion.new(input_text, context, caret_offset)
```

Commands can add choices by overriding `_get_completions()`:

```gdscript
func _get_completions(completion):
    var options = GDSh.Options.new()
    options.add_option("player", {&"help": "Greet the player"})
    return options
```

Completion uses the parser and routes through a linked context exposed as
`completion.context`. Existing flags and arguments are processed before
`_get_completions()` runs. Variables, aliases, functions, command scopes, and the
working directory remain available, but command substitutions are never
executed. The host context's variables, streams, and status are not mutated.

Root completion includes visible commands and functions but not `scopes_hidden`;
once a hidden command is entered, its command-specific completion remains
available. The parser also supports completion inside nested commands and
incomplete quotes, blocks, substitutions, and redirection targets. Redirection
targets include `discard` and `/dev/null`. `_get_completions()` may return a
dictionary or `GDSh.Options` object.

Exports must include dynamically loaded `.gd` command files. See
[Distribution and validation](distribution.md).

## Host integrations

`Context.scope_resolver` is an optional `Callable(name, context)` returning a
scope dictionary (`{"script": command_script_or_object}`) or `null`. Registered
scopes take precedence. Execution and completion use the same resolver; it must
be free of command execution and session mutations. Child and subshell contexts
inherit the resolver.

A host can opt command names into raw arguments through
`context.raw_commands: Array[String]`, or call `context.collect_raw_commands()`
to collect registered commands whose data declares `&"raw": true` (static data
only; nothing is instantiated). Child contexts share the list. These names
reserve their argument syntax at command positions; a raw command reached
through subcommand routing reports an error instead of running. Their command
objects implement:

```gdscript
func execute_raw(source:String, ctx:Context) -> int:
    # Interpret source here, only when the command is selected for execution.
    return ExitCode.OK

func complete_raw(source:String, completion:Completion) -> Dictionary:
    return {} # Never invoke execute_raw from completion.
```

The raw source preserves quotes and balanced groups; GDSh does not expand its
arguments or parse substitution bodies. Outer GDSh pipelines, conditionals,
statement boundaries, and redirections retain their normal meaning. Raw handlers
append output/error to their context and return an integer status. Hooks remain
available inside functions, sourced scripts, aliases, and command substitutions.
With no raw names configured, the language is unchanged.

`host_data["clear_callback"]`: `Callable(ctx, history:bool)` handles the `clear`
builtin (`clear [--history]`) and may return an exit status. `GDSh.Console` installs
a default for its transcript and history unless the key is already set; without a
callback `clear` fails with "no console is attached".

`Context.host_data` carries host services or bindings separately from `data`'s
per-command/control-flow state. Its dictionary is shallow-copied into child,
subshell, and completion contexts. Prefer weak references for UI bindings to
avoid retaining disposed controls. Hosts own the lifetime of shared objects.
No OS interpretation or editor-class resolution is built into these hooks.

## Utilities

`GDSh.Utils.Value.convert(arg, type, base_type="")` converts console strings to a
`Variant.Type`: bools, numbers, `StringName`, array literals, tuples such as
`"(1, 2)"` or `"Vector2(1, 2)"`, html colors, and other `var_to_str` forms. With a
`base_type`, int targets also accept class constants (`"SIZE_FILL"`,
`"Control.SizeFlags.SIZE_FILL"`). It returns `null` when conversion is not possible.

`GDSh.Utils.Method.call_method(ctx, target, method, args, create_default_args=false,
object_default=Callable())` calls a method directly on `target`: a `Script` allows its
static methods, and any other object (an instance or a node from the tree) allows its
own. Argument types are checked and converted with `Value.convert`; missing trailing
arguments use declared defaults, and `create_default_args` fills the rest
(`object_default.call(class_name)` for object parameters). Errors and conversion notes
are appended to `ctx`. It returns `{"ok": bool, "result": Variant}`.
