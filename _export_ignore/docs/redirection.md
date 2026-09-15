# Redirection

Redirection targets resolve relative to `Context.cwd`. `res://`, `user://`, and
absolute OS paths remain absolute. Parent directories must already exist.

| Syntax | Effect |
| --- | --- |
| `command >file` or `command 1>file` | Overwrite file with stdout |
| `command >>file` or `command 1>>file` | Append stdout |
| `command 2>file` / `command 2>>file` | Overwrite / append stderr |
| `command &>file` / `command &>>file` | Overwrite / append stdout, then stderr |
| `command <file` or `command 0<file` | Read file into stdin |

The literal targets `discard` and `/dev/null` are portable null streams. Output
is dropped and input is empty. Address an actual file named `discard` as
`./discard`.

Targets use normal quote, variable, and command-substitution expansion and must
produce exactly one non-empty path. Descriptors must touch the operator: `2>`
redirects stderr, while `2 >` passes `2` as an argument and redirects stdout.

Redirections can precede a simple command, appear among its arguments, or follow
an `if`, loop, subshell, assignment, or function call:

```sh
build >user://build.log 2>user://errors.log
items <user://input.txt | process >>user://results.txt
if true{echo saved}>"$OUTPUT"
f(){echo hidden;return 4}; f &>discard
```

Targets are expanded and opened from left to right before execution. The final
redirection for a stream wins, though earlier output targets are still created or
truncated. An open failure returns `FAIL` without running the command. Redirected
stdout overrides a pipe destination, and file stdin overrides piped stdin.
Successful redirection otherwise preserves status, control flow, and scope.

Descriptor copying such as `2>&1`, `|&`, heredocs, background execution,
redirection-only statements, and redirection on function declarations are not
supported. Attach redirection to the function call instead.
