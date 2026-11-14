class_name Dialogs
extends Node
## The editor's pop-up windows: welcome, new level, level settings, editor
## settings, imported models, the trigger editor, export, and the small
## "are you sure" questions.

var app: Node
var _open: Window
var _rule := {}
var _rule_box: VBoxContainer
var _rule_text: Label


func _doc() -> EditorDoc:
	return app.doc


# --- Helpers ----------------------------------------------------------------------------------

func _show(dialog: Window, min_size := Vector2i(520, 0)) -> void:
	if _open and is_instance_valid(_open):
		_open.hide()  # gives up being the exclusive window right away
		_open.queue_free()
	_open = dialog
	dialog.min_size = min_size
	app.add_child(dialog)
	dialog.popup_centered()
	dialog.close_requested.connect(dialog.queue_free)
	if dialog is AcceptDialog and not (dialog as AcceptDialog).canceled.is_connected(dialog.queue_free):
		(dialog as AcceptDialog).canceled.connect(dialog.queue_free)


func _vbox(dialog: AcceptDialog) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)
	return box


static func _label(text: String, dim := false, size := 0) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 420
	if dim:
		label.add_theme_color_override("font_color", Color(0.72, 0.75, 0.8))
	if size > 0:
		label.add_theme_font_size_override("font_size", size)
	return label


