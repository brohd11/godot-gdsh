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
spaces. Ctrl+Backspace deletes back to the previous space, `.`, `/`, quote, or
`=`; Left/Right close the completion popup. The completion popup sizes itself to
its choices and scrolls after it reaches half the window height.

The `clear` builtin clears the transcript (`clear --history` also clears history)
through a `clear_callback` the console installs in its context's `host_data`. A host
that sets its own callback first keeps it.

The transcript echoes each command with the input highlighter's colors through
`console.format_command(text)`, which uses the highlighter's `to_bbcode` when it
has one. Set `console.echo_values = true` to prefix variables and aliases with a
grey `[value]` preview. Previews read values only and never run substitutions.

## Syntax highlighting

The default `GDSh.Console.Highlighter` colors commands, functions, aliases, and
known versus unknown variables using the console's current context. It respects
quotes, escapes, comments, and command substitutions without evaluating input.
Redirection operators are colored even without spaces around them. Coloring an
operator such as `<<` does not make it supported by execution.

Global-class highlighting defaults to **off**, since another runtime may not
support invoking globals. Enable it explicitly when useful:

```gdscript
var syntax = GDSh.Console.Highlighter.new()
syntax.highlight_globals = true # Coloring only; does not enable execution.
syntax.set_palette(GDSh.Console.Palette.new({
    "scope": Color.SKY_BLUE,
    "variable": Color.GREEN,
}))
console.set_highlighter(syntax) # Also works before add_child(console).
```

`GDSh.Console.ScriptHighlighter` is the alternative for richer lexical coloring
of scripts, including strings, numbers, comments, and multiline constructs. It
uses GDSh's self-contained script tokenizer and accepts the same palette:

```gdscript
var syntax = GDSh.Console.ScriptHighlighter.new()
syntax.set_palette(GDSh.Console.Palette.new({"string": Color.LIGHT_YELLOW}))
console.set_highlighter(syntax)
```

Both are Godot `SyntaxHighlighter` objects and can also be assigned to a separate
`CodeEdit.syntax_highlighter`. For standalone console highlighting, call
`syntax.set_context(context)`. `console.set_highlighter()` accepts other Godot
syntax highlighters too, or `null` to disable highlighting.

The shared `Palette` is a `RefCounted` with hardcoded defaults. Constructor
overrides accept `Color` values under these property names:

| Slot | Default | Use |
| --- | --- | --- |
| `text` | `#cdcfd2` | Plain console text and script text |
| `scope` | `Color.SKY_BLUE` | Registered console commands, including hidden commands |
| `variable` | `#96f442` | Known console variables; script variables |
| `unknown_variable` | `#6d6d6d` | Unknown console variables |
| `alias` | `#6d6d6d` | Registered console aliases |
| `global_class` | `#c7ffed` | Registered global class names when enabled |
| `symbol` | `Color(0.975, 0.703, 0.585)` | Operators and delimiters |
| `function_def` | `#66e6ff` | Registered console functions; script function declarations |
| `function` | `#57b3ff` | Script command positions |
| `comment` | `#7b7f85` | Script comments |
| `string` | `#ffeda1` | Script strings |
| `number` | `#a1ffe0` | Script numbers |
| `control_flow` | `#ff8ccc` | Script control-flow keywords |
| `string_name` | `#ffc2a6` | Script string names |
| `bracket` | `#d1cc52` | Script brackets |

Each highlighter starts with an independent palette. Unknown override names and
non-Color values report errors and are skipped. Reapply `set_palette(palette)`
after editing palette properties to refresh colors; changing a shared palette
requires reapplying it to each highlighter using it. Passing `null` restores a
fresh default palette.

Console execution, command loading, and context replacement refresh highlighting.
After mutating context dictionaries directly, call
`syntax.clear_highlighting_cache()`. Changing `highlight_globals` or replacing
the palette/context also clears cached colors. Console literal text and comments
stay plain; choose the script highlighter for full lexical coloring.

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

## Custom submission and completion

Hosts may assign `console.execution_handler: Callable(text, result_context)` to
replace execution while retaining the normal history, signals, prompt updates,
transcript, and status lifecycle. The handler writes the supplied child context's
streams and status; leaving the callable empty uses `GDSh.Execute`.

`console.input.completion_factory: Callable(text, context, caret)` optionally
returns a `GDSh.Completion` instance or subclass. The existing popup, filtering,
replacement, debounce, and keyboard behavior are retained. Empty means the
standard GDSh completion request. Custom requests must not execute input.

Completion filtering matches either the display label or the option's `insert`
text using case-insensitive subsequence matching. An `insert` value replaces the
whole token before the caret by default, so path providers include the typed
directory prefix in it while displaying only the leaf name. Directory choices
append `/` to allow continued completion. Separators stay with surviving groups;
empty groups and trailing separators are removed after filtering.
