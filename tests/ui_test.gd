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
		mb.button_index = button
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
