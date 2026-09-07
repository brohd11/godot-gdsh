# GDSh

GDSh is a runtime copy of Editor Console's GDSh execution engine for games and
application consoles. It requires Godot 4.6 or newer. It has no plugin, autoload,
editor-only UI, or Editor Console dependency.

Editor Console keeps its own implementation, commands, and OS mode. GDSh does not
include OS mode or the `os` command. A future host adapter would need to preserve
whole-command shell dispatch and unresolved environment variables as well as the
`os` prefix; that migration is outside this package.

## Execute scripts

```gdscript
var context = GDSh.Context.new()
GDSh.Execute.execute_command_multiline("""
name = player
echo Hello $name
for item in sword shield {
    echo $item
}
""", context)

print(context.stdout)
print(context.stderr)
print(context.exit_code)
```

Reuse a context for a persistent session. Variables, aliases, functions, command
scopes, and the working directory belong to that context. Independent contexts
have independent dictionaries. The default working directory is `res://`, which
also works in exported games; `cwd` can also be a `user://` or absolute OS path.

Execution is synchronous. Output accumulates in `stdout` and `stderr`; clear those
strings when the host has consumed them. `last_status` is the last command's status,
and `exit_code` is the execution result. The codes are `OK=0`, `FAIL=1`, `ERR=2`, and
`HELP=3`. `exit N` marks the current execution context as stopped, preserving `N`;
it does not quit the game. Create a new session or explicitly reset
`exit_requested` before reusing a stopped context.

```gdscript
# Accepts the full script grammar, plus parent_ctx and sub_shell options.
var result = GDSh.Execute.execute_command("echo hello", {"parent_ctx": context})

# A source file must start with #!gdsh. Relative paths resolve against context.cwd.
GDSh.Execute.source_file("res://scripts/start.gdsh", context)
```

All three Execute entry points return their resulting Context. Omitting a context
creates a fresh session with builtins. `source` executes in the current scope;
invoking an absolute script path executes in a subshell with `$0`, `$1`, `$#`, and
`$@`. Quote script paths containing spaces.

## Console component

`GDSh.Console` is an instantiable runtime prompt. It is a `VBoxContainer` with an
always-present prompt row and a one-line `CodeEdit`. The Console owns its main
Context, command history, completion state, and the result of its last submission.

```gdscript
var console = GDSh.Console.new()
console.load("res://commands")
# Executable, but omitted from root completion:
console.load("res://debug_commands", true)
add_child(console)

# Optional: add a selectable RichTextLabel transcript above the prompt.
var transcript = console.create_output()
```

`load(path, hidden=false)` loads one command `.gd` file or a command directory and
returns its scope dictionary. Relative paths resolve from `context.cwd`. The
optional `hidden` argument keeps those commands out of root completion while
leaving execution and command-specific completion available. Each load is a new
layer: matching names replace earlier commands and move between visible and hidden
scopes according to the newest load.

The prompt CodeEdit supports syntax highlighting, delayed completion, Tab to show
or accept completion, and Up/Down history navigation. Its completion popup grows
and shrinks with the current choices and scrolls after reaching half the window
height. Enter submits without adding a line. Pasted newlines are converted to
spaces. The public `prompt_label`, `input`, `prompt_row`, and optional `output`
controls can be styled or placed by the host.

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

Each submission runs in a linked child Context. Variables, aliases, functions,
working directory, scopes, and `$?` persist in `console.context`, while stdout,
stderr, and exit control belong to the returned result. An `exit` command ends its
submission without disabling later console input. Programmatic `execute()` uses
the same history, signals, transcript, and state path as Enter.

`create_output()` is optional and idempotent. Its transcript echoes the prompt and
command, then appends stdout and highlighted stderr. `clear_output()` and
`clear_history()` provide UI actions without adding shell commands.

The default prompt is `Console $` at `res://`, or `Console <cwd> $` elsewhere.
Assign a formatter when the host needs different BBCode, then call
`update_prompt()` after external state changes:

```gdscript
console.prompt_formatter = func(ctx):
    return "Room %s >" % ctx.variables.get("$ROOM", "unknown")
```

Pass an existing Context to `GDSh.Console.new(context)` or replace it later with
`set_context(context)`. OS mode remains an Editor Console feature and is not part
of this component.

## Language and parsing

