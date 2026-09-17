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
preferring visible entries. See [Language](language.md#builtins) for builtin namespaces.

Directories accept loose `.gd` files and `name/name.gd` entries. Directory-backed
commands discover `child/child.gd` subcommands; override `_get_commands()` for custom
trees. A loose `manifest.gd` is skipped and may preload commands for export.
Loading is sorted, skips invalid commands, rejects later duplicate names within a
directory, and uses Godot's cache (no hot reload).

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

## Host integrations

`scope_resolver: Callable(name, context)` returns `{"script": command_script_or_object}`
or `null`. Registered scopes take precedence. Execution and completion share this
resolver, so it must not execute commands or mutate the session.

`host_data` holds services separately from command state in `data`. It is
shallow-copied into child, subshell, and completion contexts; hosts own shared
objects' lifetimes. Prefer weak references for UI bindings.

| `host_data` key | Contract |
| --- | --- |
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
