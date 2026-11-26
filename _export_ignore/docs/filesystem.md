# Filesystem providers

Bind an object to `ctx.host_data["filesystem"]` to replace shell filesystem reads.
The provider is optional. Without a binding, existing physical filesystem
behaviour is unchanged. A binding that fails or is invalid never falls back to
physical files.

The provider implements four synchronous methods returning dictionaries:

| Method | Success payload |
| --- | --- |
| `resolve(path: String, cwd: String)` | `path: String`, canonical absolute path |
| `stat(path: String)` | `path`, `kind: "file" or "directory"`, `readable: bool` |
| `list_dir(path: String)` | `path`, `entries: Array[Dictionary]` |
| `read_text(path: String)` | `path`, `text: String` |

All results also contain `ok: bool`, `error: int` (a Godot Error), and
`message: String`. Listing entries contain `name`, `path`, `kind`, and
`readable`; the provider must already filter entries according to its access
policy. Operations receive paths normalized by `resolve`. Return a failed result
for unsupported schemes, denied access, missing files, or invalid operations.

Context helpers expose this contract:

- `has_filesystem()` checks whether the host bound a provider.
- `resolve_path(path)`, `stat_path(path)`, `list_directory(path)`, and
  `read_file(path)` delegate to it, or use physical files when unbound.
- `walk_directory(path)` enumerates descendants using filtered listings, without
  descending into unreadable directories.

Core `cd`, filesystem predicates in `[`, command and file/directory flag completion, relative-path
completion, redirection completion, `<` input, and enabled `source`/`gdsh`
commands honour the provider. Output redirects other than `discard` or
`/dev/null` fail before dispatch when a provider is bound; writable providers
are not part of this interface yet.

Package and command script loading remains on the trusted resource filesystem.
The binding does not change scopes: the host selects which commands to register.
File-reading commands from other packages need provider-aware implementations;
existing utils commands are not automatically redirected. The `virtual_fs`
package supplies replacements for its file-based commands.

`Context.new_ctx` and completion copy `host_data` shallowly, preserving provider
identity. Console `new_ctx` rebuilds its root through `context_factory`; attach
the provider there too if access state should survive a shell reset.

Existing `PathCompletion.files(path, cwd, raw_word)` callers remain compatible.
Provider-aware callers pass the context as the optional fourth argument.
