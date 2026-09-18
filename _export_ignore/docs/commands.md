# Commands and completion

Here is a command template you can copy:

```gdscript
# res://commands/greet.gd
extends GDSh.CommandBase

static func get_command_name() -> String:
    return "greet"

static func get_self_command_data() -> Dictionary:
    return _command_data({&"help": "Greet the player"})

func _execute(ctx: GDSh.Context):
    ctx.append_output("Hello!")
    return ExitCode.OK
```

Extend `GDSh.CommandBase`, provide a name and help metadata, and implement
`_execute(ctx)` returning an exit code.

Commands may `await`; execution and console input wait for them. Commands inside
`$(...)`(command substituion) must finish synchronously.

## Writing output

| Method | Behavior |
| --- | --- |
| `ctx.append_output(line)` / `append_error(line)` | Append one trailing newline; ignore empty text |
| `ctx.write_output(text)` / `write_error(text)` | Preserve text exactly, including blank and partial lines |

Use these methods instead of assigning stream buffers directly. They also send
screen-bound output to the host. Redirected streams, non-final pipeline stdout,
and substitution stdout are captured instead. `ctx.should_stream(is_error=false)`
reports whether a stream is screen-bound.

Long-running commands can yield for live display:

```gdscript
for path in paths:
    ctx.append_output(path)
    await GDSh.Utils.yield_frame_if_due(ctx) # Rate limited; skips captured/unhosted output.
```

Hosts install `Callable(text:String, is_error:bool)` with `set_output_sink()`.
The sink runs inside the command's call stack: it must not await, execute commands,
or mutate the context. Child contexts inherit it; `push_output_sink()` and
`pop_output_sink()` temporarily replace and restore it.

## Loading and metadata

```gdscript
context.load("res://commands/greet.gd")
context.load("res://commands")
context.load("res://debug_commands", true) # Hidden from root completion.
```

