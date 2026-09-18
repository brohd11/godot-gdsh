#! namespace GDSh class NodePaths
extends RefCounted
## Resolve SceneTree node paths for command-position node targets and the `cwn` working node.
## Deliberately a near-duplicate of gdsh_lib/tree/tree_util's root/path_of: `tree` is an optional
## command pack, so core must not depend on it.

## Where `cwn` starts. In the editor this is the editor's own window, not the edited scene;
## a host that knows better sets `cwn` itself.
const DEFAULT_CWN = "/root"


## The SceneTree root, or null when there is no SceneTree.
static func root() -> Window:
	var loop = Engine.get_main_loop()
	return loop.root if loop is SceneTree else null


## Absolute path of a node, matching the `tree` convention so output pipes into tree commands.
static func path_of(node:Node) -> String:
	return str(node.get_path())


## The node `cwn` names, falling back to the tree root when it no longer resolves (the scene
## changed, or the node was freed). Null only when there is no SceneTree at all.
static func cwn_node(cwn:String) -> Node:
	var tree_root = root()
	if tree_root == null:
		return null
	if cwn.is_empty():
		return tree_root
	var node = tree_root.get_node_or_null(NodePath(cwn))
	return node if is_instance_valid(node) else tree_root


## The node `path` names: absolute paths resolve from the tree root, relative ones from `cwn`
## (so `..` works). Null when nothing is there. Resource paths are never node paths, so they are
## refused before touching the tree — `res://foo.gd` must stay a script, not a node lookup.
static func resolve(path:String, cwn:String=DEFAULT_CWN) -> Node:
	if path.is_empty() or path.contains("://"):
		return null
	var tree_root = root()
	if tree_root == null:
		return null
	var node_path := NodePath(path)
	var node:Node = null
	if node_path.is_absolute():
		node = tree_root.get_node_or_null(node_path)
	else:
		var base = cwn_node(cwn)
		if base != null:
			node = base.get_node_or_null(node_path)
	return node if is_instance_valid(node) else null
