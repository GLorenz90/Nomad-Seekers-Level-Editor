extends SceneTree
## Uses the editor with mouse events in a real window: places floors from
## the palette (the navmesh and rooms follow by themselves), then drags the
## move, rotate and resize handles and checks what they do. Needs a display:
##   xvfb-run godot --path . --resolution 1600x900 --script res://tests/ui_test.gd
var app: Control
var fails := 0

func check(cond: bool, label: String) -> void:
  print(("ok   " if cond else "FAIL ") + label)
  if not cond:
    fails += 1

func mouse(at: Vector2, button := -1, pressed := false) -> void:
  var v: LevelView = app.view
  if button < 0:
    var mm := InputEventMouseMotion.new()
    mm.position = at
    v._gui_input(mm)
  else:
    var mb := InputEventMouseButton.new()
    mb.button_index = button as MouseButton
    mb.pressed = pressed
    mb.position = at
    v._gui_input(mb)
  await process_frame

func screen(world: Vector3) -> Vector2:
  return app.view._camera.unproject_position(world)

func drag(from: Vector2, to: Vector2) -> void:
  await mouse(from)
  await mouse(from, MOUSE_BUTTON_LEFT, true)
  for k in range(1, 11):
    await mouse(from.lerp(to, k / 10.0))
  await mouse(to, MOUSE_BUTTON_LEFT, false)

func _point(g: TransformGizmo, handle: String) -> Vector3:
  for p in g._points:
    if p.handle == handle:
      return p.pos
  return Vector3.ZERO


