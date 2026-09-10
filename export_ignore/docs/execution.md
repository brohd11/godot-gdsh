# Execution and contexts

Use `GDSh.Execute.execute_command_multiline()` for complete scripts. The other
entry points accept the same language:

```gdscript
var context = GDSh.Context.new()

# Accepts parent_ctx and sub_shell options.
var result = GDSh.Execute.execute_command("echo hello", {"parent_ctx": context})

# The file must start with #!gdsh.
GDSh.Execute.source_file("res://scripts/start.gdsh", context)
```

All three entry points return their resulting `Context`. Omitting a context
creates a fresh session with builtins. Execution is synchronous.

## Context state

A context owns its variables, aliases, functions, command scopes, positional
arguments, and working directory. Independent contexts have independent
dictionaries. The default working directory is `res://`; `cwd` can also be a
`user://` path or an absolute OS path.

Output accumulates in `stdout` and `stderr`, so clear those strings after the host
consumes them. `last_status` is the last command's status and `exit_code` is the
execution result. Status codes are `OK=0`, `FAIL=1`, `ERR=2`, and `HELP=3`.

`exit N` stops the current execution context and preserves `N`; it does not quit
the game. Create a new session or explicitly reset `exit_requested` before
reusing a stopped context.

## Script files and scope

Relative script paths resolve against `Context.cwd`. Quote paths containing
spaces. `source` executes a file in the current scope. Invoking an absolute script
path executes it in a subshell with `$0`, `$1`, `$#`, and `$@`.

See also [Language](language.md) and [Redirection](redirection.md).
