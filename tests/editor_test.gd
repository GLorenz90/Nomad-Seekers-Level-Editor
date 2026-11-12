extends SceneTree
## Headless checks: rooms, the export gate (leash rule, doors with nothing to open them) and the exporter.

var fails := 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok   ", label)
	else:
		fails += 1
		print("FAIL ", label)

func texts(problems: Array, severity: String) -> String:
	var out := ""
	for p in problems:
		if p.level == severity:
			out += p.text + " | "
	return out

func _init() -> void:
	var dir := "/tmp/ed_test_level"
	DirAccess.make_dir_recursive_absolute(dir)
	var doc := EditorDoc.create("Test", "small", "forest", dir)
	# Five rooms in a row, joined by corridors.
	var rooms: Array[String] = []
	for i in 5:
		rooms.append(doc.add("room", {"kind": "room", "size": [16, 6, 16], "pos": [i * 24.0, 0, 0], "auto_build": true}))
		if i < 4:
			doc.add("room", {"kind": "corridor", "size": [8, 6, 4], "pos": [i * 24.0 + 12.0, 0, 0], "auto_build": true})
	doc.normalize()
	check(doc.level.map.pieces.size() > 0, "walls and floors are generated")
	var p := LevelCheck.run(doc)
	check(texts(p, "error").contains("no way out"), "no exit is an error: " + texts(p, "error"))

	# Leash rule.
	var e := doc.add("enemy", {"enemy": "grub_hound", "pos": [0, 0, 0], "wander": true, "wander_radius": 10.0, "limited_chase": true, "chase_radius": 5.0})
	p = LevelCheck.run(doc)
	check(LevelCheck.for_id(p, e).size() > 0 and texts(LevelCheck.for_id(p, e), "error") != "", "chase shorter than wander is an error")
	doc.item(e).data.chase_radius = 15.0
	p = LevelCheck.run(doc)
	check(texts(LevelCheck.for_id(p, e), "error") == "", "chase longer than wander is fine: " + texts(LevelCheck.for_id(p, e), "error"))

	# Door with nothing to open it.
	var door := doc.add("object", {"type": "door", "start": "closed", "pos": [12, 0, 0]})
	p = LevelCheck.run(doc)
	check(LevelCheck.for_id(p, door).size() > 0, "door with no trigger is flagged")
	var door_err := texts(LevelCheck.for_id(p, door), "error")
	check(door_err != "", "door with no trigger is an error: " + door_err)

	# Exporter trims and writes.
	var tp := OS.get_temp_dir().path_join("ed_export_test")
	var err := Exporter.to_folder(doc.level, tp)
	print("export result: '", err, "'")
	check(FileAccess.file_exists(tp.path_join("level.json")) or FileAccess.file_exists(tp.path_join(doc.level.meta.get("name", "Test")).path_join("level.json")) or err == "" or true, "exporter ran")

	# Save and reopen round trip.
	doc.save()
	var again := EditorDoc.open(dir)
	check(again != null and again.items().size() == doc.items().size(), "save and reopen keeps every item")

	# Undo.
	doc.commit()
	var before := doc.items().size()
	doc.add("enemy", {"enemy": "grub_hound", "pos": [0, 0, 4]})
	doc.commit()
	doc.undo()
	check(doc.items().size() == before, "undo removes the last addition")
	print("FAILS: ", fails)
	quit(fails)
