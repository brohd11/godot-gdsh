# GDSh

GDSh is a runtime shell and command engine for Godot games and application
consoles. It requires Godot 4.6 or newer and has no editor plugin, autoload,
editor-only UI, or Editor Console dependency.

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

Reuse the context to keep variables, aliases, functions, commands, and the
working directory between executions. See [Execution](export_ignore/docs/execution.md).

## Add a runtime console

```gdscript
var console = GDSh.Console.new()
console.load("res://commands")
add_child(console)

# Optional selectable transcript above the prompt.
console.create_output()
```

See [Console](export_ignore/docs/console.md) for signals, prompt customization,
history, completion, output, and styling.

## Load commands

```gdscript
# res://commands/greet.gd
extends GDSh.CommandBase

static func get_command_name() -> String:
    return "greet"

static func get_self_command_data() -> Dictionary:
    return _command_data({&"help": "Greet the player"})

func _execute(ctx: GDSh.Context):
    ctx.append_output("Hello!")
    return ExitCode.OK
```

```gdscript
var context = GDSh.Context.new()
context.load("res://commands")
GDSh.Execute.execute_command("greet", {"parent_ctx": context})
```

See [Commands and completion](export_ignore/docs/commands.md) for command trees,
hidden scopes, help metadata, and custom completions.

## Reference

- [Execution and contexts](export_ignore/docs/execution.md)
- [Runtime console](export_ignore/docs/console.md)
- [Language](export_ignore/docs/language.md)
- [Redirection](export_ignore/docs/redirection.md)
- [Commands and completion](export_ignore/docs/commands.md)
- [Distribution and validation](export_ignore/docs/distribution.md)