Paths resolve against `context.cwd`; later loads replace matching names.
`scopes` and `scopes_hidden` hold commands; `has_scope()` and `get_scope()` search both,
preferring visible entries, then the host resolver, then bare target resolution.
`get_registered_scope()` stops before bare targets, for consumers such as highlighting.
See [Language](language.md#builtins) for builtin namespaces.

Directories accept loose `.gd` files and `name/name.gd` entries. Directory-backed
commands discover `child/child.gd` subcommands; override `_get_commands()` for custom
trees. A loose `manifest.gd` is skipped and may preload commands for export.
Loading is sorted, skips invalid commands, rejects later duplicate names within a
directory, and uses Godot's cache (no hot reload).

### Directory layout

```
res://commands/              <- context.load("res://commands")
├── greet.gd                 -> greet              loose file; a leaf command
├── manifest.gd                                    skipped; preloads for exporters
└── door/
    ├── door.gd              -> door               name matches its directory
    ├── door_util.gd                               helper; never a command
    └── open/
        ├── open.gd          -> door open
        └── slowly/
            └── slowly.gd    -> door open slowly   nesting has no depth limit
```

Only the load root turns loose `.gd` files into commands. Below it, a command
discovers children from subdirectories alone, so neighboring `.gd` files (like
`door_util.gd`) are free to be shared helpers. Nesting repeats one rule at every
level: a directory contributes a command only through the `name/name.gd` file that
matches it, and that file owns everything under it.

A loose script never adopts a sibling directory of the same name — `greet.gd`
beside `greet/` stays a leaf and `greet/`'s contents are ignored. Move it to
`greet/greet.gd` to give an existing command subcommands. Children sort by their
`&"priority"` command data key, then by name.

Command data describes help, flags, positional counts, and `--` payloads.
`GDSh.Options` builds routing and completion dictionaries. Setting
`&"discoverable": false` hides a command from root completion, `help`, and `hidden`,
while keeping direct invocation and directory-child listings available.

Boolean flags can declare grouped one-letter aliases:

```gdscript
options.add_option("--recursive", {&"short": "r", &"help": "Descend into children"})
options.add_option("--pretty", {&"short": "p", &"help": "Indented output"})
# -rp means --recursive --pretty.
```

`h` is reserved; value flags cannot have short aliases. Commands declaring short
flags reject unknown letters in groups. Quote dash-leading arguments (`'-x'`);
commands without short flags treat them normally. Numbers such as `-5` stay arguments.

## Completion

```gdscript
var completion = GDSh.Completion.new(input_text, context, caret_offset)
var choices = completion.get_completions()
```

The caret offset is optional. Commands return a dictionary or `GDSh.Options`:

```gdscript
func _get_completions(completion):
    var options = GDSh.Options.new()
    options.add_option("player", {&"help": "Greet the player"})
    return options
```

`completion.context` contains processed flags and arguments plus session state.
Completion does not execute substitutions or mutate host state. Hidden commands
complete after being entered; incomplete syntax and redirection targets are supported.
Hosts provide icons and render suggestions.

## Script and node targets

A command position resolves in this order: registered visible scope, registered hidden
scope, host `scope_resolver`, then a bare target. Bare targets select the registered
handler, so hosts can replace `script`, `node`, or `gdsh`.

| Bare token | Handler |
| --- | --- |
| `.gdsh` path | `gdsh` |
| `.gd` path | `script` |
| Global class name, optionally followed by inner-class access | `script` |
| Absolute node path or a node relative to `cwn` | `node` |
| Both a global class and a node | Error: use `script X` or `node X` |

`script <class|path.gd>` accepts resource paths, absolute OS paths, and paths relative
to `cwd`; `--path=` and `--class=` are equivalent selectors. A script loaded from
outside the project has no resource path. `script` with no target uses the host's
`current_script` hook. `script --text` prints the resource's source code, or fails
with a diagnostic if source was stripped in a binary export.

`node <path>` selects a live node, with `cn <path>` changing the current working node.
Without a subcommand, a node prints its absolute path, suitable for `tree inspect`.
`node ./Child` and `node ..` use normal node-path traversal.

Both targets share these subcommands:

| Subcommand | Behavior |
| --- | --- |
| `call <method> -- [args...]` | Call a static method on a Script, or an instance/static method on a Node; convert fixed arguments and use declared defaults |
| `args <method>` | Print a method signature's arguments, including `...args` for varargs; Script instance signatures may also be inspected |
| `list` | List methods, signals, constants, properties and enums; narrow with `--methods`, `--signals`, `--constants`, `--properties`, or `--enums` |
| `get_path` | Print a Script's resource path (or a no-path message) or a Node's absolute path |

`call`, `args`, and `list` default to declarations on the target's own script.
`--inherited` includes base scripts; `--engine` includes base scripts and the engine
surface. For scriptless nodes, use `--engine`. Live property lists also expose dynamic
properties with `--engine`, omitting category/group/internal metadata entries.
`list --inherited` now selects base scripts; use `list --engine` for native members.

All three hide underscore-prefixed members unless `--private` is supplied. The flag
also permits explicit private calls and signature inspection. `call --default`
creates values for missing required arguments; declared defaults always work.
Varargs accept extra payload arguments without conversion, and still require their
fixed parameters. `list --data` includes metadata; `--pretty` compacts output.

```sh
MyGlobalClass call greeting -- world
script res://scripts/player.gd list --methods --inherited
cn /root/Main
Player call damage -- 5
Player args --engine call
Player | tree inspect
```

## Host integrations

`scope_resolver: Callable(name, context)` returns `{"script": command_script_or_object}`
or `null`. Registered scopes take precedence; a null result falls through to bare
target resolution. Execution and completion share this
resolver, so it must not execute commands or mutate the session.

`host_data` holds services separately from command state in `data`. It is
shallow-copied into child, subshell, and completion contexts; hosts own shared
objects' lifetimes. Prefer weak references for UI bindings.

| `host_data` key | Contract |
| --- | --- |
| `current_script` | `Callable() -> Script` supplies the target for `script` without an explicit target |
| `substitute_args` | `Callable(args:Array) -> Array` applies host substitutions to method-call payloads before conversion |
| `object_default` | `Callable(class_name:String) -> Object` supplies missing object arguments for `call --default` |
| `file_paths` | `Callable(directories:bool) -> PackedStringArray` supplies host paths for completion |
| `filesystem_changed` | `Callable()` asks the host to refresh after file writes; hosts also call `GDSh.Utils.clear_global_class_cache()` when the global class registry changes |
| `clear_callback` | `Callable(ctx, history:bool)` handles `clear [--history]`; may return a status |
| `new_ctx_callback` | `Callable(ctx)` handles `new_ctx`; may return a status. Ends the submission |
| `undo_redo` | `Callable() -> Object` supplies `UndoRedo` or a compatible object; null applies changes directly |
| `undo_session` | `GDSh.Undo.Session` buffer; retain it when rebuilding contexts per request |

The console supplies default clear/reset callbacks unless already set. Without a
callback, those builtins fail. Record changes with `ctx.undo_action(name)`; do not
also apply them manually. `undoredo --compound [name]` applies actions immediately,
then `undoredo commit [name]` records one undo entry or `undoredo cancel` reverts them.

### Raw commands

Set `context.raw_commands: Array[String]` or call `collect_raw_commands()` to
collect registrations with `&"raw": true`. Raw command objects implement:

```gdscript
func execute_raw(source:String, ctx:Context) -> int:
    return ExitCode.OK

func complete_raw(source:String, completion:Completion) -> Dictionary:
    return {}
```

Raw arguments preserve quotes and balanced groups without expansion or substitution
parsing. Outer pipelines, conditionals, statement boundaries, and redirections still
apply. Raw commands must appear at command positions; subcommand routing rejects
them. Completion must never invoke execution. Child contexts share the raw command list.

## Utilities

- `GDSh.Utils.Value.convert(arg, type, base_type="")` converts strings to typed
  values, including numbers, booleans, arrays, vectors, colors, and class constants
  for integer targets with a `base_type`. Returns `null` on failure.
- `GDSh.Utils.Method.call_method(ctx, target, method, args, create_default_args=false,
  object_default=Callable())` converts arguments, uses declared defaults, and calls
  instance or static script methods. Optional generated defaults use
  `object_default.call(class_name)` for objects. Returns `{"ok": bool, "result": Variant}`
  and appends diagnostics to `ctx`.

For exported command discovery, see [Distribution](distribution.md#exporting).
