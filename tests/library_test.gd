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
	var orm := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	orm.fill(Color(1.0, 0.7, 0.2))
	var orm_tex := ImageTexture.create_from_image(orm)
	mat.roughness_texture = orm_tex
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.metallic_texture = orm_tex
	mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	mat.metallic = 1.0
	mat.roughness = 1.0
	mat.ao_enabled = true
	mat.ao_texture = orm_tex
	mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.normal_enabled = true
	var flat := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	flat.fill(Color(0.5, 0.5, 1.0))
	mat.normal_texture = ImageTexture.create_from_image(flat)
	mat.normal_scale = 1.5
	mat.emission_enabled = true
	mat.emission = Color(1, 0.4, 0)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.3
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
	var problem: String = app.dialogs.import_file(model_path, "obstacle", "convex", "decoration", "Rocks/Small", true)
	await settle()
	check(problem == "", "a model imports (%s)" % problem)
	var asset := doc.level.find_asset("library_stump")
	check(asset.get("category") == "decoration" and asset.get("folder") == "Rocks/Small", "it goes into Decorations / Rocks / Small")
	check(doc.level.map.materials.size() == 1, "its material comes along")
	var mat: Dictionary = doc.level.map.materials[0] if doc.level.map.materials.size() > 0 else {}
	check(String(mat.get("albedo", "")) != "" and FileAccess.file_exists(dir.path_join(String(mat.get("albedo", "")))),
		"with its image saved in the level's assets (%s)" % mat.get("albedo", ""))
	check(mat.get("folder") == "Library Stump" and not mat.has("license"), "in a folder named after the model, with no license needed")
	print("     imported material: ", mat)
	check(mat.get("mapping") == "uv", "a model's material keeps the model's UVs")
	check(mat.has("normal") and is_equal_approx(float(mat.get("normal_strength", 0)), 1.5), "its normal map and strength come along")
	check(mat.has("roughness_map") and mat.has("metallic_map") and mat.get("roughness_channel") == "green" and mat.get("metallic_channel") == "blue",
		"its roughness and metallic map, with their channels")
	check(mat.get("roughness_map") == mat.get("metallic_map"), "  saved once when they share an image")
	check(mat.has("ao_map") and mat.get("ao_channel") == "red", "its occlusion map")
	check(mat.has("emission") and is_equal_approx(float(mat.get("emission_energy", 0)), 2.0), "its glow")
	check(mat.get("transparency") == "cutout" and is_equal_approx(float(mat.get("alpha_cutoff", 0)), 0.3), "and its cut-out transparency")
	var built := LevelMaterials.build(doc.level, String(mat.id))
	check(built != null and built.roughness_texture != null and built.ao_enabled and built.emission_enabled
		and built.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and not built.uv1_triplanar, "and it all shows in the editor")
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
	check(not texts(LevelCheck.run(doc)).to_lower().contains("license"), "nothing asks for a license")

	# Licenses: one optional folder per level.
	check(Licenses.list(doc.level).is_empty(), "a new level has no licenses")
	var pack := "/tmp/library_pack"
	DirAccess.make_dir_recursive_absolute(pack)
	for spec in [["License.txt", "CC0 1.0 Universal"], ["LICENSE", "MIT License"], ["notes.zip", "PK"]]:
		var lf := FileAccess.open(pack.path_join(spec[0]), FileAccess.WRITE)
		lf.store_string(spec[1])
		lf.close()
	check(Licenses.add_file(doc.level, pack.path_join("License.txt")) == "License.txt", "a pack's License.txt is added")
	check(Licenses.add_file(doc.level, pack.path_join("License.txt")) == "License.txt" and Licenses.list(doc.level).size() == 1,
		"adding the same file again keeps one copy")
	check(Licenses.add_file(doc.level, pack.path_join("LICENSE")) == "LICENSE.txt", "a LICENSE file with no extension is kept as .txt")
	check(Licenses.add_file(doc.level, pack.path_join("notes.zip")) == "", "but a zip isn't a license")
	var written := Licenses.write(doc.level, "Trees by Sam (CC-BY)", "Credit Sam for the trees.")
	check(written == "Trees by Sam (CC-BY).txt" and FileAccess.get_file_as_string(Licenses.folder(doc.level).path_join(written)).begins_with("Credit Sam"),
		"a license can be written in the editor (%s)" % written)
	var other := DirAccess.open(pack)
	other.make_dir("other")
	var lf2 := FileAccess.open(pack.path_join("other/License.txt"), FileAccess.WRITE)
	lf2.store_string("Something else")
	lf2.close()
	check(Licenses.add_file(doc.level, pack.path_join("other/License.txt")) == "License (2).txt", "a different file with the same name gets a new one")
	Licenses.remove(doc.level, "License (2).txt")
	check(Licenses.list(doc.level) == PackedStringArray(["LICENSE.txt", "License.txt", "Trees by Sam (CC-BY).txt"]),
		"and removing one leaves the rest (%s)" % ", ".join(Licenses.list(doc.level)))
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
	check(Licenses.list(exported).size() == 3, "export takes the licenses folder along")

	# The dialogs build: Licenses, import, material and imported models.
	app.dialogs.licenses()
	await settle()
	var shown := app.dialogs._open as Window
	var labels := shown.find_children("*", "Label", true, false).map(func(l): return (l as Label).text) if shown else []
	check(shown != null and shown.title == "Licenses" and labels.has("License.txt") and labels.has("Trees by Sam (CC-BY).txt"),
		"Level > Licenses lists the level's license files")
	for open_one in [func(): app.dialogs._import_details(model_path), func(): app.dialogs.material_dialog(String(mat.id)), func(): app.dialogs.models()]:
		open_one.call()
		await settle()
		shown = app.dialogs._open as Window
		var texts_in := shown.find_children("*", "Button", true, false).map(func(x): return (x as Button).text) if shown else []
		check(shown != null and (texts_in.has("Add a license file...") or texts_in.has("Licenses...")),
			"%s offers licenses but doesn't ask for one" % (shown.title if shown else "?"))
		check(shown != null and not shown.find_children("*", "OptionButton", true, false).any(func(o): return (o as OptionButton).get_item_text(0).contains("license")),
			"  with no license picker")
		if shown != null and shown is ConfirmationDialog:
			check(not (shown as ConfirmationDialog).get_ok_button().disabled, "  and OK works without one")
	shown.queue_free()

	# The material window: three tabs; saving keeps only settings in use.
	app.dialogs.material_dialog(String(mat.id))
	await settle()
	var mdlg := app.dialogs._open as ConfirmationDialog
	var tabs: TabContainer = mdlg.find_children("*", "TabContainer", true, false)[0] if mdlg else null
	check(tabs != null and tabs.get_tab_count() == 3 and tabs.get_tab_title(0) == "Colour" and tabs.get_tab_title(1) == "Surface"
		and tabs.get_tab_title(2) == "Glow", "the material window has Colour, Surface and Glow tabs")
	if mdlg:
		mdlg.confirmed.emit()
	await settle()
	var saved_mat := doc.level.find_material(String(mat.id))
	check(saved_mat.get("roughness_channel") == "green" and saved_mat.get("ao_channel") == "red" and saved_mat.get("transparency") == "cutout"
		and saved_mat.get("mapping") == "uv" and saved_mat.has("emission"), "saving it unchanged keeps every setting")
	saved_mat.erase("ao_map")
	saved_mat.erase("emission")
	saved_mat.erase("emission_energy")
	saved_mat.transparency = "none"
	doc.commit()
	app.dialogs.material_dialog(String(mat.id))
	await settle()
	(app.dialogs._open as ConfirmationDialog).confirmed.emit()
	await settle()
	saved_mat = doc.level.find_material(String(mat.id))
	check(not saved_mat.has("ao_channel") and not saved_mat.has("emission") and not saved_mat.has("alpha_cutoff") and not saved_mat.has("transparency"),
		"and settings for maps it doesn't use are left out of the file")
	saved_mat.height_map = saved_mat.albedo
	saved_mat.mapping = "world"
	doc.commit()
	check(texts(LevelCheck.run(doc)).contains("height maps only show"), "a height map on world mapping gets a warning")
	saved_mat.erase("height_map")
	saved_mat.ao_map = "assets/gone.png"
	doc.commit()
	check(texts(LevelCheck.run(doc)).contains("occlusion map for the material"), "a missing map is caught")
	saved_mat.erase("ao_map")
	saved_mat.mapping = "uv"
	doc.commit()

	# Deleting a material unpaints what wore it.
	doc.remove_material(String(mat.id))
	doc.commit()
	check(not doc.find(floor_id).has("material"), "deleting a material puts pieces back to their color")
	print("FAILS: ", fails)
	quit(fails)


func texts(problems: Array) -> String:
	return " | ".join(problems.map(func(p): return String(p.text)))
