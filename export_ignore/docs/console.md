# Runtime console

`GDSh.Console` is an instantiable `VBoxContainer` with a prompt row and one-line
`CodeEdit`. It owns its main context, history, completion state, and last result.

```gdscript
var console = GDSh.Console.new()
console.load("res://commands")
console.load("res://debug_commands", true) # Executable, hidden from root completion.
add_child(console)

var transcript = console.create_output() # Optional and idempotent.
```

The input provides syntax highlighting, delayed completion, Tab completion, and
Up/Down history. Enter submits without adding a line, and pasted newlines become
spaces. The completion popup sizes itself to its choices and scrolls after it
reaches half the window height.

## Execution and output

```gdscript
console.command_submitted.connect(func(text): print("running ", text))
console.command_finished.connect(func(text, result):
    print(result.stdout)
    printerr(result.stderr)
)

var result = console.execute("echo hello")
print(console.context.cwd)
print(console.last_result.exit_code)
```

Each submission runs in a linked child context. Variables, aliases, functions,
working directory, scopes, and `$?` persist in `console.context`; output and exit
control belong to the returned result. `exit` ends only its submission.
Programmatic `execute()` uses the same history, signals, transcript, and state
path as Enter.

The optional transcript echoes the prompt and command, then appends stdout and
highlighted stderr. `clear_output()` and `clear_history()` expose matching UI
actions without adding shell commands.

## Prompt and controls

The default prompt is `Console $` at `res://` and `Console <cwd> $` elsewhere.
Use `set_prompt(text, color)` for a fixed prompt and `reset_prompt()` to restore
the default. A formatter can derive it from context state:

```gdscript
console.prompt_formatter = func(ctx):
    return "Room %s >" % ctx.variables.get("$ROOM", "unknown")
```

Assigning a formatter replaces a fixed prompt. Call `update_prompt()` after
external state changes.

The public `prompt_label`, `input`, `prompt_row`, and optional `output` controls
can be styled or placed by the host. `get_text_edit()` and `get_prompt_label()`
return the primary controls. `add_font_override(font)` applies a font to them and
the transcript; `remove_font_override()` restores inherited theme fonts.

The bundled JetBrains Mono editor source font remains under the
[SIL Open Font License](../../internal/source_font.LICENSE.txt).

While focused, the input consumes keyboard press, release, and repeat events. The
transcript consumes wheel and pan gestures, including at its scroll limits, so
these events do not reach gameplay handlers in the unhandled-input stages.

Pass an existing context to `GDSh.Console.new(context)` or replace it with
`set_context(context)`. OS mode is not part of this component.
