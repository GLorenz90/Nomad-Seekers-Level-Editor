extends SceneTree
## The library side of the editor, through the real app (headless):
## importing a model into Decorations / a folder (with its materials),
## materials painted onto shapes, folders (new, nested, renamed, deleted),
## dragging things between folders, remembered collapsing, the new shapes,
## the material checks and export.
##   godot --headless --path . --script res://tests/library_test.gd

var fails := 0
var app: Control


func check(cond: bool, label: String) -> void:
	print(("ok   " if cond else "FAIL ") + label)
	if not cond:
		fails += 1


func settle() -> void:
	await process_frame
	await process_frame


## A small glTF model with a textured material, written to `path`.
func make_model(path: String) -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.6, 0.5, 0.3))
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Bark"
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.roughness = 0.6
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 2, 1)
	var mi := MeshInstance3D.new()
	mi.name = "Stump"
	mi.mesh = mesh
	mi.material_override = mat
	mesh.material = mat
	var root := Node3D.new()
	root.name = "Stump"
	root.add_child(mi)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	doc.write_to_filesystem(state, path)
	root.free()


func _init() -> void:
	AppSettings.set_value(Palette.COLLAPSED_KEY, [])
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await settle()
	var dir := "/tmp/library_test_level"
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir.path_join("assets")) if DirAccess.dir_exists_absolute(dir.path_join("assets")) else PackedStringArray():
			DirAccess.remove_absolute(dir.path_join("assets").path_join(f))
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.make_dir_recursive_absolute(dir)
	app.set_doc(EditorDoc.create("Library", "", dir))
	await settle()
	var doc: EditorDoc = app.doc
	var pal: Palette = app.palette

	# The Map layer's six categories.
	var top := []
	for line in pal.outline_text():
		if not line.begins_with(" "):
			top.append(line.split(" [")[0])
	check(top.slice(0, 6) == ["Shapes", "Decorations", "Prefabs", "Materials", "Invisible", "Effects"], "the Place list has six categories (%s)" % ", ".join(top))
	check(pal.find_row("Stairs") != null and pal.find_row("Curved wall") != null, "Stairs and Curved wall are in Shapes")

	# Import a model into Decorations / Rocks, with its material.
	var model_path := "/tmp/library_stump.glb"
	make_model(model_path)
	check(app.dialogs._model_materials(model_path) == 1, "the import dialog finds the model's material")
	var problem: String = app.dialogs.import_file(model_path, "CC0", "Tester", "obstacle", "convex", "decoration", "Rocks/Small", true)
	await settle()
	check(problem == "", "a model imports (%s)" % problem)
	var asset := doc.level.find_asset("library_stump")
	check(asset.get("category") == "decoration" and asset.get("folder") == "Rocks/Small", "it goes into Decorations / Rocks / Small")
	check(doc.level.map.materials.size() == 1, "its material comes along")
	var mat: Dictionary = doc.level.map.materials[0] if doc.level.map.materials.size() > 0 else {}
	check(String(mat.get("albedo", "")) != "" and FileAccess.file_exists(dir.path_join(String(mat.get("albedo", "")))),
		"with its image saved in the level's assets (%s)" % mat.get("albedo", ""))
	check(mat.get("license") == "CC0" and mat.get("folder") == "Library Stump", "sharing the model's license, in a folder named after it")
	pal.refresh(true)
	var lines := "\n".join(pal.outline_text())
	check(lines.contains("Decorations\n  Rocks\n    Small\n      Library Stump"), "the Place list shows Decorations > Rocks > Small > the model")
	check(lines.contains("Materials\n  Library Stump\n    Bark"), "and Materials > Library Stump > Bark")

	# Folders: new, nested, rename (moves everything under it), delete.
	doc.add_folder("prefab", "Buildings/Ruins")
	doc.commit()
	await settle()
	check(pal.find_row("Prefabs/Buildings/Ruins") != null, "an empty nested folder shows up")
	doc.rename_folder("decoration", "Rocks", "Stones")
	doc.commit()
	await settle()
	check(doc.level.find_asset("library_stump").folder == "Stones/Small" and pal.find_row("Decorations/Stones/Small") != null,
		"renaming a folder takes what's inside along")
	doc.delete_folder("decoration", "Stones")
	doc.commit()
	await settle()
	check(doc.level.find_asset("library_stump").folder == "Small", "deleting a folder moves what was in it up a level")

	# Dragging the model from Decorations into a Prefabs folder.
	pal.refresh(true)
	var target := pal.find_row("Prefabs/Buildings")
	var row := pal.find_row("Library Stump")
	var entry: Dictionary = row.get_metadata(0).entry if row else {}
	pal._tree.scroll_to_item(target, true)
	await settle()
	var drop_at := pal._tree.get_item_area_rect(target).get_center() if target else Vector2.ZERO
	var data := {"palette_entry": entry}
	check(target != null and pal._can_drop(drop_at, data), "a model can be dropped on a folder")
	var mat_row := pal.find_row("Bark")
	check(mat_row != null and not pal._can_drop(drop_at, {"palette_entry": mat_row.get_metadata(0).entry}), "but a material can't go into Prefabs")
	pal._drop(drop_at, data)
	await settle()
	asset = doc.level.find_asset("library_stump")
	check(asset.category == "prefab" and asset.folder == "Buildings", "dropping moves it to Prefabs / Buildings")

	# Collapsing is remembered.
	pal.refresh(true)
	var cat := pal.find_row("Effects")
	cat.collapsed = true
	pal._on_collapsed(cat)
	pal.refresh(true)
	check(pal.find_row("Effects").collapsed and "\n".join(pal.outline_text()).contains("Effects [closed]"), "a closed category stays closed after a rebuild")
	check((AppSettings.get_value(Palette.COLLAPSED_KEY, []) as Array).has("Effects"), "and it's remembered between sessions")
	var folder_row := pal.find_row("Prefabs/Buildings")
	folder_row.collapsed = true
	pal._on_collapsed(folder_row)
	pal.refresh(true)
	check(pal.find_row("Prefabs/Buildings").collapsed, "folders stay closed too")
	pal._search.text = "stump"
	pal.refresh(true)
	check("\n".join(pal.outline_text()).contains("Library Stump") and not "\n".join(pal.outline_text()).contains("Fireflies"),
		"searching opens folders and hides what doesn't match")
	pal._search.text = ""
	pal.refresh(true)

	# Painting: a floor, stairs and a curved wall, with the material.
	var floor_id := doc.add("piece", {"asset": "builtin:box", "size": [12, 0.5, 20], "pos": [0, -0.5, 0], "surface": "floor"})
	var stairs := doc.add("piece", {"asset": "builtin:stairs", "size": [4, 2, 6], "steps": 8, "pos": [0, 0, 0], "surface": "floor"})
	doc.add("piece", {"asset": "builtin:box", "size": [12, 0.5, 6], "pos": [0, 1.5, -6], "surface": "floor"})
	var curve := doc.add("piece", {"asset": "builtin:curved_wall", "size": [8, 3, 0.5], "bend": 120.0, "pos": [0, 0, 6], "surface": "obstacle"})
	doc.find(floor_id).material = String(mat.id)
	doc.commit()
	await settle()
	var node: Node3D = app.view._nodes.get(floor_id)
	var mi: MeshInstance3D = node.find_children("*", "MeshInstance3D", true, false)[0] if node else null
	check(mi != null and mi.material_override is StandardMaterial3D and (mi.material_override as StandardMaterial3D).albedo_texture != null,
		"a painted floor shows its material in the view")
	doc.update_nav()
	check(doc.room_at(Vector3(0, 0, 7)) == doc.room_at(Vector3(0, 2, -6)) and doc.room_at(Vector3(0, 2, -6)) != "", "8 stairs join the lower and upper floors")
	doc.find(stairs).steps = 3
	doc.commit()
	doc.update_nav()
	check(doc.room_at(Vector3(0, 0, 7)) != doc.room_at(Vector3(0, 2, -6)), "3 stairs are too steep: the upper floor is cut off")
	doc.find(stairs).steps = 8
	doc.commit()
	var box := Items.local_aabb("piece", doc.find(curve), doc.level)
	check(box.size.x < 8.0 and box.size.z > 1.0, "a curved wall's box follows its curve (%s)" % box)
	check(not Items.sides_resizable("piece", doc.find(curve)) and Items.get_size("piece", doc.find(curve), doc.level).x == 8.0,
		"and it resizes by its length along the curve")

	# Checks and export.
	check(LevelCheck.errors(LevelCheck.run(doc)).filter(func(p): return String(p.text).contains("material")).is_empty(), "a good material raises no problems")
	var saved_license := String(mat.license)
	mat.license = ""
	doc.commit()
	check(texts(LevelCheck.run(doc)).contains("has no license for its images"), "a material's images need a license")
	mat.license = saved_license
	doc.find(curve).material = "gone"
	doc.commit()
	check(texts(LevelCheck.run(doc)).contains("isn't in the level (\"gone\")"), "painting with a missing material is caught")
	doc.find(curve).erase("material")
	doc.level.map.materials.append({"id": "unused", "name": "Unused", "color": [1, 0, 0]})
	doc.commit()
	var out_dir := "/tmp/library_export"
	for f in (DirAccess.get_files_at(out_dir.path_join("assets")) if DirAccess.dir_exists_absolute(out_dir.path_join("assets")) else PackedStringArray()):
		DirAccess.remove_absolute(out_dir.path_join("assets").path_join(f))
	var err := Exporter.to_folder(doc.level, out_dir)
	var exported := LevelData.load_dir(out_dir)
	check(err == "" and FileAccess.file_exists(out_dir.path_join(String(mat.albedo))), "export copies the material's image")
	check(exported != null and exported.find_material("unused").is_empty() and not exported.find_material(String(mat.id)).is_empty(),
		"and leaves out materials nothing uses")
	check(exported != null and exported.find_asset("library_stump").is_empty(), "and models nothing uses")

	# Deleting a material unpaints what wore it.
	doc.remove_material(String(mat.id))
	doc.commit()
	check(not doc.find(floor_id).has("material"), "deleting a material puts pieces back to their color")
	print("FAILS: ", fails)
	quit(fails)


func texts(problems: Array) -> String:
	return " | ".join(problems.map(func(p): return String(p.text)))