GDSh uses a shared lexer and recursive-descent parser for execution and completion.
The lexer retains source offsets, quoting, escapes, and nested substitution tokens.
The parser builds a command tree before execution; function declarations have a
name, `()`, and a parsed brace body. Function bodies run only when called.
`Context.functions` remains a dictionary of source strings; parsed bodies are
cached and refreshed when their source changes.

GDSh keeps its compact brace grammar. It is not a Bash implementation: Bash uses
`then`/`fi` for conditionals and treats braces differently. This is valid GDSh:

```sh
echo first; if [ someval == "" ]{echo yes} else {echo fail}
f(){if true{echo nested}else{echo no}}; f
for item in sword shield{echo $item}
```

A newline or `;` separates simple statements. A completed block can end a statement
without a separator. Operators and structural braces do not need surrounding
spaces. Ordinary arguments can contain balanced literal braces (`echo {a:1}`);
quote or escape braces that would otherwise start a block. Quotes and escapes
protect punctuation, and empty quoted arguments are retained. Single quotes are
literal; double quotes allow variables and `$(...)`. An unquoted substitution
splits output on whitespace, while a quoted substitution remains one argument.

The operator precedence, highest first, is:

1. Redirections belong to the command or compound block they are attached to.
2. `|` connects stdout to the next command's stdin; stderr stays separate.
3. `&&` and `||` have equal precedence and evaluate left to right.
4. `;` and newlines separate statements.

A pipeline returns its last command's status. For example, `a || b | c && d`
means `a || (b | c)`, followed by `&& d`. Commands skipped by a logical operator
or branch do not expand variables or run substitutions. Expanded values remain
argument data rather than becoming operators. GDSh retains recursive variable
expansion, including substitutions stored in variables. Aliases are explicitly
source fragments, parsed when invoked; alias cycles produce an error.

Assignments accept `name=value` or `name = value`; `local` limits a variable to the
current scope. Assignment values preserve spacing, support quotes and substitutions,
and end at a statement, logical, pipeline, or redirection operator. Alias definitions
can contain pipelines and logical operators; use `;` or a newline to end them.

Syntax errors anywhere in the submitted script prevent the entire submission from
running, including errors in unused blocks or direct substitutions. Diagnostics
include a line and column, return `ERR`, and leave the session reusable. Aliases,
externally supplied function source, and sourced files are checked when reached.
Unsupported shell operators are rejected rather than passed as command arguments.
Quote operator characters when they are intended as data.

## Discard output

Redirection currently supports the literal target `discard`, with `/dev/null` as
an equivalent portable spelling. It does not open an OS device or file.

| Syntax | Effect |
| --- | --- |
| `command >discard` or `command 1>discard` | Discard stdout |
| `command 2>discard` | Discard stderr |
| `command &>discard` | Discard both streams |

Descriptors must touch the operator: `2>` redirects stderr, while `2 >` passes `2`
as an argument and redirects stdout. Redirections may precede a simple command or
appear among its arguments; they are removed before flag and argument routing.
They can also follow an `if`, loop, subshell, or function call:

```sh
unknown_command 2>discard || echo recovered
if true{echo hidden}>discard
f(){echo hidden;return 4}; f &>discard
```

Discarding output preserves exit status, control flow, and variable scope.
A command's stdout redirection overrides its pipe destination:
`echo hidden >discard | sink` gives `sink` empty stdin. Output emitted before or
after a redirected command is preserved.

File output, append/input redirection, descriptor copying such as `2>&1`, `|&`,
background execution, and redirection on function *declarations* are unsupported.
Attach a redirection to a function call instead.

## Load commands

Commands extend `GDSh.CommandBase`. Their execution hook receives `GDSh.Context`.

```gdscript
# res://commands/look.gd
extends GDSh.CommandBase

static func get_command_name():
    return "look"

static func get_self_command_data():
    return _command_data({"help": "Describe the room"})

func _execute(ctx:Context):
    ctx.append_output("A wooden door leads north.")
    return ExitCode.OK
```

```gdscript
var context = GDSh.Context.new()
context.load("res://commands/look.gd")
context.load("res://commands")
# Hidden commands still execute, but do not appear at the root of completion.
context.load("res://internal_commands", true)
GDSh.Execute.execute_command("look", {"parent_ctx": context})
```

`Context.scopes` contains visible commands and `Context.scopes_hidden` contains
hidden commands. `has_scope(name)` and `get_scope(name)` resolve both dictionaries,
with a visible entry winning if callers directly introduce the same name into
both. Prefer `Context.load(path, hidden)` when layering commands because it removes
the matching name from the other dictionary. The lower-level
`GDSh.Load.load_command()` and `load_directory()` functions remain available when
manual registration is useful.

