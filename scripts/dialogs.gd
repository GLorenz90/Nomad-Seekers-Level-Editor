class_name Dialogs
extends Node
## The editor's pop-up windows: welcome, new level, level settings, editor
## settings, imported models, the trigger editor, export, and the small
## "are you sure" questions.

const LICENSES := [["", "Choose a license..."], ["CC0", "CC0 (public domain)"], ["CC-BY", "CC-BY (credit the author)"],
	["CC-BY-SA", "CC-BY-SA (credit, share alike)"], ["Own work", "I made it myself"], ["Other", "Other (I have permission)"]]

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
		_open.queue_free()
	_open = dialog
	dialog.min_size = min_size
	app.add_child(dialog)
	dialog.popup_centered()
	dialog.close_requested.connect(dialog.queue_free)
	if dialog is AcceptDialog:
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


static func _row(box: Container, text: String, editor: Control, tip := "") -> void:
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
	app.add_child(fd)
	fd.popup_centered_ratio(0.6)


# --- Welcome ----------------------------------------------------------------------------------

func welcome() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Nomad's Seekers Level Editor"
	dialog.ok_button_text = "Close"
	var box := _vbox(dialog)
	box.add_child(_label("Build a level", false, 22))
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
	box.add_child(buttons)
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
	var size := _size_options("small")
	_row(box, "Size", size, "How long a run is. Only rooms count; corridors don't. You can change it later.")
	var area := LineEdit.new()
	area.placeholder_text = "forest_1 (optional)"
	_row(box, "Area", area, "The area this level belongs to, like forest_1 or forest_boss. The game picks one level per area each session. You can leave it empty for now.")
	var areas := Catalog.game_areas()
	if not areas.is_empty():
		box.add_child(_label("Areas in the game: " + ", ".join(areas), true))
	var light := _options([["day", "Day"], ["dusk", "Dusk"], ["overcast", "Overcast"], ["night", "Night"], ["cave", "Cave"], ["interior", "Indoors"]], "day")
	_row(box, "Lighting", light)
	var starter := CheckBox.new()
	starter.text = "Start me off with a first room"
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
		var doc := EditorDoc.create(level_name, String(size.get_selected_metadata()), EditorDoc.slug(area.text) if area.text.strip_edges() != "" else "", dir)
		doc.level.map.lighting.preset = light.get_selected_metadata()
		if starter.button_pressed:
			doc.add("room", {"kind": "room", "name": "Start", "pos": [0, 0, 0], "size": [16, 6, 16], "auto_build": true})
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
	var size := _size_options(String(meta.get("size", "small")))
	size.item_selected.connect(func(index: int) -> void: set_meta.call("size", size.get_item_metadata(index)))
	_row(box, "Size", size, "Only rooms count toward the size; corridors don't.")
	var about := TextEdit.new()
	about.text = String(meta.get("description", ""))
	about.custom_minimum_size.y = 70
	about.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	about.text_changed.connect(func() -> void: set_meta.call("description", about.text))
	_row(box, "Description", about)
	box.add_child(HSeparator.new())
	box.add_child(_label("Lighting", false, 17))
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
		box.add_child(_label(spec[1], false, 16))
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

func import_model() -> void:
	pick_file(FileDialog.FILE_MODE_OPEN_FILE, "Import a model (glTF)", PackedStringArray(["*.glb,*.gltf ; glTF models"]),
		func(path: String) -> void: _import_details(path))


func _import_details(path: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Import " + path.get_file()
	dialog.ok_button_text = "Import"
	var box := _vbox(dialog)
	box.add_child(_label("Levels can be shared, so every imported model needs a license you're allowed to share it under.", true))
	var license := _options(LICENSES, "")
	_row(box, "License", license)
	var author := LineEdit.new()
	author.placeholder_text = "Who made it (for credit)"
	_row(box, "Author", author)
	dialog.get_ok_button().disabled = true
	license.item_selected.connect(func(index: int) -> void: dialog.get_ok_button().disabled = String(license.get_item_metadata(index)) == "")
	dialog.confirmed.connect(func() -> void:
		var problem := import_file(path, String(license.get_selected_metadata()), author.text.strip_edges())
		dialog.queue_free()
		if problem != "":
			tell("Couldn't import the model", problem))
	_show(dialog)


## Copies a model into the level's assets folder and lists it. Returns ""
## or what went wrong.
func import_file(path: String, license: String, author: String) -> String:
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
	doc.level.map.assets.append({"id": id, "file": "assets/" + id + "." + ext, "license": license, "author": author})
	doc.commit()
	app.toast("Imported \"%s\". It's in the Map layer's palette under Imported models." % id)
	return ""


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
		var license := _options(LICENSES, String(a.get("license", "")))
		license.item_selected.connect(func(index: int) -> void:
			a.license = license.get_item_metadata(index)
			doc.commit())
		row.add_child(license)
		var author := LineEdit.new()
		author.text = String(a.get("author", ""))
		author.placeholder_text = "Author"
		author.custom_minimum_size.x = 150
		author.text_changed.connect(func(text: String) -> void:
			a.author = text
			doc.commit("asset:author"))
		row.add_child(author)
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
	var add := Button.new()
	add.text = "Import a model..."
	add.pressed.connect(func() -> void:
		dialog.queue_free()
		import_model())
	box.add_child(add)
	dialog.confirmed.connect(dialog.queue_free)
	_show(dialog, Vector2i(760, 0))


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
	_rule_text = _label("", false, 17)
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
	_rule_box.add_child(_label("WHEN", false, 16))
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
	_rule_box.add_child(_label("ONLY IF (optional)", false, 16))
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
	_rule_box.add_child(_label("DO (in this order)", false, 16))
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
		"set_flag":
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
		"give_item":
			var item := _options([["oro", "Oro"], ["hp_gel", "HP Gel"], ["lp_cell", "LP Cell"], ["cure_salt", "Cure Salt"],
				["trap_scanner", "Trap Scanner"], ["lumidium", "Lumidium"]], String(a.get("item", "oro")))
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
				color.item_selected.connect(func(index: int) -> void: a.color = color.get_item_metadata(index))
				row.add_child(color)
			var amount := SpinBox.new()
			amount.min_value = 1
			amount.max_value = 99999
			amount.value = float(a.get("amount", 1))
			amount.value_changed.connect(func(v: float) -> void:
				a.amount = int(v)
				touch.call())
			row.add_child(amount)
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


func _condition_row(checks: Array, i: int, touch: Callable) -> Control:
	var c: Dictionary = checks[i]
	var row := HBoxContainer.new()
	var pick := _options([["flag", "A flag is"], ["party_at_least", "The party has at least"],
		["difficulty_at_least", "The difficulty is at least"], ["quest_active", "This quest is active"]], String(c.get("check", "flag")))
	pick.item_selected.connect(func(index: int) -> void:
		var check := String(pick.get_item_metadata(index))
		checks[i] = {"check": check}
		match check:
			"flag":
				checks[i].merge({"flag": "", "is": true})
			"party_at_least":
				checks[i].value = 2
			"difficulty_at_least":
				checks[i].value = "hard"
			"quest_active":
				checks[i].value = ""
		_fill_rule())
	row.add_child(pick)
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
		box.add_child(_label("Export to", false, 17))
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
