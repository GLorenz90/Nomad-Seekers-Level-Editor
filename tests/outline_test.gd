extends SceneTree
## The selection outline on a real render: it rings the selected thing and
## never fills it in, even for an open, one-sided model seen from its back
## (a cave wall). Needs a window: run it under xvfb like ui_test.gd.

var app: Control
var fails := 0


func check(cond: bool, label: String) -> void:
  print(("ok   " if cond else "FAIL ") + label)
  if not cond:
    fails += 1


## Half a cylinder with its faces pointing out and no inside: like a scanned
## cave wall, from the inside you only ever see its back faces.
func make_shell(path: String) -> void:
  DirAccess.make_dir_recursive_absolute(path.get_base_dir())
  var st := SurfaceTool.new()
  st.begin(Mesh.PRIMITIVE_TRIANGLES)
  var steps := 16
  for i in steps:
    var a0 := PI * i / steps
    var a1 := PI * (i + 1) / steps
    var p0 := Vector3(cos(a0) * 3.0, 0, sin(a0) * 3.0)
    var p1 := Vector3(cos(a1) * 3.0, 0, sin(a1) * 3.0)
    var up := Vector3(0, 4, 0)
    for v in [p0, p1 + up, p1, p0, p0 + up, p1 + up]:
      st.set_normal(Vector3(v.x, 0, v.z).normalized())
      st.add_vertex(v)
  var mat := StandardMaterial3D.new()
  mat.albedo_color = Color(0.55, 0.45, 0.35)
  mat.cull_mode = BaseMaterial3D.CULL_DISABLED
  st.set_material(mat)
  var mi := MeshInstance3D.new()
  mi.name = "Mesh"
  mi.mesh = st.commit()
  var root_node := Node3D.new()
  root_node.name = "shell"
  root_node.add_child(mi)
  var gltf := GLTFDocument.new()
  var state := GLTFState.new()
  gltf.append_from_scene(root_node, state)
  gltf.write_to_filesystem(state, path)
  root_node.free()


func white_pixels() -> int:
  for i in 4:
    await process_frame
  await create_timer(0.3).timeout
  var img := root.get_texture().get_image()
  var rect: Rect2 = app.view.get_global_rect()
  var count := 0
  for y in range(int(rect.position.y), int(rect.end.y), 2):
    for x in range(int(rect.position.x), int(rect.end.x), 2):
      var c := img.get_pixel(x, y)
      if c.r > 0.97 and c.g > 0.97 and c.b > 0.97:
        count += 1
  return count


func _init() -> void:
  var dir := "/tmp/outline_lvl"
  make_shell(dir + "/assets/shell.glb")
  app = load("res://scenes/main.tscn").instantiate()
  root.add_child(app)
  await process_frame
  app.set_doc(EditorDoc.create("O", "", dir))
  for w in root.find_children("*", "Window", true, false):
    w.hide()
  if app.view.show_nav:
    app._toggle_view_option(3)
  var doc: EditorDoc = app.doc
  doc.level.map.assets.append({"id": "shell", "file": "assets/shell.glb", "category": "prefab", "surface": "obstacle"})
  var id := doc.add("piece", {"asset": "shell", "pos": [0, 0, 0], "surface": "obstacle"})
  doc.commit()
  # Look into the hollow side, so most of what shows is the shell's back faces.
  app.view.focus(id)
  app.view._target = Vector3(0, 2, 1.5)
  app.view._yaw = 0.0
  app.view._pitch = deg_to_rad(-20.0)
  app.view._dist = 9.0
  app.view._update_camera()
  doc.select("")
  var before: int = await white_pixels()
  doc.select(id)
  var after: int = await white_pixels()
  var rect: Rect2 = app.view.get_global_rect()
  var band := after - before
  # The shell covers a good part of the view; a 3 px ring round it is a few
  # thousand pixels (sampled every 2nd), a fill would be tens of thousands.
  var area := int(rect.size.x * rect.size.y / 4.0)
  check(band > 50, "selecting the shell draws an outline (%d white pixels)" % band)
  check(band < area * 0.04, "and doesn't fill its inside white (%d of %d)" % [band, area])
  root.get_texture().get_image().save_png("/tmp/outline_shell.png")
  print("FAILS: ", fails)
  quit(fails)