func _init() -> void:
  app = load("res://scenes/main.tscn").instantiate()
  root.add_child(app)
  await process_frame
  DirAccess.make_dir_recursive_absolute("/tmp/gizmo_lvl")
  app.set_doc(EditorDoc.create("G", "", "/tmp/gizmo_lvl"))
  for w in root.find_children("*", "Window", true, false):
    w.hide()
  var doc: EditorDoc = app.doc
  var id := doc.add("piece", {"asset": "builtin:box", "size": [4, 3, 0.5], "pos": [0, 0, 0], "surface": "obstacle"})
  doc.commit()
  doc.select(id)
  app.view.focus(id)
  app.view._dist = 14.0
  app.view._update_camera()
  for i in 5:
    await process_frame
  var g: TransformGizmo = app.view.gizmo
  g._process(0)
  var s := g.scale.x
  # Move along X: grab near the end of the red arrow, drag along it.
  app.set_gizmo_mode(TransformGizmo.Mode.MOVE)
  await process_frame
  g._process(0)
  var a := screen(g.global_position + Vector3(0.8, 0, 0) * s)
  var b := screen(g.global_position + Vector3(0.8 + 3.0 / s, 0, 0) * s)
  check(g.hit(a) == "x", "the X arrow is under the mouse (%s)" % g.hit(a))
  await drag(a, b)
  var p := Items.get_pos("piece", doc.find(id))
  check(absf(p.x - 3.0) < 0.3 and absf(p.z) < 0.01 and absf(p.y) < 0.01, "dragging the X arrow moves it 3 m along X only (%s)" % p)
  check(is_equal_approx(p.x, snappedf(p.x, 0.5)), "and it snaps to 0.5 m")
  # Rotate around Y: drag a quarter way round the green ring.
  app.set_gizmo_mode(TransformGizmo.Mode.ROTATE)
  await process_frame
  g._process(0)
  var o := g.global_position
  var r := 0.9 * g.scale.x
  var start := screen(o + Vector3(r, 0, 0))
  check(g.hit(start).begins_with("r"), "a rotation ring is under the mouse (%s)" % g.hit(start))
  var handle := g.hit(start)
  var path: Array[Vector2] = []
  for k in range(0, 11):
    var t := deg_to_rad(-9.0 * k)
    path.append(screen(o + Vector3(cos(t), 0, sin(t)) * r))
  await mouse(start)
  await mouse(start, MOUSE_BUTTON_LEFT, true)
  for pt in path:
    await mouse(pt)
  await mouse(path[path.size() - 1], MOUSE_BUTTON_LEFT, false)
  var rot := Items.get_rot("piece", doc.find(id))
  check(handle == "ry" and is_equal_approx(absf(rot.y), 90.0), "dragging the Y ring a quarter turn turns it 90° (%s, %s)" % [handle, rot])
  # Resize along its own X (now pointing along world Z after the turn).
  app.set_gizmo_mode(TransformGizmo.Mode.SCALE)
  await process_frame
  g._process(0)
  var basis := Items.xform("piece", doc.find(id)).basis.orthonormalized()
  var axis := basis * Vector3.RIGHT
  var h0 := screen(g.global_position + axis * 0.9 * g.scale.x)
  var h1 := screen(g.global_position + axis * 1.8 * g.scale.x)
  check(g.hit(h0) == "sx", "the X resize handle is under the mouse (%s)" % g.hit(h0))
  await drag(h0, h1)
  var size := LevelData.vec3(doc.find(id).size)
  check(size.x > 6.0 and is_equal_approx(size.y, 3.0) and is_equal_approx(size.z, 0.5), "dragging it out makes it wider only (%s)" % size)
  # Undo goes back one handle drag at a time.
  doc.undo()
  check(is_equal_approx(LevelData.vec3(doc.find(id).size).x, 4.0), "undo takes back the resize")

  # Local axes: the wall is turned 90°, so its own X points along world -Z.
  var wd := doc.find(id)
  var p0 := Items.get_pos("piece", wd)
  app.set_local(true)
  app.set_gizmo_mode(TransformGizmo.Mode.MOVE)
  await process_frame
  g._fit()
  var gx: Transform3D = g.global_transform
  var dir := gx.basis.x.normalized()
  var arrow := gx * Vector3(0.8, 0, 0)
  check(g.hit(screen(arrow)) == "x", "in Local, the X arrow follows the wall")
  await drag(screen(arrow), screen(arrow + dir * 2.0))
  var p1 := Items.get_pos("piece", wd)
  check(p1.distance_to(p0 + Vector3(0, 0, -2)) < 0.01, "dragging it moves the wall along its own X (world -Z) (%s -> %s)" % [p0, p1])
  app.set_local(false)

  # Plane squares: the XZ square slides it across the ground.
  await process_frame
  g._fit()
  gx = g.global_transform
  var square := gx * Vector3(0.31, 0, 0.31)
  check(g.hit(screen(square)) == "xz", "the XZ square is under the mouse (%s)" % g.hit(screen(square)))
  await drag(screen(square), screen(square + Vector3(2, 0, 1)))
  var p2 := Items.get_pos("piece", wd)
  check(p2.distance_to(p1 + Vector3(2, 0, 1)) < 0.01, "dragging the XZ square moves it 2 m X and 1 m Z, not up (%s)" % p2)
  # Look along X so the YZ square faces the camera.
  var yaw_was: float = app.view._yaw
  var pitch_was: float = app.view._pitch
  app.view._yaw = deg_to_rad(80.0)
  app.view._pitch = deg_to_rad(-15.0)
  app.view._update_camera()
  await process_frame
  g._fit()
  square = g.global_transform * Vector3(0, 0.31, 0.31)
  check(g.hit(screen(square)) == "yz", "the YZ square is there too (%s)" % g.hit(screen(square)))
  await drag(screen(square), screen(square + Vector3(0, 1, 0)))
  wd = doc.find(id)
  check(is_equal_approx(Items.get_pos("piece", wd).y, 1.0) and is_equal_approx(Items.get_pos("piece", wd).x, p2.x),
    "dragging the YZ square lifts it without moving X (%s)" % Items.get_pos("piece", wd))
  app.view._yaw = yaw_was
  app.view._pitch = pitch_was
  app.view._update_camera()
  doc.undo()
  wd = doc.find(id)

  # Orthographic: the handles still work.
  app.set_ortho(true)
  await process_frame
  check(app.view._camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "O switches to orthographic")
  g._fit()
  gx = g.global_transform
  arrow = gx * Vector3(0.8, 0, 0)
  var before_o := Items.get_pos("piece", wd)
  await drag(screen(arrow), screen(arrow + Vector3(1.5, 0, 0)))
  wd = doc.find(id)
  check(is_equal_approx(Items.get_pos("piece", wd).x - before_o.x, 1.5), "the X arrow works in orthographic too (%s -> %s)" % [before_o, Items.get_pos("piece", wd)])
  app.set_ortho(false)
  check(app.view._camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "and back to perspective")

  # Resize by sides: square the wall up first, then pull faces and a corner.
  Items.set_rot("piece", wd, Vector3.ZERO)
  doc.commit()
  app.set_gizmo_mode(TransformGizmo.Mode.SCALE)  # into Resize (from the centre)
  app.set_gizmo_mode(TransformGizmo.Mode.SCALE)  # again: switches to by-sides
  await process_frame
  check(g.scale_sides and g.sides_active(), "pressing Resize again switches to by-sides")
  check(g._points.size() == 6 + 8, "a box gets 6 face and 8 corner handles (%d)" % g._points.size())
  var start_pos := Items.get_pos("piece", wd)
  var left_face := start_pos.x - 2.0
  var face := _point(g, "f+x")
  await drag(screen(face), screen(face + Vector3(2, 0, 0)))
  var sz := LevelData.vec3(wd.size)
  var pp := Items.get_pos("piece", wd)
  check(is_equal_approx(sz.x, 6.0) and is_equal_approx(pp.x - sz.x / 2.0, left_face), "pulling the +X face out 2 m makes it 6 m wide; the -X face stays put (%s, %s)" % [sz, pp])
  face = _point(g, "f-y")
  await drag(screen(face), screen(face + Vector3(0, -1, 0)))
  sz = LevelData.vec3(wd.size)
  pp = Items.get_pos("piece", wd)
  check(is_equal_approx(sz.y, 4.0) and is_equal_approx(pp.y, -1.0) and is_equal_approx(pp.y + sz.y, 3.0),
    "pulling the bottom face down 1 m grows it downward; the top stays put (%s, %s)" % [sz, pp])
  var lo := pp - Vector3(sz.x / 2.0, 0, sz.z / 2.0)
  var corner := _point(g, "c+++")
  var far := lo + (corner - lo) * 2.0
  await drag(screen(corner), screen(far))
  sz = LevelData.vec3(wd.size)
  pp = Items.get_pos("piece", wd)
  var lo2 := pp - Vector3(sz.x / 2.0, 0, sz.z / 2.0)
  check(sz.x > 9.0 and sz.y > 6.0 and lo2.distance_to(lo) < 0.05, "pulling the corner scales it toward that corner; the opposite corner stays put (%s, %s)" % [sz, lo2])
  app.set_gizmo_mode(TransformGizmo.Mode.SCALE)
  check(not g.scale_sides, "pressing Resize once more goes back to from-the-centre")

  # Placing from the palette: a floor, then a second one beside it, then a
  # boundary between them. The rooms follow without anything else.
  doc.select("")
  app.view._target = Vector3(0, 0, 20)
  app.view._dist = 40.0
  app.view._update_camera()
  await process_frame
  var floor_entry := {}
  var boundary_entry := {}
  for e in Catalog.palette(1, doc):
    if e.title == "Floor":
      floor_entry = e
    if e.title == "Room boundary":
      boundary_entry = e
  floor_entry = floor_entry.duplicate(true)
  floor_entry.data.size = [8, 0.5, 8]
  var pieces_before: int = doc.level.map.pieces.size()
  app.begin_place(floor_entry)
  for spot in [Vector3(0, 0, 20), Vector3(8, 0, 20)]:
    var at := screen(spot)
    await mouse(at)
    await mouse(at, MOUSE_BUTTON_LEFT, true)
    await mouse(at, MOUSE_BUTTON_LEFT, false)
  app.view.cancel_place()
  check(doc.level.map.pieces.size() == pieces_before + 2, "two floors placed with the mouse")
  await create_timer(0.4).timeout
  await process_frame
  var here := doc.room_at(Vector3(0, 0, 20))
  check(here != "" and here == doc.room_at(Vector3(8, 0, 20)), "the navmesh caught up: the two floors are one room (%s)" % here)
  boundary_entry = boundary_entry.duplicate(true)
  boundary_entry.data.size = [8, 4]  # as wide as the seam, or the navmesh walks round it
  app.begin_place(boundary_entry)
  var bat := screen(Vector3(4, 0, 20))
  await mouse(bat)
  app.view.rotate_placing(90.0)
  await mouse(bat + Vector2(1, 0))
  await mouse(bat, MOUSE_BUTTON_LEFT, true)
  await mouse(bat, MOUSE_BUTTON_LEFT, false)
  app.view.cancel_place()
  await create_timer(0.4).timeout
  await process_frame
  var left := doc.room_at(Vector3(0, 0, 20))
  var right := doc.room_at(Vector3(8, 0, 20))
  check(left != "" and right != "" and left != right, "a boundary placed between them splits them into two rooms (%s, %s)" % [left, right])
  print("FAILS: ", fails)
  quit(fails)
