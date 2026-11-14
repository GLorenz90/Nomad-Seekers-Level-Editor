class_name Models
extends RefCounted
## Imported glTF models, loaded once per file with GLTFDocument (the same
## way the game loads them), plus their size for picking.

static var _scenes := {}
static var _boxes := {}


static func file_for(level: LevelData, asset_id: String) -> String:
  for a in level.map.assets:
    if String(a.get("id", "")) == asset_id:
      return level.dir.path_join(String(a.get("file", "")))
  return ""


## A fresh copy of an asset's model, or null.
static func instance(level: LevelData, asset_id: String) -> Node3D:
  var path := file_for(level, asset_id)
  if path == "" or not FileAccess.file_exists(path):
    return null
  if not _scenes.has(path):
    var doc := GLTFDocument.new()
    var state := GLTFState.new()
    var packed: PackedScene = null
    if doc.append_from_file(path, state) == OK:
      var scene := doc.generate_scene(state) as Node3D
      if scene:
        _own(scene, scene)
        _boxes[path] = _bounds(scene, Transform3D.IDENTITY)
        packed = PackedScene.new()
        packed.pack(scene)
        scene.free()
    _scenes[path] = packed
  var cached: PackedScene = _scenes[path]
  return cached.instantiate() as Node3D if cached else null


static func aabb(level: LevelData, asset_id: String) -> AABB:
  var path := file_for(level, asset_id)
  if not _boxes.has(path):
    var model := instance(level, asset_id)
    if model:
      model.free()
  var box: AABB = _boxes.get(path, AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE))
  return box if box.size.length() > 0.01 else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)


static func forget(path: String) -> void:
  _scenes.erase(path)
  _boxes.erase(path)


static func _bounds(node: Node, xf: Transform3D) -> AABB:
  var box := AABB()
  var any := false
  for child in node.get_children():
    var cxf := xf
    if child is Node3D:
      cxf = xf * (child as Node3D).transform
    if child is MeshInstance3D and (child as MeshInstance3D).mesh:
      var b := cxf * (child as MeshInstance3D).mesh.get_aabb()
      box = b if not any else box.merge(b)
      any = true
    var sub := _bounds(child, cxf)
    if sub.size != Vector3.ZERO:
      box = sub if not any else box.merge(sub)
      any = true
  return box


static func _own(node: Node, owner: Node) -> void:
  for child in node.get_children():
    child.owner = owner
    _own(child, owner)
