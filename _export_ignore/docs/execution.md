# Execution and contexts

```gdscript
var context = GDSh.Context.new()
await GDSh.Execute.execute_command_multiline("echo hello", context)
var result = await GDSh.Execute.execute_command("echo hello", {"parent_ctx": context})
await GDSh.Execute.source_file("res://scripts/start.gdsh", context) # Starts with #!gdsh.
```

All entry points return a `Context`; omitting one creates a session with builtins.
Use `await` to support commands that pause. Synchronous commands finish in the calling frame.

## Context state

A context keeps variables, aliases, functions, command scopes, positional arguments,
and `cwd` (initially `res://`). Paths may also use `user://` or absolute OS paths.

| Field | Meaning |
| --- | --- |
| `stdout`, `stderr` | Accumulated output; clear after consuming |
| `last_status` | Last command's status (`$?`) |
| `exit_code` | Execution result: `OK=0`, `FAIL=1`, `ERR=2` |
| `output_sink` | Optional live output callback; see [Commands](commands.md#writing-output) |

BBCode is preserved for display and stripped from pipes, substitutions, and
redirected output. Use `GDSh.Context.plain_text()` for hosts without BBCode support.

`exit N` stops execution without quitting the game. Create a new context or reset
`exit_requested` before reusing a stopped context.

## Script files

Relative paths resolve against `cwd`; quote paths containing spaces. `source` runs
in the current scope. An absolute script invocation runs in a subshell with
`$0`, `$1`, `$#`, and `$@`.

See [Language](language.md) and [Redirection](redirection.md) for syntax.
