# Language

GDSh supports assignments, aliases, functions, conditionals, loops, pipes,
substitutions, and subshells with brace syntax. It is not Bash and has no OS mode.

```sh
name = player
echo "Hello ${name}!"
f(){if true{echo yes}else{echo no}}; f
for item in sword shield{echo $item}
```

Newlines and `;` separate statements; completed blocks also end statements.
Operators and structural braces need no surrounding spaces. Balanced literal
braces are allowed in arguments (`echo {a:1}`); quote ambiguous braces.

## Expansion and operators

Single quotes are literal; double quotes allow variables and `$(...)`.
`${name}` separates a variable name from following text. Unquoted substitution
output splits on whitespace; quoted output stays one argument, including empty strings.
Commands inside `$(...)` cannot pause with `await`.

Precedence, highest first:

1. Redirections.
2. `|` (stdout only; returns the last command's status).
3. `&&` and `||` (equal precedence, left to right).
4. `;` and newlines.

Skipped commands do not expand values or run substitutions. Expanded values remain
argument data. Variable expansion is recursive, including stored substitutions.
Aliases are parsed as source when invoked; cycles are errors.

Assignments accept `name=value` or `name = value`; `local` limits scope. Values
preserve spacing and end at a statement, logical, pipeline, or redirection operator.
Alias values can contain pipelines and logical operators; end them with `;` or a newline.

## Errors and limits

The full submission is parsed before execution. Syntax errors, even in unused
blocks, prevent execution and return `ERR` with a line and column. Aliases,
externally supplied function source, and sourced files are checked when reached.
Unsupported operators must be quoted to use them as data. `while` loops have a
100-iteration limit.

## Builtins

Builtins provide control flow, output, arithmetic, scripts, directory changes,
and session management. They are callable directly but hidden from root completion.

- `builtins` lists bundled commands; `builtins echo hello` bypasses host overrides.
- `hidden` lists discoverable hidden commands, including `builtins`.
- `help` lists commands; `<command> --help` or `-h` shows usage and returns `OK`.
- `GDSh.Context.new("", false)` creates a context without builtins.

See [Redirection](redirection.md) for file and stream operators.
