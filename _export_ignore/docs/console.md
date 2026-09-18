# Runtime console

`GDSh.Console` is a `VBoxContainer` with a one-line prompt, history, completion,
and optional transcript.

```gdscript
var console = GDSh.Console.new() # Optionally pass an existing context.
console.load("res://commands")
add_child(console)
console.create_output()
```

Enter submits, Tab completes, and Up/Down browse history. Pasted newlines become
spaces. Focused input consumes keyboard events; the transcript consumes scrolling.

## Execution and output

```gdscript
console.command_submitted.connect(func(text): print("running ", text))
console.command_finished.connect(func(text, result):
    print(result.stdout)
    printerr(result.stderr)
)

var result = await console.execute("echo hello")
print(result.exit_code)
```

Session state persists in `console.context`; each submission returns a child context
with its output and status, also available as `last_result`. `exit` ends only that
submission. Programmatic execution uses the same history, signals, and transcript as Enter.

The transcript streams output once per frame, with stderr in red. Set
`stream_output = false` to display output only after completion. Custom transcripts
should call `discard_pending_stream()` when clearing; subclasses can override
`_stream_chunk(text, is_error)` and `_stream_enabled()`.

- `clear` / `clear --history`: clear output, optionally history. Also available as
  `clear_output()` and `clear_history()`.
- `new_ctx`: end the submission and reset the context using `context_factory.call()`
  or a bare context. Use `reset_context()` or `set_context(context)` from code.
- `echo_values = true`: show variable and alias previews in echoed commands.

## Interactive views

Commands extending `GDSh.TUICommand` can temporarily take over the display and input.
The console restores its prompt, transcript, and focus when the command exits.

See [Writing TUI commands](tui.md) for a complete selectable-list example, the
`update()` / `view()` lifecycle, messages, scrolling, and `run()` for mixed-mode commands.

## Prompt and styling

The default prompt is `Console $`, including `cwd` outside `res://`.
Use `set_prompt(text, color)`, `reset_prompt()`, or a formatter:

```gdscript
console.prompt_formatter = func(ctx):
    return "Room %s >" % ctx.variables.get("$ROOM", "unknown")
```

A formatter replaces a fixed prompt. Call `update_prompt()` after external changes.
Style the public `prompt_label`, `input`, `prompt_row`, and `output` controls.
`add_font_override(font)` and `remove_font_override()` change their shared font.
The bundled JetBrains Mono font uses the [SIL Open Font License](../../internal/source_font.LICENSE.txt).

## Highlighting

The default `GDSh.Console.Highlighter` colors commands and session symbols.
Use `ScriptHighlighter` for strings, numbers, comments, and multiline script syntax.
Both accept the same palette:

```gdscript
var syntax = GDSh.Console.Highlighter.new()
syntax.set_palette(GDSh.Console.Palette.new({
    "scope": Color.SKY_BLUE,
    "variable": Color.GREEN,
}))
console.set_highlighter(syntax) # null disables highlighting.
```

Palette slots: `text`, `scope`, `variable`, `unknown_variable`, `alias`,
`global_class`, `symbol`, `function_def`, `function`, `comment`, `string`, `number`,
`control_flow`, `string_name`, `bracket`. Reapply `set_palette()` after editing colors;
`null` restores defaults.

Global-class coloring requires `syntax.highlight_globals = true` and does not enable
execution. For standalone `CodeEdit` use, assign `syntax_highlighter` and call
`syntax.set_context(context)` on the console highlighter. Clear its highlighting
cache after directly mutating context dictionaries. Highlighting never executes input.

## Custom execution and completion

- `execution_handler: Callable(text, result_context)` replaces execution while
  keeping the console lifecycle. Write output and status to the supplied context.
- `input.completion_factory: Callable(text, context, caret)` returns a
  `GDSh.Completion` instance or subclass. It must not execute input.

Completion filters labels and `insert` text by case-insensitive subsequence matching.
`insert` replaces the token before the caret, so path suggestions should include the
directory prefix and end directories with `/`.