Directory loading accepts both immediate `name.gd` files and `name/name.gd`
entries. A parent such as `door/door.gd` discovers its children in directories such
as `door/open/open.gd`; `door open` routes to that child. Loose files do not acquire
neighboring directories as children. Override `_get_commands()` for an explicit
subcommand dictionary.

Scripts must extend CommandBase and return a nonempty command name. Missing or
invalid scripts return `null` and report an error. Directory loading skips invalid
entries, sorts paths, and reports duplicate names while retaining the first valid
registration. Loading uses Godot's resource cache; there is no editor hot reload.

Command metadata, flags, positional counts, `--` payloads, and per-command
`--help` retain the Editor Console command format. `GDSh.Options` constructs the
same options dictionaries. Icons are caller-supplied data (textures or identifiers),
with no editor-icon lookup. UI code is responsible for displaying suggestions and
interpreting insertion metadata; `Options.Keys.COMMAND_META` is not a suggestion.

## Completion

```gdscript
var completion = GDSh.Completion.new("door open n", context)
var suggestions = completion.get_completions()

# The optional caret is an offset into the full input; defaults to its end.
var at_caret = GDSh.Completion.new(input_text, context, caret_offset)
```

Completion owns text, caret and token information, routed positional arguments,
and payload indices. Each request runs the command router on an isolated Context,
then calls `_get_completions(completion:Completion)` on the selected command.
`completion.context` exposes the temporary routing context. Execution Contexts
have no caret or UI fields. Root suggestions include `Context.scopes` and functions,
but omit `scopes_hidden`. Once a hidden command name is typed, its flags and child
commands complete normally.

```gdscript
func _get_completions(completion:Completion):
    var options = Options.new()
    options.add_option("north", {"help": "The wooden door"})
    options.add_option("south")
    return options
```

Return a dictionary or Options object. Existing CommandBase flag processing and
argument routing run before this hook, including nested commands. Completion uses
aliases and existing variables but never executes command substitutions, including
those reached through aliases, variables, or payloads. It leaves the supplied
context's variables, streams, and status unchanged. The parser accepts unfinished
quotes, blocks, substitutions, and redirection targets in completion mode; completion
inside a nested command routes to that command. Redirection targets suggest
`discard` and `/dev/null`. Suggestions are candidates;
the host can filter and render them for its UI.

## Builtins and dependencies

New contexts register `break`, `continue`, `return`, `exit`, `shift`, `true`,
`false`, `[`, `expr`, `echo`, `source`, `cd`, and `help`, plus internal function and
script invocation commands. All builtins start in `scopes_hidden`, which keeps a
host's root completion focused on the commands it loads. `help` is also hidden and
prints sorted `Commands` and `Hidden commands` sections; reserved internal names
beginning with `__` are omitted. Command-specific documentation remains available
through `<command> --help`. `GDSh.Load.load_builtins()` returns fresh scope data;
`GDSh.Context.new("", false)` creates a context without builtins.

The copied language retains assignments, aliases, functions, conditionals, loops,
pipes, logical operators, substitutions, and subshells. General shell utilities,
global-class command dispatch, persistent configuration, and editor method-call
conveniences are excluded. The existing 100-iteration `while` limit is retained.

This development version imports the runtime addon_lib string utilities, sorting,
class-inspection helper, and text-highlighting palette under
`addons/addon_lib/brohd/alib_runtime/`, including their transitive runtime
dependencies and UID sidecars. No generated ALib namespace is required. Bundling
those helpers into a standalone distribution is deferred. Internal scripts are
implementation details; public entry points are exposed through `GDSh`.

Exports must include dynamically loaded command scripts and any `.gdsh` files.
Use an appropriate export filter (for example, all resources plus `*.gdsh` in the
non-resource include filter). Command discovery handles exported `.gd` remaps.

## Validation

From the project root, with Python 3 and Godot available:

```sh
python3 tests/gdsh/run_headless.py --godot godot --export
```

The tests live in the separate plugin tests repository at `tests/gdsh/`.
The runner builds a temporary project containing only GDSh and its runtime
helper dependencies, imports it, and runs the tests outside the editor. `--export`
also exports binary scripts to a PCK and reruns the suite from an empty directory
using that pack. No export templates are needed for this pack-only check.
Use `--keep` to retain the temporary project. The negative loader tests intentionally
print diagnostics for missing, invalid, and duplicate commands.
