extends RefCounted
## The provider hook is tested without depending on a particular VirtualFS package.
const Sh = preload("res://addons/_lib/gdsh/_ns/gd_sh.gd")

class Provider extends RefCounted:
	var allowed := false
	func resolve(path:String, cwd:String):
		if path.contains("://"):
			return {"ok": false, "error": ERR_INVALID_PARAMETER, "message": "Virtual paths only"}
		return {"ok": true, "error": OK, "message": "", "path": path.simplify_path() if path.begins_with("/") else cwd.path_join(path).simplify_path()}
	func stat(path:String):
		if path == "/" or path == "/docs":
			return {"ok": true, "error": OK, "message": "", "path": path, "kind": "directory", "readable": true}
		if path == "/docs/readme.txt":
			return {"ok": true, "error": OK, "message": "", "path": path, "kind": "file", "readable": allowed}
		return {"ok": false, "error": ERR_FILE_NOT_FOUND, "message": "Missing virtual path"}
	func list_dir(path:String):
		var entries:Array = []
		if path == "/": entries = [{"name": "docs", "path": "/docs", "kind": "directory", "readable": true}]
		elif path == "/docs" and allowed: entries = [{"name": "readme.txt", "path": "/docs/readme.txt", "kind": "file", "readable": true}]
		elif path != "/docs": return {"ok": false, "error": ERR_FILE_NOT_FOUND, "message": "Missing virtual directory"}
		return {"ok": true, "error": OK, "message": "", "path": path, "entries": entries}
	func read_text(path:String):
		if allowed and path == "/docs/readme.txt":
			return {"ok": true, "error": OK, "message": "", "path": path, "text": "virtual text"}
		return {"ok": false, "error": ERR_UNAUTHORIZED, "message": "Denied by provider"}

class BadProvider extends RefCounted:
	func resolve(_path:String, _cwd:String): return {"ok": true}


func run(suite) -> void:
	var ctx = Sh.Context.new()
	var provider = Provider.new()
	ctx.host_data["filesystem"] = provider
	ctx.cwd = "/"
	suite.check(ctx.has_filesystem(), "filesystem binding is detected")
	suite.equal(ctx.resolve_path("docs").path, "/docs", "provider resolves cwd-relative paths")
	suite.check(not ctx.read_file("res://project.godot").ok, "provider rejects schemes without native fallback")
	suite.equal(ctx.read_file("/docs/readme.txt").error, ERR_UNAUTHORIZED, "provider read denial is preserved")
	var child = Sh.Context.new_ctx("child", ctx, true)
	suite.check(child.host_data.filesystem == provider, "child contexts share filesystem identity")
	var request = Sh.Completion.new("cd /docs/", ctx)
	request.get_completions()
	suite.check(request.context.host_data.filesystem == provider, "completion contexts share filesystem identity")
	suite._sync("execute_command_multiline", ["cd /docs", ctx])
	suite.equal(ctx.cwd, "/docs", "cd uses the filesystem provider")
	provider.allowed = true
	suite.equal(child.read_file("/docs/readme.txt").text, "virtual text", "host access changes apply to existing child contexts")
	suite.check(Sh.Completion.new("echo ignored < /docs/", ctx).get_completions().has("readme.txt"), "input redirection completion uses provider listings")
	for operator in [">", ">>", "2>"]:
		ctx.variables["$changed"] = "original"
		ctx.stderr = ""
		suite._sync("execute_command_multiline", ["changed = mutated " + operator + " /blocked", ctx])
		suite.equal(ctx.variables["$changed"], "original", "provider write rejection precedes execution " + operator)
		suite.check(ctx.stderr.contains("read-only"), "provider write rejection explains the failure " + operator)
	ctx.host_data["filesystem"] = BadProvider.new()
	suite.equal(ctx.read_file("res://project.godot").error, ERR_INVALID_PARAMETER, "malformed provider results fail closed")
	ctx.host_data["filesystem"] = null
	suite.equal(ctx.read_file("res://project.godot").error, ERR_INVALID_PARAMETER, "an invalid binding does not become an unbound context")
