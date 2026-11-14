extends SceneTree
## Drives the whole app (not just the document) through odd build orders:
## enemies and boundaries before any floor, floors overlapping and far apart,
## walls dropped on top of everything, boundaries cutting nothing, pieces
## turned and resized with the handles, deleting, undo / redo, room picking,
## and clicking rows in the outline, Waves tree and Problems list. Run it
## with stdout captured; any "SCRIPT ERROR" or "ERROR:" line is a failure.
##   godot --headless --path . --script res://tests/stress_test.gd

var app: Control
var rng := RandomNumberGenerator.new()


func settle() -> void:
  await process_frame
  await process_frame


## Lets the navmesh catch up (the app bakes a moment after a change).
func bake() -> void:
  app._nav_due = 1
  await settle()


func add(kind: String, d: Dictionary) -> String:
  var id: String = app.doc.add(kind, d)
  app.doc.select(id)
  app.doc.commit()
  await settle()
  return id


func floor_at(x: float, z: float, w := 16.0, dd := 16.0) -> String:
  return await add("piece", {"asset": "builtin:box", "size": [w, 0.5, dd], "pos": [x, -0.5, z], "surface": "floor"})


func wall_at(x: float, z: float, yaw := 0.0, w := 4.0) -> String:
  return await add("piece", {"asset": "builtin:box", "size": [w, 3, 0.5], "pos": [x, 0, z], "rot": [0, yaw, 0], "surface": "obstacle"})


func boundary_at(x: float, z: float, yaw := 0.0) -> String:
  return await add("boundary", {"pos": [x, 0, z], "rot": [0, yaw, 0], "size": [4, 3]})


func tree_rows(t: Tree) -> Array[TreeItem]:
  var rows: Array[TreeItem] = []
  var stack: Array[TreeItem] = []
  if t.get_root():
    stack.append(t.get_root())
  while not stack.is_empty():
    var it: TreeItem = stack.pop_back()
    if it != t.get_root() and it.is_selectable(0):
      rows.append(it)
    for c in it.get_children():
      stack.append(c)
  return rows


func click_tree(t: Tree) -> void:
  var count := tree_rows(t).size()
  for i in mini(count, 12):
    var rows := tree_rows(t)
    if i >= rows.size():
      break
    t.set_selected(rows[i], 0)
    await settle()


func click_list(l: ItemList) -> void:
  for i in mini(l.item_count, 6):
    if l.is_item_selectable(i):
      l.select(i)
      l.item_selected.emit(i)
      await settle()
  for w in root.find_children("*", "Window", true, false):
    w.hide()


## The handles, driven the way a mouse would (straight through the gizmo).
func use_handles(id: String) -> void:
  var g: TransformGizmo = app.view.gizmo
  app.doc.select(id)
  for m in [TransformGizmo.Mode.MOVE, TransformGizmo.Mode.ROTATE, TransformGizmo.Mode.SCALE]:
    app.set_gizmo_mode(m)
    await settle()
    if not g.visible:
      continue
    var handle: String = {TransformGizmo.Mode.MOVE: "x", TransformGizmo.Mode.ROTATE: "ry", TransformGizmo.Mode.SCALE: "sx"}[m]
    var at := Vector2(400, 300)
    g.start(handle, at)
    for k in 6:
      g.drag(at + Vector2(k * 15, -k * 6), false)
      await process_frame
    g.finish()
    app.doc.commit()
    await settle()


