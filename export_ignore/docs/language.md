# Language

GDSh uses a shared lexer and recursive-descent parser for execution and
completion. It has a compact brace grammar and is not a Bash implementation.

```sh
echo first; if [ someval == "" ]{echo yes} else {echo fail}
f(){if true{echo nested}else{echo no}}; f
for item in sword shield{echo $item}
```

A newline or `;` separates simple statements. A completed block can end a
statement without a separator. Operators and structural braces do not require
surrounding spaces. Ordinary arguments may contain balanced literal braces, as
in `echo {a:1}`; quote or escape braces that would otherwise start a block.

Single quotes are literal. Double quotes allow variables and `$(...)`. Unquoted
substitution output splits on whitespace, while quoted output remains one
argument. Empty quoted arguments are retained.

## Operators and expansion

Operator precedence, highest first:

1. Redirections bind to their command or compound block.
2. `|` sends stdout to the next command; stderr remains separate.
3. `&&` and `||` have equal precedence and evaluate left to right.
4. `;` and newlines separate statements.

A pipeline returns its last command's status. `a || b | c && d` evaluates as
`a || (b | c)`, followed by `&& d`. Skipped commands and branches do not expand
variables or run substitutions. Expanded values remain argument data rather than
becoming operators.

Variable expansion is recursive, including substitutions stored in variables.
Aliases are source fragments parsed when invoked; cycles report an error.

Assignments accept `name=value` or `name = value`; `local` limits a variable to
the current scope. Values preserve spacing, support quotes and substitutions,
and end at a statement, logical, pipeline, or redirection operator. Alias values
may contain pipelines and logical operators and must end with `;` or a newline.

## Parsing and errors

The parser builds the full command tree before execution. A function declaration
has a name, `()`, and a parsed brace body; its body runs only when called.
`Context.functions` stores source strings while parsed bodies are cached and
refreshed when their source changes.

A syntax error anywhere prevents the complete submission from running, including
errors in unused blocks or direct substitutions. Diagnostics include line and
column, return `ERR`, and leave the session reusable. Aliases, externally supplied
function source, and sourced files are checked when reached. Unsupported shell
operators are rejected; quote operator characters intended as data.

## Builtins and boundaries

New contexts register `break`, `continue`, `return`, `exit`, `shift`, `true`,
`false`, `[`, `expr`, `echo`, `source`, `cd`, and `help`, plus internal function
and script invocation commands. Builtins begin in `scopes_hidden`, keeping root
completion focused on host-loaded commands.

`help` prints sorted `Commands` and `Hidden commands` sections and omits reserved
internal names beginning with `__`. Use `<command> --help` for command-specific
documentation. `GDSh.Load.load_builtins()` returns fresh scope data;
`GDSh.Context.new("", false)` creates a context without builtins.

The language supports assignments, aliases, functions, conditionals, loops,
pipes, logical operators, substitutions, and subshells. It excludes general shell
utilities, global-class dispatch, persistent configuration, editor method-call
conveniences, and OS mode. `while` loops retain a 100-iteration limit.

See [Redirection](redirection.md) for file and stream operators.
