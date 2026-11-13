extends SceneTree
## Drives the whole app (not just the document) through odd sequences:
## every size, rooms touching / overlapping / far apart, corridors added
## after rooms, deleting, undo/redo, dragging rooms into each other, and
## clicking rows in the outline, Waves tree and Problems list. Run it with
## stdout captured; any "SCRIPT ERROR" or "ERROR:" line is a failure.

var app: Control
var rng := RandomNumberGenerator.new()

func settle() -> void:
	await process_frame
	await process_frame

func room(x: float, z: float, w := 16.0, d := 16.0, corridor := false) -> String:
	if OS.get_environment("TRACE") != "": print("room ", x, ",", z, " ", w, "x", d, " corridor=", corridor)
	var id: String = app.doc.add("room", {"kind": "corridor" if corridor else "room", "size": [w, 6, d], "pos": [x, 0, z], "auto_build": true})
	app.doc.select(id)
	app.doc.commit()
	await settle()
	return id

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

## Clicks each selectable row in turn (the tree rebuilds after each click).
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

func scenario(size: String) -> void:
	var dir := "/tmp/stress_%s" % size
	DirAccess.make_dir_recursive_absolute(dir)
	app.set_doc(EditorDoc.create("Stress " + size, size, "forest", dir))
	await settle()
	var doc: EditorDoc = app.doc
	# Enemies before any room (outside waves).
	app.set_layer(3)
	for i in 3:
		doc.add("enemy", {"enemy": "grub_hound", "pos": [i * 4.0, 0, 30.0], "wander": true, "wander_radius": 6.0, "limited_chase": true, "chase_radius": 3.0})
	doc.commit()
	await settle()
	app.set_layer(1)
	# Two rooms with a gap, then a corridor between (bug 1).
	var a := await room(-16, 0)
	var b := await room(8, 0)
	await room(-4, 0, 8, 4, true)
	# A room right next to another (bug 3), flush on each side.
	await room(-16, 16)
	await room(-32, 0)
	await room(-16, -16, 16, 16)
	# Overlapping and corner-touching rooms.
	await room(10, 4)
	await room(24, 16)
	# A wide-open "plains" made of touching rooms.
	for gx in 3:
		await room(60 + gx * 16, 0)
	# Select things through every list (bug 2).
	for layer in [1, 2, 3]:
		app.set_layer(layer)
		await settle()
		await click_tree(app.outline)
	await click_tree(app.bottom._waves)
	await click_list(app.bottom._problems)
	for w in root.find_children("*", "Window", true, false):
		w.hide()  # clicking the size problem opens Level settings
	# Enemies into rooms, a door and a button, then delete a room under them.
	app.set_layer(3)
	doc.add("enemy", {"enemy": "grub_hound", "pos": [-16, 0, 0]})
	doc.add("enemy", {"enemy": "grub_hound", "pos": [-16, 0, 2]}, 1)
	doc.commit()
	await settle()
	app.set_layer(2)
	var door := doc.add("object", {"type": "door", "start": "closed", "pos": [-8, 0, 0]})
	doc.add("object", {"type": "button", "mode": "floor", "pos": [-16, 0, 4]})
	doc.commit()
	await settle()
	doc.select(a)
	app.delete_selected()
	for w in root.find_children("*", "ConfirmationDialog", true, false):
		if (w as Window).visible:
			(w as ConfirmationDialog).get_ok_button().pressed.emit()
	await settle()
	# Drag a room straight through others, step by step.
	app.set_layer(1)
	var d := doc.find(b)
	if not d.is_empty():
		for step in 20:
			Items.set_pos("room", d, Vector3(8 - step * 4, 0, 0))
			doc.normalize()
			app.view.rebuild()
			await process_frame
		doc.commit()
	await settle()
	# Undo everything, redo everything.
	while doc.can_undo():
		doc.undo()
		await process_frame
	while doc.can_redo():
		doc.redo()
		await process_frame
	await settle()
	# Random churn.
	for i in 40:
		match rng.randi_range(0, 4):
			0:
				await room(rng.randi_range(-10, 10) * 8.0, rng.randi_range(-10, 10) * 8.0, [4.0, 8.0, 16.0, 24.0][rng.randi() % 4], [4.0, 8.0, 16.0][rng.randi() % 3], rng.randf() < 0.4)
			1:
				var items := doc.items()
				doc.select(items[rng.randi() % items.size()].id)
				app.delete_selected()
				await settle()
			2:
				app.set_layer(rng.randi_range(1, 3))
				await settle()
			3:
				if doc.can_undo():
					doc.undo()
					await settle()
			4:
				await click_tree(app.outline)
	print("scenario ", size, " ok: ", doc.level.room_count(), " rooms, ", LevelCheck.run(doc).size(), " problems")

func _init() -> void:
	rng.seed = 7
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await settle()
	for size in ["arena", "small", "medium", "huge"]:
		await scenario(size)
	print("STRESS DONE")
	quit()
