# Distribution and validation

GDSh is a runtime copy of Editor Console's execution engine. It does not include
Editor Console, its commands, editor-only UI, OS mode, or the `os` command.

String, sorting, and class-enumeration utilities are copied into
`internal/utils.gd`. Each function has a `#! using` tag with its fully qualified
ALib source function for future synchronization. Class enumeration builds a fresh
dictionary on each call; it does not cache the registry.

The default console highlighter and shared palette are local to GDSh. The
script-oriented option imports the GDSh highlighter, palette, and highlighter base from
`addons/addon_lib/brohd/alib_runtime/misc/syntax_highlighters/text/`. A standalone
distribution must bundle those three scripts and their UID sidecars. No generated
ALib namespace or external utility scripts are needed. The ALib script highlighter
has not yet been ported locally; the public `GDSh.Console.ScriptHighlighter`
adapter translates GDSh palette colors for it.

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
runner builds a temporary project containing GDSh and its highlighting
dependencies, imports it, and runs the suite outside the editor. `--export` also
exports binary scripts to a PCK and reruns the suite from an empty directory using
that pack. No export templates are required for this pack-only check. Use `--keep`
to retain the temporary project.

Negative loader tests intentionally print diagnostics for missing, invalid, and
duplicate commands.
