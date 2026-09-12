# Distribution and validation

GDSh is a runtime copy of Editor Console's execution engine. It does not include
Editor Console, its commands, editor-only UI, OS mode, or the `os` command.

String, sorting, and class-enumeration utilities are copied into
`internal/utils.gd`. Each function has a `#! using` tag with its fully qualified
ALib source function for future synchronization. Class enumeration builds a fresh
dictionary on each call; it does not cache the registry.

Both highlighters, their shared palette, and the script tokenizer's cache and
helpers are local to GDSh. A standalone distribution needs only the GDSh directory,
including its resources and UID sidecars. No ALib files or generated namespace
are required.

ALib's text dispatcher optionally loads
`res://addons/addon_lib/gdsh/internal/script_highlighter_logic.gd` for `.gdsh`
files. That script is a standalone `RefCounted` implementing
`setup(text_edit, palette)`, `get_line_highlighting(line)`, and `clear_cache()`.
It accepts either library's palette through shared color properties. If the
provider is absent, ALib returns `null` and its text wrapper displays plain text.
ALib's supported-extension queries include `.gdsh` only when the provider exists.

## Exporting

Exports must include dynamically loaded command scripts and `.gdsh` files. Use an
appropriate Godot export filter—for example, export all resources and add
`*.gdsh` to the non-resource include filter. Command discovery handles exported
`.gd` remaps.

## Validation

From the project root, with Python 3 and Godot available:

```sh
python3 tests/gdsh/run_headless.py --godot godot --export
```

The tests live in the separate plugin tests repository at `tests/gdsh/`. The
runner builds a temporary project containing only GDSh and its test fixtures,
rejects external dependencies, imports it, and runs the suite outside the editor. `--export` also
exports binary scripts to a PCK and reruns the suite from an empty directory using
that pack. No export templates are required for this pack-only check. Use `--keep`
to retain the temporary project.

Negative loader tests intentionally print diagnostics for missing, invalid, and
duplicate commands.
