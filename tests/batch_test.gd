extends SceneTree
## Importing many models at once (Grayson 2026-11-14), through the real app
## (headless): a model pack folder with subfolders, a .gltf with its .bin,
## a broken file, a hidden folder and a License.txt; the pack's subfolders
## kept as Place list folders; one undo for the lot; importing again skips
## what's there; several picked files; files dropped on the window.
##   godot --headless --path . --script res://tests/batch_test.gd

var fails := 0
var app: Control


func check(cond: bool, label: String) -> void:
	print(("ok   " if cond else "FAIL ") + label)
	if not cond:
		fails += 1


func settle(n := 3) -> void:
	for i in n:
		await process_frame


func rm(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		rm(path.path_join(d))
	DirAccess.remove_absolute(path)


## A small model, written as .glb or .gltf (+ .bin).
func make_model(path: String, color: Color) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	var mesh := BoxMesh.new()
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	var root_node := Node3D.new()
	root_node.name = path.get_file().get_basename()
	root_node.add_child(mi)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root_node, state)
	doc.write_to_filesystem(state, path)
	root_node.free()


func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _init() -> void:
	var pack := "/tmp/batch_pack/Forest Pack"
	rm("/tmp/batch_pack")
	make_model(pack.path_join("nature/rocks/boulder.glb"), Color.GRAY)
	make_model(pack.path_join("nature/rocks/pebble.glb"), Color.DARK_GRAY)
	make_model(pack.path_join("nature/big_trees/oak.gltf"), Color.FOREST_GREEN)
	make_model(pack.path_join("hut.glb"), Color.SADDLE_BROWN)
	make_model(pack.path_join(".backup/old.glb"), Color.RED)
	write(pack.path_join("broken.glb"), "not a model")
	write(pack.path_join("License.txt"), "CC0 1.0 Universal")
	write(pack.path_join("readme.md"), "Thanks for downloading!")
	var level_dir := "/tmp/batch_level"
	rm(level_dir)
	DirAccess.make_dir_recursive_absolute(level_dir)

	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await settle()
	app.set_doc(EditorDoc.create("Batch", "", level_dir))
	await settle()
	var doc: EditorDoc = app.doc
	var dialogs: Dialogs = app.dialogs

	# Finding what's in a pack.
	var deep := Dialogs.find_models(pack)
	check(deep.size() == 5 and not Array(deep).any(func(p): return String(p).contains(".backup")),
		"a pack's models are found, subfolders included, hidden folders not (%d)" % deep.size())
	check(Dialogs.find_models(pack, false).size() == 2, "or just the top folder (hut and the broken one)")
	var lic := Dialogs.find_pack_licenses(pack)
	check(lic.size() == 1 and lic[0].ends_with("License.txt"), "the pack's License.txt is spotted (not its readme)")
	check(Dialogs.pack_folder(pack.path_join("nature/big_trees/oak.gltf"), pack, "Forest", true) == "Forest/Nature/Big Trees",
		"subfolders become Place list folders (nature/big_trees -> Nature / Big Trees)")
	check(Dialogs.pack_folder(pack.path_join("nature/rocks/a.glb"), pack, "", false) == "", "or not, if you'd rather")

	# The settings window.
	dialogs._batch_details(PackedStringArray(), pack, "decoration", "Forest")
	await settle()
	var win := dialogs._open as ConfirmationDialog
	var texts := win.find_children("*", "Label", true, false).map(func(l): return (l as Label).text) if win else []
	var boxes := win.find_children("*", "CheckBox", true, false).map(func(c): return (c as CheckBox).text) if win else []
	check(texts.any(func(t): return String(t).begins_with("5 models:")), "the window says how many models it found")
	check(boxes.has("Include subfolders") and boxes.has("Keep the pack's subfolders as folders in the Place list")
		and boxes.any(func(t): return String(t).contains("License.txt")), "with subfolder and license options")
	(win.find_children("*", "CheckBox", true, false).filter(func(c): return (c as CheckBox).text == "Include subfolders")[0] as CheckBox).button_pressed = false
	await settle()
	texts = win.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	check(texts.any(func(t): return String(t).begins_with("2 models:")), "unticking subfolders updates the count")
	win.queue_free()
	await settle()

	# Importing the pack.
	var options := {"root": pack, "keep_subfolders": true, "category": "decoration", "folder": "Forest",
		"surface": "obstacle", "hitbox": "convex", "materials": true, "licenses": lic}
	var summary: Dictionary = await dialogs.run_batch(deep, options)
	await settle()
	check(summary.imported.size() == 4, "4 models import (%s)" % ", ".join(summary.imported))
	check(summary.skipped.size() == 1 and String(summary.skipped[0][0]) == "broken.glb", "the broken one is skipped, and named")
	var oak := doc.level.find_asset("oak")
	check(not oak.is_empty() and oak.category == "decoration" and oak.folder == "Forest/Nature/Big Trees" and oak.hitbox == "convex",
		"each goes in its pack folder with the chosen settings")
	check(FileAccess.file_exists(level_dir.path_join("assets/oak.gltf")) and FileAccess.file_exists(level_dir.path_join("assets/oak0.bin")),
		"a .gltf comes with its .bin")
	check(doc.level.find_asset("hut").folder == "Forest", "a model at the top of the pack goes in the base folder")
	check(summary.materials >= 4 and doc.level.map.materials.size() == summary.materials, "their materials come too (%d)" % summary.materials)
	check(summary.licenses == ["License.txt"] and Licenses.list(doc.level).has("License.txt"), "and the pack's license")
	pal_check(doc)
	var shown := dialogs._open as AcceptDialog
	var told := "\n".join(shown.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)) if shown else ""
	check(shown != null and shown.title == "Import finished" and told.contains("Imported 4 models and 4 materials") and told.contains("broken.glb"),
		"a summary says what was imported and skipped")
	shown.queue_free()

	# Again: everything's already there.
	var again: Dictionary = await dialogs.run_batch(deep, options)
	check(again.imported.is_empty() and again.skipped.filter(func(s): return String(s[1]).begins_with("already in the level")).size() == 4,
		"importing again skips what's already there")
	(dialogs._open as Window).queue_free()

	# One undo takes the whole import back.
	doc.undo()
	await settle()
	check(doc.level.map.assets.is_empty() and doc.level.map.materials.is_empty(), "one undo takes the whole import back")
	doc.redo()
	await settle()
	check(doc.level.map.assets.size() == 4, "and redo brings it back")

	# Model settings for one model, for a folder, and a list that scrolls.
	dialogs.models("boulder")
	await settle()
	var one := dialogs._open as AcceptDialog
	var one_labels := one.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	check(one.title == "Model: boulder" and one_labels.any(func(t): return String(t).begins_with("boulder")) \
		and not one_labels.any(func(t): return String(t).begins_with("pebble")), "a model's settings show just that model")
	dialogs.models("", ["decoration", "Forest/Nature"])
	await settle()
	var some := dialogs._open as AcceptDialog
	var some_labels := some.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	check(some.title == "Models in Decorations / Forest/Nature" and some_labels.has("Set all 3 of these:"), "a folder's settings show its 3 models, with Set all")
	var set_all: OptionButton = some.find_children("*", "OptionButton", true, false)[1]
	set_all.select(0)
	set_all.item_selected.emit(0)
	await settle()
	check(["boulder", "pebble", "oak"].all(func(id): return doc.level.find_asset(id).hitbox == "concave") and doc.level.find_asset("hut").hitbox == "convex",
		"Set all changes those models and no others")
	dialogs.models()
	await settle()
	var scrolls := (dialogs._open as Window).find_children("*", "ScrollContainer", true, false)
	var lists := scrolls.filter(func(sc): return (sc as Node).get_child_count() > 0 and (sc as Node).get_child(0) is VBoxContainer)
	check(lists.size() == 1 and (lists[0] as Node).get_child(0).get_child_count() == 4, "the full list scrolls (all 4 models in it)")
	(dialogs._open as Window).queue_free()

	# Deleting a folder with everything in it.
	var placed := doc.add("piece", {"asset": "boulder", "pos": [0, 0, 0], "surface": "obstacle"})
	doc.add("decoration", {"asset": "oak", "pos": [3, 0, 0]})
	doc.commit()
	var gone := doc.delete_folder_contents("decoration", "Forest/Nature")
	doc.commit()
	await settle()
	check(gone.models == 3 and gone.placed == 2 and gone.materials == 3, "deleting a folder takes its models, their copies and materials (%s)" % gone)
	check(doc.find(placed).is_empty() and doc.level.find_asset("hut").folder == "Forest" and doc.level.map.materials.size() == 1,
		"and leaves everything else")
	app.palette.refresh(true)
	check(not "\n".join(app.palette.outline_text()).contains("Nature"), "the folder is gone from the Place list")
	doc.undo()
	await settle()
	check(not doc.level.find_asset("oak").is_empty() and not doc.find(placed).is_empty(), "Undo brings it all back")
	doc.redo()
	await settle()
	var redo_pack: Dictionary = await dialogs.run_batch(Dialogs.find_models(pack.path_join("nature")), {"root": pack, "keep_subfolders": true,
		"category": "decoration", "folder": "Forest", "hitbox": "concave", "surface": "obstacle"})
	(dialogs._open as Window).queue_free()
	check(redo_pack.imported.size() == 3 and not doc.level.find_asset("boulder").is_empty() and doc.level.find_asset("boulder_2").is_empty()
		and doc.level.find_asset("oak").folder == "Forest/Nature/Big Trees",
		"re-importing after deleting keeps the same names (boulder, not boulder_2): %s" % ", ".join(redo_pack.imported))
	check(doc.level.find_asset("oak").hitbox == "concave", "with the new settings")

	# Several picked files, and files dropped on the window.
	dialogs.files_dropped(PackedStringArray([pack.path_join("hut.glb"), pack.path_join("nature/rocks/pebble.glb")]))
	await settle()
	check(dialogs._open is ConfirmationDialog and (dialogs._open as Window).title == "Import models", "dropping several models opens the import window")
	dialogs.files_dropped(PackedStringArray([pack]))
	await settle()
	check((dialogs._open as Window).title == "Import the models in Forest Pack", "dropping a folder imports the pack")
	dialogs.files_dropped(PackedStringArray([pack.path_join("hut.glb")]))
	await settle()
	check((dialogs._open as Window).title == "Import hut.glb", "dropping one model opens its import window")
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	img.save_png("/tmp/batch_pack/moss.png")
	dialogs.files_dropped(PackedStringArray(["/tmp/batch_pack/moss.png"]))
	await settle()
	check((dialogs._open as Window).title == "Material", "dropping an image starts a material")
	(dialogs._open as Window).queue_free()

	print("FAILS: ", fails)
	quit(fails)


## The Place list shows the pack's folders.
func pal_check(_doc: EditorDoc) -> void:
	app.palette.refresh(true)
	var lines := "\n".join(app.palette.outline_text())
	check(lines.contains("Decorations\n  Forest\n    Nature\n      Big Trees\n        Oak") and lines.contains("      Rocks\n        Boulder"),
		"the Place list shows Decorations > Forest > Nature > Rocks / Big Trees")