func scenario(n: int) -> void:
  var dir := "/tmp/stress_v2_%d" % n
  DirAccess.make_dir_recursive_absolute(dir)
  app.set_doc(EditorDoc.create("Stress %d" % n, "forest", dir))
  await settle()
  var doc: EditorDoc = app.doc
  # Enemies and boundaries before any floor.
  app.set_layer(3)
  for i in 3:
    doc.add("enemy", {"enemy": "grub_hound", "pos": [i * 4.0, 0, 30.0], "wander": true, "wander_radius": 6.0, "limited_chase": true, "chase_radius": 3.0})
  doc.commit()
  await bake()
  app.set_layer(1)
  await boundary_at(-8, 0, 90)
  await boundary_at(100, 100)
  await bake()
  # Floors far apart, overlapping, stacked.
  var a := await floor_at(-16, 0)
  await floor_at(8, 0)
  await floor_at(-8, 0, 8, 4)
  await floor_at(0, 40)
  await floor_at(4, 44)
  await floor_at(0, 40, 4, 4)
  await bake()
  # Walls across everything, some with gaps, then boundaries in the gaps.
  for z in [-6.0, -2.0, 2.0, 6.0]:
    if absf(z) > 3.0:
      await wall_at(-8, z, 90)
  await boundary_at(-8, 0, 90)
  await wall_at(0, 40, 45, 12)
  await bake()
  # Select through every list, and rooms by the navmesh.
  for layer in [1, 2, 3]:
    app.set_layer(layer)
    await settle()
    await click_tree(app.outline)
  app.set_layer(1)
  app.set_pick_rooms(true)
  for area in doc.level.map.areas.duplicate():
    doc.select(String(area.id))
    await settle()
  app.set_pick_rooms(false)
  if not doc.level.map.areas.is_empty():
    var area_id := String(doc.level.map.areas[0].id)
    doc.level.find_area(area_id).kind = "corridor"
    doc.commit()
    if doc.level.map.areas.size() > 1:
      doc.join_areas(area_id, String(doc.level.map.areas[1].id))
      doc.commit()
    await bake()
  await click_tree(app.bottom._waves)
  await click_list(app.bottom._problems)
  # Handles on a floor, a wall and a boundary.
  for id in [a, String(doc.level.map.pieces[-1].id), String(doc.level.map.boundaries[0].id)]:
    if doc.kind_of(id) != "":
      await use_handles(id)
  await bake()
  # Enemies into rooms, a door and a button, then delete the floor under them.
  app.set_layer(3)
  doc.add("enemy", {"enemy": "grub_hound", "pos": [-16, 0, 0]})
  doc.add("enemy", {"enemy": "grub_hound", "pos": [-16, 0, 2]}, 1)
  doc.commit()
  await bake()
  app.set_layer(2)
  doc.add("object", {"type": "door", "start": "closed", "pos": [-8, 0, 0], "yaw": 90})
  doc.add("object", {"type": "button", "mode": "floor", "pos": [-16, 0, 4]})
  doc.commit()
  await settle()
  app.set_layer(1)
  doc.select(a)
  app.delete_selected()
  for w in root.find_children("*", "ConfirmationDialog", true, false):
    if (w as Window).visible:
      (w as ConfirmationDialog).get_ok_button().pressed.emit()
  await bake()
  # Undo everything, redo everything.
  while doc.can_undo():
    doc.undo()
    await process_frame
  await bake()
  while doc.can_redo():
    doc.redo()
    await process_frame
  await bake()
  # Random churn.
  for i in 40:
    match rng.randi_range(0, 5):
      0:
        await floor_at(rng.randi_range(-6, 6) * 8.0, rng.randi_range(-6, 6) * 8.0, [4.0, 8.0, 16.0][rng.randi() % 3], [4.0, 8.0, 16.0][rng.randi() % 3])
      1:
        await wall_at(rng.randi_range(-12, 12) * 4.0, rng.randi_range(-12, 12) * 4.0, [0.0, 90.0, 30.0][rng.randi() % 3])
      2:
        await boundary_at(rng.randi_range(-12, 12) * 4.0, rng.randi_range(-12, 12) * 4.0, [0.0, 90.0][rng.randi() % 2])
      3:
        var items := doc.items()
        doc.select(items[rng.randi() % items.size()].id)
        app.delete_selected()
        for w in root.find_children("*", "ConfirmationDialog", true, false):
          if (w as Window).visible:
            (w as ConfirmationDialog).get_ok_button().pressed.emit()
        await settle()
      4:
        app.set_layer(rng.randi_range(1, 3))
        await settle()
      5:
        if doc.can_undo():
          doc.undo()
          await settle()
    if i % 5 == 0:
      await bake()
  await bake()
  print("scenario ", n, " ok: ", doc.level.room_count(), " rooms, ", doc.level.corridor_count(), " corridors, ", app.problems.size(), " problems")


func _init() -> void:
  rng.seed = 7
  app = load("res://scenes/main.tscn").instantiate()
  root.add_child(app)
  await settle()
  for n in 3:
    await scenario(n)
  print("STRESS DONE")
  quit()