static func _row(box: Container, text: String, editor: Control, tip := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 170
	label.tooltip_text = tip
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(label)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.tooltip_text = tip
	row.add_child(editor)
	box.add_child(row)
	return row


static func _options(options: Array, current: Variant) -> OptionButton:
	var ob := OptionButton.new()
	for i in options.size():
		ob.add_item(String(options[i][1]))
		ob.set_item_metadata(i, options[i][0])
		if options[i][0] == current:
			ob.select(i)
	return ob


static func _size_options(current: String) -> OptionButton:
	var options := []
	for key in LevelData.SIZES:
		var lim: Array = LevelData.SIZES[key]
		options.append([key, "%s: %s" % [LevelData.SIZE_NAMES[key], "1 room, no corridors" if lim[1] == 1 else "%d to %d rooms" % [lim[0], lim[1]]]])
	return _options(options, current)


## A question with OK / Cancel.
func ask(title: String, text: String, ok_text: String, on_ok: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.ok_button_text = ok_text
	_vbox(dialog).add_child(_label(text))
	dialog.confirmed.connect(func() -> void:
		on_ok.call()
		dialog.queue_free())
	_show(dialog)


## Asks for a line of text; calls on_ok(text) if it isn't empty.
func ask_text(title: String, prompt: String, current: String, on_ok: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	var box := _vbox(dialog)
	box.add_child(_label(prompt))
	var edit := LineEdit.new()
	edit.text = current
	edit.select_all_on_focus = true
	box.add_child(edit)
	var done := func() -> void:
		var text := edit.text.strip_edges()
		dialog.queue_free()
		if text != "":
			on_ok.call(text)
	dialog.confirmed.connect(done)
	edit.text_submitted.connect(func(_t: String) -> void:
		dialog.hide()
		done.call())
	dialog.canceled.connect(dialog.queue_free)
	_show(dialog)
	edit.grab_focus.call_deferred()


func tell(title: String, text: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	_vbox(dialog).add_child(_label(text))
	dialog.confirmed.connect(dialog.queue_free)
	_show(dialog)


## Runs `then` once it's safe to leave the current level (saved, or the
## user chose not to save).
func leave_level(then: Callable) -> void:
	var doc := _doc()
	if doc == null or not doc.dirty:
		then.call()
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Unsaved changes"
	dialog.ok_button_text = "Save"
	_vbox(dialog).add_child(_label("Save the changes to \"%s\" first?" % doc.level.meta.get("name", "this level")))
	dialog.add_button("Don't save", true, "discard")
	dialog.confirmed.connect(func() -> void:
		app.save_level()
		dialog.queue_free()
		then.call())
	dialog.custom_action.connect(func(_action: StringName) -> void:
		dialog.queue_free()
		then.call())
	_show(dialog)


func pick_file(mode: FileDialog.FileMode, title: String, filters: PackedStringArray, on_pick: Callable, start_dir := "") -> void:
	var fd := FileDialog.new()
	fd.file_mode = mode
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = title
	fd.filters = filters
	fd.use_native_dialog = DisplayServer.get_name() != "headless"
	if start_dir != "" and DirAccess.dir_exists_absolute(start_dir):
		fd.current_dir = start_dir
	fd.file_selected.connect(on_pick)
	fd.dir_selected.connect(on_pick)
	fd.files_selected.connect(on_pick)
	app.add_child(fd)
	fd.popup_centered_ratio(0.6)


# --- Welcome ----------------------------------------------------------------------------------

func welcome() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Nomad's Seekers Level Editor"
	dialog.ok_button_text = "Close"
	var box := _vbox(dialog)
	box.add_child(_label("Build a level", false, 18))
	box.add_child(_label("A level is built in three layers: the Map (rooms and scenery), Interaction (doors, buttons, triggers) and Combat (enemies and waves). You can switch between them at any time.", true))
	var buttons := HBoxContainer.new()
	var new_button := Button.new()
	new_button.text = "New level..."
	new_button.pressed.connect(func() -> void:
		dialog.queue_free()
		new_level())
	buttons.add_child(new_button)
	var open_button := Button.new()
	open_button.text = "Open a level folder..."
	open_button.pressed.connect(func() -> void:
		dialog.queue_free()
		open_level())
	buttons.add_child(open_button)
	var example_button := Button.new()
	example_button.text = "Open the starter example"
	example_button.tooltip_text = "A finished 15-room level to look around and pull apart. You get your own copy, so change anything."
	example_button.pressed.connect(func() -> void:
		dialog.queue_free()
		app.open_example())
	buttons.add_child(example_button)
	box.add_child(buttons)
	box.add_child(_label("Or build a quest: its people and props on Nomad-2, its steps, and where the teleporter goes while it's on.", true))
	var quest_buttons := HBoxContainer.new()
	for spec in [["New quest...", "new_quest"], ["Open a quest folder...", "open_quest"]]:
		var b := Button.new()
		b.text = spec[0]
		var method: String = spec[1]
		b.pressed.connect(func() -> void:
			dialog.queue_free()
			app.quests.call(method))
		quest_buttons.add_child(b)
	box.add_child(quest_buttons)
	var levels := library_levels()
	if not levels.is_empty():
		box.add_child(_label("Your levels (double-click to open)"))
		var list := ItemList.new()
		list.custom_minimum_size = Vector2(520, 220)
		for path in levels:
			var data := LevelData.load_dir(path)
			if data == null:
				continue
			var index := list.add_item("%s   (%s%s)" % [data.meta.get("name", "Untitled"), data.size_name(),
				", " + String(data.meta.area) if String(data.meta.get("area", "")) != "" else ""])
			list.set_item_metadata(index, path)
			list.set_item_tooltip(index, path)
		list.item_activated.connect(func(index: int) -> void:
			dialog.queue_free()
			app.open_path(String(list.get_item_metadata(index))))
		box.add_child(list)
	if not AppSettings.has_game():
		box.add_child(_label("Tip: tell the editor where the game is (Settings) to playtest levels and export straight into it.", true))
		var settings_button := Button.new()
		settings_button.text = "Settings..."
		settings_button.pressed.connect(func() -> void:
			dialog.queue_free()
			settings())
		box.add_child(settings_button)
	dialog.confirmed.connect(dialog.queue_free)
	_show(dialog, Vector2i(600, 0))


## Recently opened levels, then everything in the library folder.
func library_levels() -> PackedStringArray:
	var out := AppSettings.recent()
	var lib := AppSettings.library_dir()
	if DirAccess.dir_exists_absolute(lib):
		for sub in DirAccess.get_directories_at(lib):
			var path := lib.path_join(sub)
			if LevelData.is_level_dir(path) and not out.has(path):
				out.append(path)
	return out


func open_level() -> void:
	pick_file(FileDialog.FILE_MODE_OPEN_DIR, "Open a level folder (the one with level.json)", PackedStringArray(),
		func(path: String) -> void: app.open_path(path), AppSettings.library_dir())


# --- New level --------------------------------------------------------------------------------

func new_level() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "New level"
	dialog.ok_button_text = "Create"
	var box := _vbox(dialog)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Mossy Glade"
	_row(box, "Name", name_edit)
	var area := LineEdit.new()
	area.placeholder_text = "forest_1 (optional)"
	_row(box, "Area", area, "The area this level belongs to, like forest_1 or forest_boss. The game picks one level per area each session. You can leave it empty for now.")
	var areas := Catalog.game_areas()
	if not areas.is_empty():
		box.add_child(_label("Areas in the game: " + ", ".join(areas), true))
	var light := _options([["day", "Day"], ["dusk", "Dusk"], ["overcast", "Overcast"], ["night", "Night"], ["cave", "Cave"], ["interior", "Indoors"]], "day")
	_row(box, "Lighting", light)
	var starter := CheckBox.new()
	starter.text = "Start me off with a 16 x 16 m floor"
	starter.button_pressed = true
	box.add_child(starter)
	box.add_child(_label("It's saved in: " + AppSettings.library_dir(), true))
	dialog.confirmed.connect(func() -> void:
		var level_name := name_edit.text.strip_edges()
		if level_name == "":
			level_name = "Untitled"
		var dir := AppSettings.library_dir().path_join(EditorDoc.slug(level_name))
		var n := 2
		while DirAccess.dir_exists_absolute(dir):
			dir = AppSettings.library_dir().path_join("%s_%d" % [EditorDoc.slug(level_name), n])
			n += 1
		var doc := EditorDoc.create(level_name, EditorDoc.slug(area.text) if area.text.strip_edges() != "" else "", dir)
		doc.level.map.lighting.preset = light.get_selected_metadata()
		if starter.button_pressed:
			doc.add("piece", {"asset": "builtin:box", "size": [16, 0.5, 16], "pos": [0, -0.5, 0], "surface": "floor", "color": Catalog.FLOOR_COLOR})
			doc.level.map.start = {"pos": [0, 0.1, 4], "yaw": 0}
		doc._reset_history()
		var err := doc.save()
		dialog.queue_free()
		if err != OK:
			tell("Couldn't create the level", "The folder %s couldn't be written (%s). Choose another library folder in Settings." % [dir, error_string(err)])
			return
		app.set_doc(doc))
	_show(dialog)
	name_edit.grab_focus.call_deferred()


# --- Level settings ---------------------------------------------------------------------------

func level_settings() -> void:
	var doc := _doc()
	var meta := doc.level.meta
	var dialog := AcceptDialog.new()
	dialog.title = "Level settings"
	dialog.ok_button_text = "Done"
	var box := _vbox(dialog)
	var set_meta := func(key: String, value: Variant) -> void:
		meta[key] = value
		doc.commit("meta:" + key)
	for spec in [["name", "Name", ""], ["author", "Made by", ""], ["area", "Area", "The area folder this level belongs to in the game, like forest_1 or forest_boss."]]:
		var edit := LineEdit.new()
		edit.text = String(meta.get(spec[0], ""))
		var key: String = spec[0]
		edit.text_changed.connect(func(text: String) -> void: set_meta.call(key, EditorDoc.slug(text) if key == "area" and text.strip_edges() != "" else text))
		_row(box, spec[1], edit, spec[2])
	box.add_child(_label("Size: " + Inspector.size_summary(doc.level) + " The size follows the room count.", true))
	var about := TextEdit.new()
	about.text = String(meta.get("description", ""))
	about.custom_minimum_size.y = 70
	about.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	about.text_changed.connect(func() -> void: set_meta.call("description", about.text))
	_row(box, "Description", about)
	box.add_child(HSeparator.new())
	box.add_child(_label("Lighting", false, 15))
	box.add_child(_label("Sliders stop where a level would become too dark to see or uncomfortably bright. For a room that's meant to be dark, use the Darkness hazard.", true))
	var lighting: Dictionary = doc.level.map.lighting
	var preset := _options([["day", "Day"], ["dusk", "Dusk"], ["overcast", "Overcast"], ["night", "Night"], ["cave", "Cave"], ["interior", "Indoors"]],
		String(lighting.get("preset", "day")))
	preset.item_selected.connect(func(index: int) -> void:
		lighting.preset = preset.get_item_metadata(index)
		doc.commit("light:preset"))
	_row(box, "Look", preset)
	for spec in [["sun_energy", "Sunlight"], ["ambient_energy", "Fill light"], ["exposure", "Exposure"], ["fog_density", "Fog"]]:
		var lim: Array = LevelData.LIGHT_LIMITS[spec[0]]
		var slider := HSlider.new()
		slider.min_value = lim[0]
		slider.max_value = lim[1]
		slider.step = (float(lim[1]) - float(lim[0])) / 100.0
		slider.value = float(lighting.get(spec[0], 1.0))
		var key: String = spec[0]
		slider.value_changed.connect(func(v: float) -> void:
			lighting[key] = snappedf(v, 0.0001)
			doc.commit("light:" + key))
		_row(box, spec[1], slider)
	dialog.confirmed.connect(dialog.queue_free)
	_show(dialog, Vector2i(620, 0))


# --- Editor settings --------------------------------------------------------------------------

func settings() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Settings"
	dialog.ok_button_text = "Save"
	var box := _vbox(dialog)
	var edits := {}
	for spec in [
			["game_dir", "Game folder", "The Nomad's Seekers project folder (the one with project.godot). Needed to playtest, to list the game's enemies and areas, and to export straight into the game.", FileDialog.FILE_MODE_OPEN_DIR, AppSettings.game_dir()],
			["run_with", "Run the game with", "The Godot program (it runs the game folder), or a built copy of the game. Used by Playtest. Leave empty to use the Godot this editor is running on.", FileDialog.FILE_MODE_OPEN_FILE, String(AppSettings.get_value("run_with", ""))],
			["library_dir", "My levels folder", "Where new levels are made.", FileDialog.FILE_MODE_OPEN_DIR, AppSettings.library_dir()]]:
		box.add_child(_label(spec[1], false, 14))
		box.add_child(_label(spec[2], true))
		var row := HBoxContainer.new()
		var edit := LineEdit.new()
		edit.text = spec[4]
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(edit)
		var browse := Button.new()
		browse.text = "Browse..."
		var mode: FileDialog.FileMode = spec[3]
		browse.pressed.connect(func() -> void:
			pick_file(mode, spec[1], PackedStringArray(), func(path: String) -> void: edit.text = path, edit.text))
		row.add_child(browse)
		box.add_child(row)
		edits[spec[0]] = edit
	dialog.confirmed.connect(func() -> void:
		var game := String((edits.game_dir as LineEdit).text).strip_edges()
		if game.ends_with("project.godot"):
			game = game.get_base_dir()
		for key in edits:
			AppSettings.set_value(key, game if key == "game_dir" else String((edits[key] as LineEdit).text).strip_edges())
		dialog.queue_free()
		if game != "" and not AppSettings.has_game():
			tell("That doesn't look like the game", "There's no project.godot in %s. Choose the Nomad's Seekers project folder." % game)
		app.settings_changed())
	_show(dialog, Vector2i(680, 0))


# --- Imported models --------------------------------------------------------------------------

func import_model(category := "prefab", folder := "") -> void:
	pick_file(FileDialog.FILE_MODE_OPEN_FILE, "Import a model (glTF)", PackedStringArray(["*.glb,*.gltf ; glTF models"]),
		func(path: String) -> void: _import_details(path, category, folder))


func _import_details(path: String, category := "prefab", folder := "") -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Import " + path.get_file()
	dialog.ok_button_text = "Import"
	var box := _vbox(dialog)
	var where := _options([["prefab", "Prefabs (buildings, bridges, set pieces)"], ["decoration", "Decorations (plants, rocks, props)"]], category)
	_row(box, "Goes in", where, "Where it's listed in the Place list. It's only for finding things; it doesn't change how the model works.")
	var folder_edit := _folder_field(category, folder)
	_row(box, "Folder", folder_edit, "Optional. Use / for folders inside folders, like Forest/Trees. You can rearrange them later in the Place list.")
	where.item_selected.connect(func(index: int) -> void: _fill_folder_menu(folder_edit, String(where.get_item_metadata(index))))
	var found := _model_materials(path)
	var take_materials := CheckBox.new()
	take_materials.text = "Also add its %d material%s to Materials" % [found, "" if found == 1 else "s"]
	take_materials.button_pressed = found > 0
	take_materials.tooltip_text = "Its colors and images become level materials you can paint onto shapes."
	if found > 0:
		box.add_child(take_materials)
	box.add_child(HSeparator.new())
	box.add_child(_license_row())
	box.add_child(HSeparator.new())
	var surface := _surface_options("obstacle")
	_row(box, "Acts as", surface, "\n".join(Catalog.SURFACE_HELP.values()))
	var surface_help := _label(Catalog.SURFACE_HELP.obstacle, true)
	box.add_child(surface_help)
	var hitbox := _hitbox_options("concave")
	_row(box, "Hitbox", hitbox, "How its collision is made from its shape.")
	var hitbox_help := _label("Concave follows every triangle (exact; best for floors, arches and buildings). Convex wraps it in one hull (faster; fine for rocks, crates and barrels, but fills in arches).", true)
	box.add_child(hitbox_help)
	box.add_child(_label("You can change these later for the model (Level > Imported models) or for any one placed copy (in the inspector).", true))
	surface.item_selected.connect(func(index: int) -> void:
		var key := String(surface.get_item_metadata(index))
		surface_help.text = String(Catalog.SURFACE_HELP[key])
		hitbox.disabled = key == "intangible")
	dialog.confirmed.connect(func() -> void:
		var problem := import_file(path, String(surface.get_selected_metadata()), String(hitbox.get_selected_metadata()),
			String(where.get_selected_metadata()), _folder_text(folder_edit), found > 0 and take_materials.button_pressed)
		dialog.queue_free()
		if problem != "":
			tell("Couldn't import the model", problem))
	_show(dialog)


## A folder box: type a path, or pick one of the category's folders.
func _folder_field(category: String, current: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.name = "Path"
	edit.text = current
	edit.placeholder_text = "(no folder)"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var pick := MenuButton.new()
	pick.name = "Pick"
	pick.text = "▾"
	pick.flat = false
	pick.tooltip_text = "Pick an existing folder."
	pick.get_popup().index_pressed.connect(func(index: int) -> void:
		edit.text = String(pick.get_popup().get_item_metadata(index)))
	row.add_child(pick)
	_fill_folder_menu(row, category)
	return row


func _fill_folder_menu(field: HBoxContainer, category: String) -> void:
	var popup := (field.get_node("Pick") as MenuButton).get_popup()
	popup.clear()
	popup.add_item("(no folder)")
	popup.set_item_metadata(0, "")
	for f in _doc().library_folders(category):
		popup.add_item(String(f))
		popup.set_item_metadata(popup.item_count - 1, String(f))


func _folder_text(field: HBoxContainer) -> String:
	return EditorDoc.clean_folder((field.get_node("Path") as LineEdit).text)


## How many materials a glTF model brings (0 if it can't be read).
func _model_materials(path: String) -> int:
	var state := GLTFState.new()
	if GLTFDocument.new().append_from_file(path, state) != OK:
		return 0
	return state.get_materials().size()


## Copies a model into the level's assets folder and lists it. Returns ""
## or what went wrong.
func import_file(path: String, surface := "obstacle", hitbox := "concave",
		category := "prefab", folder := "", with_materials := false) -> String:
	var doc := _doc()
	var ext := path.get_extension().to_lower()
	if not ext in ["glb", "gltf"]:
		return "Only .glb and .gltf models can be imported."
	var assets := doc.level.dir.path_join("assets")
	DirAccess.make_dir_recursive_absolute(assets)
	var id := EditorDoc.slug(path.get_file().get_basename())
	var taken := doc.level.ids()
	for a in doc.level.map.assets:
		taken[String(a.get("id", ""))] = true
	var base := id
	var n := 2
	while taken.has(id) or FileAccess.file_exists(assets.path_join(id + "." + ext)):
		id = "%s_%d" % [base, n]
		n += 1
	var dest := assets.path_join(id + "." + ext)
	var err := DirAccess.copy_absolute(path, dest)
	if err != OK:
		return "Couldn't copy the file (%s)." % error_string(err)
	if ext == "gltf":
		# A .gltf keeps its data and textures in files beside it.
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			for list in [parsed.get("buffers", []), parsed.get("images", [])]:
				for entry in list:
					var uri := String(entry.get("uri", ""))
					if uri != "" and not uri.begins_with("data:") and not uri.contains(".."):
						DirAccess.make_dir_recursive_absolute(assets.path_join(uri).get_base_dir())
						DirAccess.copy_absolute(path.get_base_dir().path_join(uri), assets.path_join(uri))
	Models.forget(dest)
	var test := GLTFDocument.new()
	if test.append_from_file(dest, GLTFState.new()) != OK:
		DirAccess.remove_absolute(dest)
		return "That file couldn't be read as a glTF model."
	var entry := {"id": id, "file": "assets/" + id + "." + ext,
		"surface": surface, "hitbox": hitbox, "category": category}
	doc.set_folder(entry, folder)
	doc.level.map.assets.append(entry)
	var made := extract_materials(dest, id) if with_materials else []
	doc.commit()
	app.toast("Imported \"%s\" as %s, under %s%s.%s" % [id, String(Catalog.SURFACE_NAMES[surface]).to_lower(),
		"Prefabs" if category == "prefab" else "Decorations", " / " + EditorDoc.clean_folder(folder) if EditorDoc.clean_folder(folder) != "" else "",
		" Added %d material%s." % [made.size(), "" if made.size() == 1 else "s"] if not made.is_empty() else ""])
	return ""


## Turns a glTF model's materials into level materials (their images saved
## as PNGs in assets/), in a Materials folder named after the model.
## Returns the new material ids.
func extract_materials(model_path: String, model_id: String) -> Array:
	var doc := _doc()
	var state := GLTFState.new()
	if GLTFDocument.new().append_from_file(model_path, state) != OK:
		return []
	var assets := doc.level.dir.path_join("assets")
	DirAccess.make_dir_recursive_absolute(assets)
	var saved := {}  # texture -> level path, so a packed image is saved once
	var out := []
	var n := 0
	for m in state.get_materials():
		n += 1
		var base := m as BaseMaterial3D
		if base == null:
			continue
		var label := base.resource_name if base.resource_name != "" else "%s %d" % [model_id.capitalize(), n]
		var id := _unique_material_id(EditorDoc.slug(model_id + "_" + label))
		# A model's textures are unwrapped onto its UVs, so they keep UV mapping.
		var spec := {"id": id, "name": label, "folder": model_id.capitalize(), "mapping": "uv", "uv_repeat": 1.0, "tile": 2.0,
			"color": _rgb(base.albedo_color), "roughness": snappedf(base.roughness, 0.01), "metallic": snappedf(base.metallic, 0.01)}
		var maps := [["albedo", base.albedo_texture, ""],
			["normal", base.normal_texture if base.normal_enabled else null, "_normal"],
			["roughness_map", base.roughness_texture, "_rough"],
			["metallic_map", base.metallic_texture, "_metal"],
			["ao_map", base.ao_texture if base.ao_enabled else null, "_ao"],
			["emission_map", base.emission_texture if base.emission_enabled else null, "_glow"],
			["height_map", base.heightmap_texture if base.heightmap_enabled else null, "_height"]]
		for entry in maps:
			var tex: Texture2D = entry[1]
			if tex == null:
				continue
			if not saved.has(tex):
				var image := tex.get_image()
				if image == null or image.is_empty():
					continue
				if image.is_compressed():
					image.decompress()
				var file := "%s%s.png" % [id, entry[2]]
				if image.save_png(assets.path_join(file)) != OK:
					continue
				saved[tex] = "assets/" + file
			spec[entry[0]] = saved[tex]
		if spec.has("normal"):
			spec.normal_strength = snappedf(base.normal_scale, 0.01)
		if spec.has("roughness_map"):
			spec.roughness_channel = LevelMaterials.channel_name(base.roughness_texture_channel)
		if spec.has("metallic_map"):
			spec.metallic_channel = LevelMaterials.channel_name(base.metallic_texture_channel)
		if spec.has("ao_map"):
			spec.ao_channel = LevelMaterials.channel_name(base.ao_texture_channel)
			spec.ao_strength = snappedf(base.ao_light_affect, 0.01) if base.ao_light_affect > 0.0 else 1.0
		if spec.has("height_map"):
			spec.height_scale = snappedf(base.heightmap_scale, 0.1)
		if base.emission_enabled:
			spec.emission = _rgb(base.emission)
			spec.emission_energy = snappedf(base.emission_energy_multiplier, 0.01)
		match base.transparency:
			BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
				spec.transparency = "cutout"
				spec.alpha_cutoff = snappedf(base.alpha_scissor_threshold, 0.01)
			BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
				spec.transparency = "alpha"
				if base.albedo_color.a < 1.0:
					spec.opacity = snappedf(base.albedo_color.a, 0.01)
		doc.level.map.materials.append(spec)
		out.append(id)
	return out


func _unique_material_id(base: String) -> String:
	var taken := _doc().level.ids()
	var id := base
	var n := 2
	while taken.has(id):
		id = "%s_%d" % [base, n]
		n += 1
	return id


# --- Materials -------------------------------------------------------------------------------

## Starts a new material from an image (picked first) or from nothing.
func import_material(folder := "") -> void:
	pick_file(FileDialog.FILE_MODE_OPEN_FILE, "Pick a colour image for the material", PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Images"]),
		func(path: String) -> void: material_dialog("", path, folder))


## Edits a material (or makes one: id "", optionally from an image file).
## Images picked here are copied into the level's assets folder on OK.
## Three tabs: Colour (image, tint, transparency), Surface (normal, roughness,
## metallic, ambient occlusion, height) and Glow.
func material_dialog(id := "", image_path := "", folder := "") -> void:
	var doc := _doc()
	var existing := doc.level.find_material(id) if id != "" else {}
	var spec: Dictionary = existing.duplicate(true) if not existing.is_empty() else {
		"name": image_path.get_file().get_basename().capitalize() if image_path != "" else "New material",
		"color": [1, 1, 1], "roughness": 0.85, "metallic": 0.0, "tile": 2.0}
	if existing.is_empty() and folder != "":
		spec.folder = folder
	var picked := {}  # new files to copy in, by image key
	for key in LevelData.MATERIAL_IMAGES:
		picked[key] = ""
	picked.albedo = image_path
	var dialog := ConfirmationDialog.new()
	dialog.title = "Material" if existing.is_empty() else "Material: " + String(spec.get("name", id))
	dialog.ok_button_text = "Add material" if existing.is_empty() else "Save"
	var box := _vbox(dialog)
	var name_edit := LineEdit.new()
	name_edit.text = String(spec.get("name", ""))
	_row(box, "Name", name_edit)
	var folder_edit := _folder_field("material", String(spec.get("folder", "")))
	_row(box, "Folder", folder_edit, "Optional. Use / for folders inside folders.")
	# Mapping.
	var mapping := _options([["world", "Across the world (tiles evenly at any size)"], ["uv", "The model's own UVs"]], String(spec.get("mapping", "world")))
	_row(box, "Mapping", mapping, "Across the world: images repeat every Tile size metres, so a material looks the same on a small step and a big floor. Best for shapes.\nThe model's own UVs: for a model's unwrapped textures, and needed for height maps.")
	var tile := _spin_box(float(spec.get("tile", 2.0)), 0.1, 100.0, 0.1)
	var tile_row := _row(box, "Tile size (m)", tile, "How many metres one copy of the images covers.")
	var repeat := _spin_box(float(spec.get("uv_repeat", 1.0)), 0.01, 100.0, 0.05)
	var repeat_row := _row(box, "Repeat", repeat, "How many times the images repeat across the model's UVs (1 for a model's own textures).")
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 380)
	box.add_child(tabs)

	# Colour.
	var colour := _tab(tabs, "Colour")
	_row(colour, "Colour image", _image_row(spec, picked, "albedo"), "The material's picture (optional: without one it's a plain color).")
	var tint := ColorPickerButton.new()
	var c := LevelData.vec3(spec.get("color"), Vector3.ONE)
	tint.color = Color(c.x, c.y, c.z)
	tint.edit_alpha = false
	tint.custom_minimum_size = Vector2(80, 0)
	_row(colour, "Color", tint, "Multiplied with the colour image, or the whole color without one.")
	var see_through := _options([["none", "Solid"], ["cutout", "Cut-out (leaves, fences, grates)"], ["alpha", "See-through (glass, water, ghosts)"]],
		String(spec.get("transparency", "none")))
	_row(colour, "Transparency", see_through, "Uses the colour image's alpha (transparent parts).\nCut-out drops pixels below the cut-off and shows both sides; see-through blends them.")
	var opacity := _spin_box(float(spec.get("opacity", 1.0)), 0.0, 1.0, 0.05)
	var opacity_row := _row(colour, "Opacity", opacity, "How solid a see-through material is (1 is fully solid).")
	var cutoff := _spin_box(float(spec.get("alpha_cutoff", 0.5)), 0.0, 1.0, 0.05)
	var cutoff_row := _row(colour, "Cut-off", cutoff, "Pixels less solid than this are dropped.")
	colour.add_child(_label("Solid pieces still block the way and carry the navmesh however see-through they look.", true))

	# Surface.
	var surface := _tab(tabs, "Surface")
	surface.add_child(_label("Maps are optional. A glTF model packs occlusion, roughness and metallic into one image (red, green and blue): pick it for all three with those channels.", true))
	_row(surface, "Normal map", _image_row(spec, picked, "normal"), "Bumpiness (a normal map).")
	var strength := _spin_box(float(spec.get("normal_strength", 1.0)), 0.0, 4.0, 0.1)
	_row(surface, "Normal strength", strength)
	var rough := _spin_box(float(spec.get("roughness", 0.85)), 0.0, 1.0, 0.05)
	var metal := _spin_box(float(spec.get("metallic", 0.0)), 0.0, 1.0, 0.05)
	_row(surface, "Roughness map", _image_row(spec, picked, "roughness_map", func() -> void: rough.value = 1.0), "Where it's glossy (dark) or matte (light).")
	var rough_channel := _channel_options(spec, "roughness_channel")
	_row(surface, "  channel", rough_channel)
	_row(surface, "Roughness", rough, "0 is glossy, 1 is matte. With a map, this multiplies it (leave it at 1).")
	_row(surface, "Metallic map", _image_row(spec, picked, "metallic_map", func() -> void: metal.value = 1.0), "Where it's metal (light) or not (dark).")
	var metal_channel := _channel_options(spec, "metallic_channel")
	_row(surface, "  channel", metal_channel)
	_row(surface, "Metallic", metal, "With a map, this multiplies it (leave it at 1).")
	_row(surface, "Occlusion map", _image_row(spec, picked, "ao_map"), "Ambient occlusion: darkens creases and corners.")
	var ao_channel := _channel_options(spec, "ao_channel")
	_row(surface, "  channel", ao_channel)
	var ao_strength := _spin_box(float(spec.get("ao_strength", 1.0)), 0.0, 1.0, 0.05)
	_row(surface, "  strength", ao_strength)
	_row(surface, "Height map", _image_row(spec, picked, "height_map"), "Fakes depth (parallax): light is high, dark is low.")
	var height := _spin_box(float(spec.get("height_scale", 5.0)), 0.0, 16.0, 0.5)
	_row(surface, "  depth", height)
	var height_note := _label("Height maps only work with Mapping: the model's own UVs.", true)
	surface.add_child(height_note)

	# Glow.
	var glow := _tab(tabs, "Glow")
	glow.add_child(_label("Makes the material give off its own light (it doesn't light up things around it; use a Light effect for that).", true))
	var glow_color := ColorPickerButton.new()
	var g := LevelData.vec3(spec.get("emission"), Vector3.ZERO)
	glow_color.color = Color(g.x, g.y, g.z)
	glow_color.edit_alpha = false
	glow_color.custom_minimum_size = Vector2(80, 0)
	_row(glow, "Glow color", glow_color, "Black is no glow.")
	_row(glow, "Glow map", _image_row(spec, picked, "emission_map"), "Which parts glow, in what colors. With a map and a black glow color, the map glows in its own colors.")
	var energy := _spin_box(float(spec.get("emission_energy", 1.0)), 0.0, 16.0, 0.1)
	_row(glow, "Brightness", energy)

	var update := func() -> void:
		var uv := String(mapping.get_selected_metadata()) == "uv"
		tile_row.visible = not uv
		repeat_row.visible = uv
		height_note.visible = not uv
		var mode := String(see_through.get_selected_metadata())
		opacity_row.visible = mode == "alpha"
		cutoff_row.visible = mode == "cutout"
	update.call()
	mapping.item_selected.connect(func(_i: int) -> void: update.call())
	see_through.item_selected.connect(func(_i: int) -> void: update.call())
	box.add_child(HSeparator.new())
	box.add_child(_license_row())
	dialog.confirmed.connect(func() -> void:
		var problem := ""
		for k in LevelData.MATERIAL_IMAGES:
			if String(picked[k]) != "":
				var copied := _copy_image(String(picked[k]))
				if copied == "":
					problem = "Couldn't copy %s into the level." % String(picked[k]).get_file()
				else:
					spec[k] = copied
		if problem != "":
			dialog.queue_free()
			tell("Couldn't save the material", problem)
			return
		spec.name = name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "Material"
		doc.set_folder(spec, _folder_text(folder_edit))
		spec.color = _rgb(tint.color)
		spec.roughness = rough.value
		spec.metallic = metal.value
		spec.tile = tile.value
		var has := func(key: String) -> bool: return String(spec.get(key, "")) != ""
		_keep(spec, String(mapping.get_selected_metadata()) == "uv", {"mapping": "uv", "uv_repeat": repeat.value})
		var mode := String(see_through.get_selected_metadata())
		_keep(spec, mode != "none", {"transparency": mode})
		_keep(spec, mode == "alpha" and opacity.value < 1.0, {"opacity": opacity.value})
		_keep(spec, mode == "cutout", {"alpha_cutoff": cutoff.value})
		_keep(spec, has.call("normal"), {"normal_strength": strength.value})
		_keep(spec, has.call("roughness_map"), {"roughness_channel": String(rough_channel.get_selected_metadata())})
		_keep(spec, has.call("metallic_map"), {"metallic_channel": String(metal_channel.get_selected_metadata())})
		_keep(spec, has.call("ao_map"), {"ao_channel": String(ao_channel.get_selected_metadata()), "ao_strength": ao_strength.value})
		_keep(spec, has.call("height_map"), {"height_scale": height.value})
		var glowing: bool = has.call("emission_map") or glow_color.color.get_luminance() > 0.0
		_keep(spec, glowing, {"emission": _rgb(glow_color.color), "emission_energy": energy.value})
		if existing.is_empty():
			spec.id = _unique_material_id(EditorDoc.slug(String(spec.name)))
			doc.level.map.materials.append(spec)
		else:
			existing.clear()
			existing.merge(spec)
		LevelMaterials.clear_cache()
		doc.commit()
		dialog.queue_free()
		app.toast("Saved the material \"%s\". Click it in the Place list, then click pieces to paint them." % spec.name))
	dialog.canceled.connect(dialog.queue_free)
	_show(dialog, Vector2i(680, 0))


## A tab page (a VBox) in a TabContainer.
func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 6)
	scroll.add_child(page)
	tabs.add_child(scroll)
	return page


## "file.png  [Choose...] [None]" for one of a material's images. Choosing
## a file calls on_pick (to nudge a setting that goes with it).
func _image_row(spec: Dictionary, picked: Dictionary, key: String, on_pick := Callable()) -> HBoxContainer:
	var row := HBoxContainer.new()
	var shown := Label.new()
	shown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shown.clip_text = true
	shown.custom_minimum_size.x = 160
	var choose := Button.new()
	choose.text = "Choose..."
	var clear := Button.new()
	clear.text = "None"
	row.add_child(shown)
	row.add_child(choose)
	row.add_child(clear)
	var refresh := func() -> void:
		var file := String(picked[key]) if String(picked[key]) != "" else String(spec.get(key, ""))
		shown.text = file.get_file() if file != "" else "(none)"
	refresh.call()
	choose.pressed.connect(func() -> void:
		pick_file(FileDialog.FILE_MODE_OPEN_FILE, "Pick an image", PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Images"]),
			func(path: String) -> void:
				picked[key] = path
				if on_pick.is_valid():
					on_pick.call()
				refresh.call()))
	clear.pressed.connect(func() -> void:
		picked[key] = ""
		spec.erase(key)
		refresh.call())
	return row


func _channel_options(spec: Dictionary, key: String) -> OptionButton:
	return _options([["gray", "Whole image (gray)"], ["red", "Red"], ["green", "Green"], ["blue", "Blue"], ["alpha", "Alpha"]],
		String(spec.get(key, "gray")))


## Sets `values` on spec when `wanted`, else takes those keys out (so unused
## settings don't clutter the level file).
static func _keep(spec: Dictionary, wanted: bool, values: Dictionary) -> void:
	for k in values:
		if wanted:
			spec[k] = values[k]
		else:
			spec.erase(k)


static func _rgb(c: Color) -> Array:
	return [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001)]


## Copies an image into the level's assets folder; returns its level path.
func _copy_image(path: String) -> String:
	var ext := path.get_extension().to_lower()
	if not LevelData.TEXTURE_FILES.has(ext):
		return ""
	var assets := _doc().level.dir.path_join("assets")
	DirAccess.make_dir_recursive_absolute(assets)
	var base := EditorDoc.slug(path.get_file().get_basename())
	var file := base + "." + ext
	var n := 2
	while FileAccess.file_exists(assets.path_join(file)):
		if FileAccess.get_md5(assets.path_join(file)) == FileAccess.get_md5(path):
			return "assets/" + file  # the same image is already there
		file = "%s_%d.%s" % [base, n, ext]
		n += 1
	if DirAccess.copy_absolute(path, assets.path_join(file)) != OK:
		return ""
	return "assets/" + file


func _spin_box(value: float, lo: float, hi: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.value = value
	spin.custom_minimum_size = Vector2(110, 0)
	return spin


func models() -> void:
	var doc := _doc()
	var dialog := AcceptDialog.new()
	dialog.title = "Imported models"
	dialog.ok_button_text = "Done"
	var box := _vbox(dialog)
	if (doc.level.map.assets as Array).is_empty():
		box.add_child(_label("No models imported yet. Import .glb or .gltf files (Kenney, KayKit, Quaternius and similar packs work well), then place them from the Map layer's palette.", true))
	for a in doc.level.map.assets:
		var used := 0
		for key in ["pieces", "decorations"]:
			for p in doc.level.map[key]:
				if String(p.get("asset", "")) == String(a.id):
					used += 1
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = "%s  (placed %d time(s))" % [a.id, used]
		name_label.custom_minimum_size.x = 220
		row.add_child(name_label)
		var surface := _surface_options(String(a.get("surface", "obstacle")))
		surface.tooltip_text = "\n".join(Catalog.SURFACE_HELP.values())
		var hitbox := _hitbox_options(String(a.get("hitbox", "concave")))
		hitbox.tooltip_text = "Concave follows every triangle; convex wraps it in one hull."
		hitbox.disabled = String(a.get("surface", "obstacle")) == "intangible"
		surface.item_selected.connect(func(index: int) -> void:
			a.surface = surface.get_item_metadata(index)
			hitbox.disabled = a.surface == "intangible"
			doc.commit())
		hitbox.item_selected.connect(func(index: int) -> void:
			a.hitbox = hitbox.get_item_metadata(index)
			doc.commit())
		row.add_child(surface)
		row.add_child(hitbox)
		var remove := Button.new()
		remove.text = "Remove"
		remove.disabled = used > 0
		remove.tooltip_text = "Delete the things that use it first." if used > 0 else "Take this model out of the level."
		remove.pressed.connect(func() -> void:
			(doc.level.map.assets as Array).erase(a)
			doc.commit()
			models())
		row.add_child(remove)
		box.add_child(row)
	var buttons := HBoxContainer.new()
	var add := Button.new()
	add.text = "Import a model..."
	add.pressed.connect(func() -> void:
		dialog.queue_free()
		import_model())
	buttons.add_child(add)
	var lic := Button.new()
	lic.text = "Licenses..."
	lic.pressed.connect(func() -> void:
		dialog.queue_free()
		licenses())
	buttons.add_child(lic)
	box.add_child(buttons)
	dialog.confirmed.connect(dialog.queue_free)
	_show(dialog, Vector2i(820, 0))


# --- Licenses ---------------------------------------------------------------------------------

## An optional "came with a license?" line for the import and material
## dialogs: adds files to the level's licenses folder straight away.
func _license_row() -> Control:
	var row := HBoxContainer.new()
	var note := _label("Came with a license? Keep it with the level (optional).", true)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(note)
	var add := Button.new()
	add.text = "Add a license file..."
	add.tooltip_text = "Copies it into the level's licenses folder (Level > Licenses). It goes along when you export or share the level."
	add.pressed.connect(func() -> void:
		pick_license_files(func(added: PackedStringArray) -> void:
			if not added.is_empty():
				note.text = "Added " + ", ".join(added) + "."))
	row.add_child(add)
	return row


## Picks license files and copies them in; on_done gets the names kept.
func pick_license_files(on_done := Callable()) -> void:
	pick_file(FileDialog.FILE_MODE_OPEN_FILES, "Add license files", PackedStringArray(Licenses.FILTERS), func(paths: Variant) -> void:
		var list: PackedStringArray = paths if paths is PackedStringArray else PackedStringArray([String(paths)])
		var added := PackedStringArray()
		var skipped := PackedStringArray()
		for path in list:
			var name := Licenses.add_file(_doc().level, path)
			if name == "":
				skipped.append(path.get_file())
			else:
				added.append(name)
		if not skipped.is_empty():
			app.toast("Skipped %s: licenses can be .txt, .md, .pdf, .rtf or .html files, or a file with no extension like LICENSE." % ", ".join(skipped))
		if on_done.is_valid():
			on_done.call(added))


## Level > Licenses: the level's license files, to add, write, open or remove.
func licenses() -> void:
	var doc := _doc()
	var dialog := AcceptDialog.new()
	dialog.title = "Licenses"
	dialog.ok_button_text = "Done"
	var box := _vbox(dialog)
	box.add_child(_label("One place for the licenses of anything you bring into this level: the License.txt from a model or texture pack, a note from the artist, your own terms. It's optional. The files are kept in the level's licenses folder and go along with it when you export or share it.", true))
	var files := Licenses.list(doc.level)
	if files.is_empty():
		box.add_child(_label("No licenses yet.", true))
	for f in files:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = f
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var open := Button.new()
		open.text = "Open"
		open.pressed.connect(func() -> void: OS.shell_open(Licenses.folder(doc.level).path_join(f)))
		row.add_child(open)
		var remove := Button.new()
		remove.text = "Remove"
		remove.pressed.connect(func() -> void:
			ask("Remove %s?" % f, "The file is deleted from the level's licenses folder.", "Remove", func() -> void:
				Licenses.remove(doc.level, f)
				licenses.call_deferred()))
		row.add_child(remove)
		box.add_child(row)
	var buttons := HBoxContainer.new()
	var add := Button.new()
	add.text = "Add files..."
	add.pressed.connect(func() -> void:
		pick_license_files(func(_added: PackedStringArray) -> void:
			if is_instance_valid(dialog):
				dialog.queue_free()
			licenses()))
	buttons.add_child(add)
	var write := Button.new()
	write.text = "Write one..."
	write.pressed.connect(func() -> void:
		dialog.queue_free()
		_write_license())
	buttons.add_child(write)
	var folder := Button.new()
	folder.text = "Open the folder"
	folder.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(Licenses.folder(doc.level))
		OS.shell_open(Licenses.folder(doc.level)))
	buttons.add_child(folder)
	box.add_child(buttons)
	dialog.confirmed.connect(dialog.queue_free)
	_show(dialog, Vector2i(620, 0))


func _write_license() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Write a license"
	dialog.ok_button_text = "Save"
	var box := _vbox(dialog)
	var title := LineEdit.new()
	title.placeholder_text = "Like: Forest pack by Kenney (CC0)"
	_row(box, "Name", title)
	var text := TextEdit.new()
	text.placeholder_text = "The license, or who made what and how it may be used."
	text.custom_minimum_size = Vector2(520, 220)
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(text)
	dialog.confirmed.connect(func() -> void:
		Licenses.write(_doc().level, title.text, text.text)
		dialog.queue_free()
		licenses())
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
		licenses())
	_show(dialog)


func _surface_options(current: String) -> OptionButton:
	var options := []
	for key in LevelData.SURFACES:
		options.append([key, Catalog.SURFACE_NAMES[key]])
	return _options(options, current)


func _hitbox_options(current: String) -> OptionButton:
	return _options([["concave", "Concave"], ["convex", "Convex"]], current)


# --- Triggers ---------------------------------------------------------------------------------

## Opens the trigger editor on a trigger (a new one when its id is "").
func edit_rule(rule: Dictionary) -> void:
	_rule = rule.duplicate(true)
	if not _rule.has("when"):
		_rule.when = {"event": "", "source": ""}
	if not _rule.has("do"):
		_rule["do"] = []
	var dialog := ConfirmationDialog.new()
	dialog.title = "New trigger" if String(_rule.get("id", "")) == "" else "Edit trigger"
	dialog.ok_button_text = "Save trigger"
	var outer := _vbox(dialog)
	_rule_text = _label("", false, 15)
	_rule_text.custom_minimum_size = Vector2(760, 50)
	_rule_text.add_theme_color_override("font_color", Color(0.65, 0.95, 0.7))
	outer.add_child(_rule_text)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(780, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rule_box = VBoxContainer.new()
	_rule_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rule_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_rule_box)
	outer.add_child(scroll)
	_fill_rule()
	dialog.confirmed.connect(func() -> void:
		var doc := _doc()
		if String(_rule.get("id", "")) == "":
			_rule.id = doc.new_rule_id()
		if String(Wiring.event_row(String(_rule.when.get("event", "")))[2]) == "":
			_rule.when.erase("source")
		if (_rule.get("if", []) as Array).is_empty():
			_rule.erase("if")
		doc.put_rule(_rule)
		doc.commit()
		dialog.queue_free())
	_show(dialog, Vector2i(820, 0))


func _fill_rule() -> void:
	var doc := _doc()
	for child in _rule_box.get_children():
		_rule_box.remove_child(child)
		child.queue_free()
	_rule_text.text = Wiring.describe(_rule, doc)
	var touch := func() -> void: _rule_text.text = Wiring.describe(_rule, doc)
	var when: Dictionary = _rule.when
	# --- When
	_rule_box.add_child(_label("WHEN", false, 14))
	var event := String(when.get("event", ""))
	var event_options := [["", "Choose what sets it off..."]] if event == "" else []
	for row in Wiring.EVENTS:
		event_options.append([row[0], row[1]])
	var event_pick := _options(event_options, Wiring.event_row(event)[0] if event != "" else "")
	event_pick.item_selected.connect(func(index: int) -> void:
		var chosen := String(event_pick.get_item_metadata(index))
		_rule.when = {"event": chosen}
		var options := Wiring.candidates(String(Wiring.event_row(chosen)[2]), doc)
		if not options.is_empty():
			_rule.when.source = options[0][0]
		if chosen == "health_below":
			_rule.when.value = 50
		_fill_rule())
	_row(_rule_box, "This happens", event_pick)
	var kinds := String(Wiring.event_row(event)[2])
	if event != "" and kinds != "":
		var sources := Wiring.candidates(kinds, doc)
		var source := String(when.get("source", ""))
		var known := false
		for s in sources:
			known = known or s[0] == source
		if not known:
			sources.push_front([source, "(choose)" if source == "" else "%s (missing)" % source])
		if sources.size() == 1 and not known:
			_rule_box.add_child(_label("There's nothing in the level this can come from yet. Place one first.", true))
		var source_pick := _options(sources, source)
		source_pick.item_selected.connect(func(index: int) -> void:
			when.source = source_pick.get_item_metadata(index)
			_fill_rule())
		_row(_rule_box, "From", source_pick)
	match event:
		"wave_cleared":
			var wave := SpinBox.new()
			wave.min_value = 0
			wave.max_value = 50
			wave.value = float(when.get("value", 0))
			wave.value_changed.connect(func(v: float) -> void:
				if v <= 0:
					when.erase("value")
				else:
					when.value = int(v)
				touch.call())
			_row(_rule_box, "Which wave (0 = any)", wave)
		"health_below":
			var percent := SpinBox.new()
			percent.min_value = 1
			percent.max_value = 99
			percent.suffix = "%"
			percent.value = float(when.get("value", 50))
			percent.value_changed.connect(func(v: float) -> void:
				when.value = int(v)
				touch.call())
			_row(_rule_box, "HP at or below", percent)
		"dialogue_ended":
			var choices := [["", "Any ending"]]
			for c in doc.find_dialogue(String(when.get("source", ""))).get("choices", []):
				choices.append([String(c.get("id", "")), "Choice: " + String(c.get("text", c.get("id", "")))])
			var choice_pick := _options(choices, String(when.get("value", "")))
			choice_pick.item_selected.connect(func(index: int) -> void:
				if String(choice_pick.get_item_metadata(index)) == "":
					when.erase("value")
				else:
					when.value = choice_pick.get_item_metadata(index)
				touch.call())
			_row(_rule_box, "Ending with", choice_pick)
	# --- Only if
	_rule_box.add_child(HSeparator.new())
	_rule_box.add_child(_label("ONLY IF (optional)", false, 14))
	var checks: Array = _rule.get("if", [])
	for i in checks.size():
		_rule_box.add_child(_condition_row(checks, i, touch))
	var add_check := Button.new()
	add_check.text = "Add a condition"
	add_check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_check.pressed.connect(func() -> void:
		checks.append({"check": "flag", "flag": "", "is": true})
		_rule["if"] = checks
		_fill_rule())
	_rule_box.add_child(add_check)
	# --- Do
	_rule_box.add_child(HSeparator.new())
	_rule_box.add_child(_label("DO (in this order)", false, 14))
	var actions: Array = _rule["do"]
	for i in actions.size():
		_rule_box.add_child(_action_row(actions, i, touch))
	var action_options := [["", "Add an action..."]]
	for row in Wiring.ACTIONS:
		action_options.append([row[0], row[1]])
	var add_action := _options(action_options, "")
	add_action.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_action.item_selected.connect(func(index: int) -> void:
		var chosen := String(add_action.get_item_metadata(index))
		if chosen != "":
			actions.append(_new_action(chosen))
			_fill_rule())
	_rule_box.add_child(add_action)
	_rule_box.add_child(HSeparator.new())
	var once := CheckBox.new()
	once.text = "Only the first time it happens"
	once.button_pressed = bool(_rule.get("once", true))
	once.toggled.connect(func(on: bool) -> void:
		_rule.once = on
		touch.call())
	_rule_box.add_child(once)


func _new_action(action: String) -> Dictionary:
	var a := {"action": action}
	var kinds := String(Wiring.action_row(action)[2])
	if kinds != "":
		var options := Wiring.candidates(kinds, _doc())
		a.target = options[0][0] if not options.is_empty() else ""
	match action:
		"wait":
			a.seconds = 1.0
		"banner":
			a.text = ""
		"set_flag":
			a.flag = ""
			a.value = true
		"start_timer":
			a.id = "timer_1"
			a.seconds = 10.0
		"give_item":
			a.item = "oro"
			a.amount = 100
		"complete_objective":
			a.key = ""
		"set_quest_flag", "set_story_flag":
			a.flag = ""
			a.value = true
		"take_item":
			a.item = "hp_gel"
			a.amount = 1
		"set_talk":
			var dialogues := Wiring.candidates("dialogue", _doc())
			a.dialogue = dialogues[0][0] if not dialogues.is_empty() else ""
	return a


func _action_row(actions: Array, i: int, touch: Callable) -> Control:
	var doc := _doc()
	var a: Dictionary = actions[i]
	var action := String(a.get("action", ""))
	var row := HBoxContainer.new()
	var number := Label.new()
	number.text = "%d." % (i + 1)
	row.add_child(number)
	var options := []
	for r in Wiring.ACTIONS:
		options.append([r[0], r[1]])
	var pick := _options(options, action)
	pick.custom_minimum_size.x = 250
	pick.clip_text = true
	pick.item_selected.connect(func(index: int) -> void:
		actions[i] = _new_action(String(pick.get_item_metadata(index)))
		_fill_rule())
	row.add_child(pick)
	var kinds := String(Wiring.action_row(action)[2])
	if kinds != "":
		var targets := Wiring.candidates(kinds, doc)
		var target := String(a.get("target", ""))
		var known := false
		for t in targets:
			known = known or t[0] == target
		if not known:
			targets.push_front([target, "(nothing to choose yet)" if targets.is_empty() else ("(choose)" if target == "" else "%s (missing)" % target)])
		var target_pick := _options(targets, target)
		target_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		target_pick.clip_text = true
		target_pick.item_selected.connect(func(index: int) -> void:
			a.target = target_pick.get_item_metadata(index)
			touch.call())
		row.add_child(target_pick)
	match action:
		"wait", "start_timer":
			if action == "start_timer":
				row.add_child(_text(a, "id", "timer name", touch))
			var seconds := SpinBox.new()
			seconds.min_value = 0
			seconds.max_value = 3600
			seconds.step = 0.1
			seconds.suffix = "s"
			seconds.value = float(a.get("seconds", 1.0))
			seconds.value_changed.connect(func(v: float) -> void:
				a.seconds = v
				touch.call())
			row.add_child(seconds)
		"banner":
			row.add_child(_text(a, "text", "What it says", touch))
		"set_flag", "set_quest_flag", "set_story_flag":
			row.add_child(_text(a, "flag", "flag name", touch))
			var value := CheckBox.new()
			value.text = "on"
			value.button_pressed = bool(a.get("value", true))
			value.toggled.connect(func(on: bool) -> void:
				a.value = on
				touch.call())
			row.add_child(value)
		"complete_objective":
			row.add_child(_text(a, "key", "the quest's objective key", touch))
		"give_item", "take_item":
			_item_controls(row, a, touch)
		"set_talk":
			var dialogues := Wiring.candidates("dialogue", doc)
			if dialogues.is_empty():
				dialogues = [["", "(make a dialogue first)"]]
			var said := _options(dialogues, String(a.get("dialogue", "")))
			said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			said.clip_text = true
			said.item_selected.connect(func(index: int) -> void:
				a.dialogue = said.get_item_metadata(index)
				touch.call())
			row.add_child(said)
	if i > 0:
		var up := Button.new()
		up.text = "Up"
		up.tooltip_text = "Do this earlier."
		up.pressed.connect(func() -> void:
			var moved: Dictionary = actions[i]
			actions[i] = actions[i - 1]
			actions[i - 1] = moved
			_fill_rule())
		row.add_child(up)
	var remove := Button.new()
	remove.text = "X"
	remove.tooltip_text = "Remove this action."
	remove.pressed.connect(func() -> void:
		actions.remove_at(i)
		_fill_rule())
	row.add_child(remove)
	return row


## Item, Lumidium colour and amount (give_item, take_item, has_item).
func _item_controls(row: HBoxContainer, a: Dictionary, touch: Callable) -> void:
	var item := _options(Wiring.ITEMS, String(a.get("item", "oro")))
	item.item_selected.connect(func(index: int) -> void:
		a.item = item.get_item_metadata(index)
		if String(a.item) == "lumidium":
			a.color = "raw"
		else:
			a.erase("color")
		_fill_rule())
	row.add_child(item)
	if String(a.get("item", "")) == "lumidium":
		var colors := []
		for c in LevelData.LUMIDIUM_COLORS:
			colors.append([c, String(c).capitalize()])
		var color := _options(colors, String(a.get("color", "raw")))
		color.item_selected.connect(func(index: int) -> void:
			a.color = color.get_item_metadata(index)
			touch.call())
		row.add_child(color)
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = 99999
	amount.value = float(a.get("amount", 1))
	amount.value_changed.connect(func(v: float) -> void:
		a.amount = int(v)
		touch.call())
	row.add_child(amount)


func _condition_row(checks: Array, i: int, touch: Callable) -> Control:
	var doc := _doc()
	var c: Dictionary = checks[i]
	var row := HBoxContainer.new()
	var kinds := [["flag", "A flag is"], ["party_at_least", "The party has at least"],
		["difficulty_at_least", "The difficulty is at least"], ["quest_active", "This quest is active"],
		["has_item", "The Seeker who talked has"], ["story_flag", "A story flag is"]]
	if doc.quest:
		kinds.append_array([["quest_step", "Quest step"], ["quest_flag", "A quest flag is"], ["escort_near", "An escort is near"]])
	var pick := _options(kinds, String(c.get("check", "flag")))
	pick.item_selected.connect(func(index: int) -> void:
		var check := String(pick.get_item_metadata(index))
		checks[i] = {"check": check}
		match check:
			"flag", "quest_flag", "story_flag":
				checks[i].merge({"flag": "", "is": true})
			"party_at_least":
				checks[i].value = 2
			"difficulty_at_least":
				checks[i].value = "hard"
			"quest_active":
				checks[i].value = ""
			"has_item":
				checks[i].merge({"item": "hp_gel", "amount": 1, "is": true})
			"quest_step":
				var steps := Wiring.candidates("step", doc)
				checks[i].merge({"step": steps[0][0] if not steps.is_empty() else "", "is": "done"})
			"escort_near":
				var people := Wiring.candidates("escort", doc)
				checks[i].merge({"target": people[0][0] if not people.is_empty() else "", "distance": 8.0, "is": true})
		_fill_rule())
	row.add_child(pick)
	match String(c.get("check", "")):
		"quest_flag", "story_flag":
			row.add_child(_text(c, "flag", "flag name", touch))
			var on := CheckBox.new()
			on.text = "on"
			on.button_pressed = bool(c.get("is", true))
			on.toggled.connect(func(v: bool) -> void:
				c["is"] = v
				touch.call())
			row.add_child(on)
		"has_item":
			_item_controls(row, c, touch)
			var have := CheckBox.new()
			have.text = "has it"
			have.tooltip_text = "Untick for \"doesn't have it\"."
			have.button_pressed = bool(c.get("is", true))
			have.toggled.connect(func(v: bool) -> void:
				c["is"] = v
				touch.call())
			row.add_child(have)
		"quest_step":
			var steps := Wiring.candidates("step", doc)
			var step_pick := _options(steps if not steps.is_empty() else [["", "(no steps yet)"]], String(c.get("step", "")))
			step_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			step_pick.clip_text = true
			step_pick.item_selected.connect(func(index: int) -> void:
				c.step = step_pick.get_item_metadata(index)
				touch.call())
			row.add_child(step_pick)
			var state := _options([["done", "is done"], ["current", "is the current step"], ["not_done", "isn't done yet"]], String(c.get("is", "done")))
			state.item_selected.connect(func(index: int) -> void:
				c["is"] = state.get_item_metadata(index)
				touch.call())
			row.add_child(state)
		"escort_near":
			var people := Wiring.candidates("escort", doc)
			var who := _options(people if not people.is_empty() else [["", "(nobody to escort)"]], String(c.get("target", "")))
			who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			who.clip_text = true
			who.item_selected.connect(func(index: int) -> void:
				c.target = who.get_item_metadata(index)
				touch.call())
			row.add_child(who)
			var within := SpinBox.new()
			within.min_value = 1
			within.max_value = 50
			within.suffix = "m"
			within.value = float(c.get("distance", 8.0))
			within.value_changed.connect(func(v: float) -> void:
				c.distance = v
				touch.call())
			row.add_child(within)
			var near := CheckBox.new()
			near.text = "near"
			near.tooltip_text = "Untick for \"not near\" (left behind)."
			near.button_pressed = bool(c.get("is", true))
			near.toggled.connect(func(v: bool) -> void:
				c["is"] = v
				touch.call())
			row.add_child(near)
	match String(c.get("check", "")):
		"flag":
			row.add_child(_text(c, "flag", "flag name", touch))
			var value := CheckBox.new()
			value.text = "on"
			value.button_pressed = bool(c.get("is", true))
			value.toggled.connect(func(on: bool) -> void:
				c["is"] = on
				touch.call())
			row.add_child(value)
		"party_at_least":
			var count := SpinBox.new()
			count.min_value = 1
			count.max_value = 6
			count.suffix = " Seekers"
			count.value = float(c.get("value", 2))
			count.value_changed.connect(func(v: float) -> void:
				c.value = int(v)
				touch.call())
			row.add_child(count)
		"difficulty_at_least":
			var tiers := []
			for t in LevelData.DIFFICULTIES:
				tiers.append([t, String(t).capitalize()])
			var tier := _options(tiers, String(c.get("value", "hard")))
			tier.item_selected.connect(func(index: int) -> void:
				c.value = tier.get_item_metadata(index)
				touch.call())
			row.add_child(tier)
		"quest_active":
			row.add_child(_text(c, "value", "quest id", touch))
	var remove := Button.new()
	remove.text = "X"
	remove.pressed.connect(func() -> void:
		checks.remove_at(i)
		_fill_rule())
	row.add_child(remove)
	return row


func _text(d: Dictionary, key: String, placeholder: String, touch: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = String(d.get(key, ""))
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func(text: String) -> void:
		d[key] = text
		touch.call())
	return edit


# --- Export -----------------------------------------------------------------------------------

func export_level() -> void:
	var doc := _doc()
	var problems := LevelCheck.run(doc)
	var errors := LevelCheck.errors(problems)
	var warnings := LevelCheck.warnings(problems)
	var dialog := AcceptDialog.new()
	dialog.title = "Export \"%s\"" % doc.level.meta.get("name", "level")
	dialog.ok_button_text = "Close"
	var box := _vbox(dialog)
	if errors.is_empty() and warnings.is_empty():
		box.add_child(_label("The level check found nothing wrong.", false, 18))
	elif errors.is_empty():
		box.add_child(_label("Ready to export, with %d thing(s) worth a look." % warnings.size(), false, 18))
	else:
		box.add_child(_label("%d thing(s) must be fixed before this level can be exported." % errors.size(), false, 18))
		box.add_child(_label("These would break the level or make it impossible to finish. Double-click one to go to it.", true))
	if not problems.is_empty():
		var list := ItemList.new()
		list.custom_minimum_size = Vector2(700, 260)
		list.auto_height = false
		list.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		list.wraparound_items = false
		for p in errors + warnings:
			var index := list.add_item(("MUST FIX   " if p.level == "error" else "CHECK      ") + String(p.text))
			list.set_item_metadata(index, p)
			list.set_item_tooltip(index, String(p.text))
			list.set_item_custom_fg_color(index, Color(1.0, 0.55, 0.5) if p.level == "error" else Color(1.0, 0.85, 0.45))
		list.item_activated.connect(func(index: int) -> void:
			dialog.queue_free()
			app.go_to_problem(list.get_item_metadata(index)))
		box.add_child(list)
	if errors.is_empty():
		box.add_child(HSeparator.new())
		box.add_child(_label("Export to", false, 15))
		var folder_name := EditorDoc.slug(String(doc.level.meta.get("name", "level")))
		if AppSettings.has_game():
			var row := HBoxContainer.new()
			var area := LineEdit.new()
			area.text = String(doc.level.meta.get("area", ""))
			area.placeholder_text = "area, e.g. forest_1"
			area.custom_minimum_size.x = 200
			area.tooltip_text = "The game keeps one folder of levels per area and picks one level from it each session."
			row.add_child(area)
			var into_game := Button.new()
			into_game.text = "Export into the game"
			into_game.pressed.connect(func() -> void:
				var area_id := EditorDoc.slug(area.text) if area.text.strip_edges() != "" else ""
				if area_id == "":
					app.toast("Type the area this level belongs to (for example forest_1).")
					return
				doc.level.meta.area = area_id
				doc.commit()
				_finish_export(dialog, Exporter.to_folder(doc.level, AppSettings.game_dir().path_join("levels").path_join(area_id).path_join(folder_name)),
					"It's in the game's levels/%s folder. The game can pick it the next time a session reaches that area." % area_id))
			row.add_child(into_game)
			box.add_child(row)
			var areas := Catalog.game_areas()
			if not areas.is_empty():
				box.add_child(_label("Areas in the game: " + ", ".join(areas), true))
		else:
			box.add_child(_label("Set the game folder in Settings to export straight into the game.", true))
		var row2 := HBoxContainer.new()
		var to_folder := Button.new()
		to_folder.text = "Export to a folder..."
		to_folder.pressed.connect(func() -> void:
			pick_file(FileDialog.FILE_MODE_OPEN_DIR, "Choose where to put the level's folder", PackedStringArray(), func(path: String) -> void:
				_finish_export(dialog, Exporter.to_folder(doc.level, path.path_join(folder_name)), "It's in %s." % path.path_join(folder_name))))
		row2.add_child(to_folder)
		var to_zip := Button.new()
		to_zip.text = "Export as a zip to share..."
		to_zip.pressed.connect(func() -> void:
			pick_file(FileDialog.FILE_MODE_SAVE_FILE, "Save the level as a zip", PackedStringArray(["*.zip ; Zip files"]), func(path: String) -> void:
				if not path.to_lower().ends_with(".zip"):
					path += ".zip"
				_finish_export(dialog, Exporter.to_zip(doc.level, path, folder_name), "It's saved as %s." % path)))
		row2.add_child(to_zip)
		box.add_child(row2)
	dialog.confirmed.connect(dialog.queue_free)
	_show(dialog, Vector2i(740, 0))


func _finish_export(dialog: Window, problem: String, where: String) -> void:
	if is_instance_valid(dialog):
		dialog.queue_free()
	if problem != "":
		tell("The export didn't work", problem)
	else:
		tell("Exported", "The level was exported. " + where)
