# Execution and contexts

```gdscript
var context = GDSh.Context.new()
await GDSh.Execute.execute_command_multiline("echo hello", context)
var result = await GDSh.Execute.execute_command("echo hello", {"parent_ctx": context})
await GDSh.Execute.execute_command_multiline("gdsh res://scripts/start.gdsh first", context)
await GDSh.Execute.source_file("res://scripts/setup.gdsh", context) # Requires #!gdsh.
```

All entry points return a `Context`; omitting one creates a session with builtins.
Use `await` to support commands that pause. Synchronous commands finish in the calling frame.

## Context state

A context keeps variables, aliases, functions, command scopes, positional arguments,
and `cwd` (initially `res://`) and `cwn` (initially `/root`). File paths may also use
`user://` or absolute OS paths. `cd` changes the working directory; `cn` changes the
working node. Both are inherited by child, subshell, and completion contexts.

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

Relative file paths resolve against `cwd`; quote paths containing spaces.
`gdsh path/to/start.gdsh first second` and bare `path/to/start.gdsh first second`
run in a subshell with `$0`, `$1`, `$#`, and `$@`. Only the `.gdsh` extension is
required; a `#!gdsh` header is optional. Variables, functions, `cwd`, and `cwn`
changed inside the subshell do not propagate to its parent; output and status do.

`source path/to/setup.gdsh` and `Execute.source_file()` run in the current scope
and still require a `#!gdsh` header. `.gd` paths resolve as Script targets, not
shell scripts. See [Commands](commands.md#script-and-node-targets) for target routing.

See [Language](language.md) and [Redirection](redirection.md) for syntax.
