# Redirection

| Syntax | Effect |
| --- | --- |
| `>file` / `1>file` | Overwrite with stdout |
| `>>file` / `1>>file` | Append stdout |
| `2>file` / `2>>file` | Overwrite / append stderr |
| `&>file` / `&>>file` | Overwrite / append stdout, then stderr |
| `<file` / `0<file` | Read into stdin |

Paths resolve against `Context.cwd`; parent directories must exist. Targets use
normal expansion and must produce one non-empty path. `discard` and `/dev/null`
discard output or supply empty input; use `./discard` for a real file with that name.
Descriptors must touch the operator: `2 >file` passes `2` as an argument.

```sh
build >user://build.log 2>user://errors.log
items <user://input.txt | process >>user://results.txt
if true{echo saved}>"$OUTPUT"
```

Redirections can precede commands, appear among arguments, or follow blocks and
function calls. Targets open left to right before execution; the last for each
stream wins, but earlier files are still created or truncated. Open failures
return `FAIL` without executing. File redirection overrides piped input/output;
otherwise status, control flow, and scope are preserved.

Unsupported: `2>&1`, `|&`, heredocs, background execution, redirection-only
statements, and redirection on function declarations (redirect the call instead).
