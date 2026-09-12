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

`load_builtins()` includes the hidden `builtins` parent and the direct built-in
registrations. Both `echo hello` and `builtins echo hello` work in a default
context. Neither appears in root completion; `builtins ` offers public built-in
names and delegates further completion to the selected child. Run `builtins` or
`builtins --help` to list them, and `builtins echo --help` for a child's help.

Directory loading recognizes loose `.gd` files and `name/name.gd` entries. A
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
