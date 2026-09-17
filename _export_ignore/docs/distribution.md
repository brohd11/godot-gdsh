# Distribution and validation

Distribute the GDSh directory with its resources and UID sidecars. It has no
ALib or Editor Console dependency. ALib can optionally use GDSh's bundled
highlighter for `.gdsh` files.

## Exporting

Include dynamically loaded command scripts and `.gdsh` files. For example,
export all resources and add `*.gdsh` to the non-resource include filter.
Command discovery supports exported `.gd` remaps.

## Validation

From a project containing the separate plugin tests repository at `tests/gdsh/`:

```sh
python3 tests/gdsh/run_headless.py --godot godot --export
```

The runner builds an isolated GDSh project, checks dependencies, and runs the suite.
`--export` also tests a binary-script PCK; no export templates are needed.
Use `--keep` to retain the temporary project. Negative loader tests print expected errors.
