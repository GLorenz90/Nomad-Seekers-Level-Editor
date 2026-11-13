class_name Inspector
extends ScrollContainer
## The right-hand panel: everything about the selected item, in plain
## words, with its problems at the top and its triggers at the bottom.
## Fields come from Catalog.fields; the extra sections (what opens a door,
## an enemy's wave, a platform's stops...) are built here.

var app: Node
var _box: VBoxContainer
var _problems: VBoxContainer
var _own_change := false
var _shown := ""
var _shown_layer := 0


func _init() -> void:
	custom_minimum_size.x = 340
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	add_child(_box)


## The level changed. Skips the redraw when the change came from a field
## here (so typing and sliders keep their focus), unless asked to.
func on_changed() -> void:
	if _own_change and _shown == app.doc.selected:
		_fill_problems()
		return
	rebuild()


func rebuild() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	_problems = null
	var doc: EditorDoc = app.doc
	if doc == null:
		return
	_shown = doc.selected
	_shown_layer = app.layer
	var it := doc.item(doc.selected)
	if it.is_empty():
		_nothing_selected()
		return
	var kind: String = it.kind
	var d: Dictionary = it.data
	_title(Catalog.type_name(kind, d))
	_problems = VBoxContainer.new()
	_box.add_child(_problems)
	_fill_problems()
	if kind != "start":
		var id_edit := LineEdit.new()
		id_edit.text = it.id
		id_edit.tooltip_text = "This item's id. Triggers and other items refer to it by this, so a clear id (\"gate\", \"boss_door\") makes wiring easier."
		var apply := func(text: String) -> void:
			if text == doc.selected:
				return
			var problem := doc.rename(doc.selected, text)
			if problem != "":
				app.toast(problem)
				id_edit.text = doc.selected
			else:
				doc.commit()
		id_edit.text_submitted.connect(apply)
		id_edit.focus_exited.connect(func() -> void: apply.call(id_edit.text))
		_row("Id", id_edit)
	for f in Catalog.fields(kind, d, doc.level):
		_field(d, f, it.id)
	match kind:
		"area":
			_area_section(it.id, d)
			_fight_section(it.id)
		"enemy":
			_wave_section(it.id, d)
		"object":
			match String(d.get("type", "")):
				"door":
					_door_section(it.id, d)
				"button":
					_group_section(it.id)
				"hazard":
					_zones_section(it.id, d)
				"platform":
					_stops_section(it.id, d)
	if kind in ["object", "enemy"] or (kind == "area" and not doc.level.combat_room(it.id).is_empty()):
		_trigger_section(it.id, kind, d)
	if kind != "start" and kind != "area":
		_box.add_child(HSeparator.new())
		var buttons := HBoxContainer.new()
		buttons.add_child(_button("Duplicate", "Make a copy next to it (Ctrl+D).", func() -> void: app.duplicate_selected()))
		buttons.add_child(_button("Delete", "Remove it (Delete).", func() -> void: app.delete_selected()))
		buttons.add_child(_button("Show", "Centre the view on it (F).", func() -> void: app.view.focus(doc.selected)))
		_box.add_child(buttons)


func _nothing_selected() -> void:
	var doc: EditorDoc = app.doc
	var level := doc.level
	_title(String(level.meta.get("name", "Untitled")))
	_note(size_summary(level))
	_note(Catalog.LAYER_HELP[app.layer])
	_box.add_child(HSeparator.new())
	match int(app.layer):
		1:
			_note("Pick something on the left, then click in the view to place it. Build floors to walk on and walls around them, from the shapes or your own models.\n\nThe colored navmesh shows where Seekers can walk. Each color is a room. Put a Room boundary across a doorway to split the navmesh into two rooms, then click a room's navmesh (with \"Click picks: Rooms\" on) to name it or make it a corridor.\n\nW move, E rotate, R resize, like Godot. Delete removes.")
		2:
			_note("Place doors, buttons and the rest, then select one to say what it does.\n\nA door needs something to open it. A button needs something to do. The Problems tab lists anything left unfinished.\n\nLines in the view show what triggers what.")
		3:
			_note("Pick an enemy on the left, choose a wave, then click on a room's navmesh.\n\nEnemies in a room fight in waves: when a wave is beaten the next one appears, and when no waves are left, doors set to open on combat end open.\n\nEnemies placed in corridors are there from the start.\n\nClick a room's navmesh to change how its fight starts.")
	_box.add_child(_button("Level settings...", "Name, area and lighting.", func() -> void: app.dialogs.level_settings()))


## "Small level: 6 rooms, 2 corridors" (the size follows the room count).
static func size_summary(level: LevelData) -> String:
	var rooms := level.room_count()
	var text := "%d room%s, %d corridor%s" % [rooms, "" if rooms == 1 else "s", level.corridor_count(),
		"" if level.corridor_count() == 1 else "s"]
	if level.size() == "":
		return text + ". That's no size yet: an Arena is 1 room, a Small level 5-9, Medium 10-14, Large 15-19, Huge 20-25."
	return "%s level: %s." % [level.size_name(), text]


## A room or corridor: what it is, and joining it with a neighbour.
func _area_section(id: String, d: Dictionary) -> void:
	var doc: EditorDoc = app.doc
	_note("This is a piece of the navmesh. To split it, put a Room boundary across it. To make two pieces one room (a room split by a pit, say), join them.")
	var others := [["", "Join another room into this one..."]]
	for a in doc.level.map.areas:
		if String(a.id) != id:
			others.append([String(a.id), Catalog.label("area", a, String(a.id))])
	if others.size() > 1:
		_box.add_child(_options(others, "", func(other: Variant) -> void:
			if String(other) == "":
				return
			doc.join_areas(id, String(other))
			doc.commit()
			app.toast("Joined. Its navmesh now counts as part of %s." % id)))
	if not (d.get("also", []) as Array).is_empty():
		_box.add_child(_button("Split off the joined pieces", "They become rooms of their own again.", func() -> void:
			doc.split_area(id)
			doc.commit()))


func _fill_problems() -> void:
	if _problems == null:
		return
	for child in _problems.get_children():
		_problems.remove_child(child)
		child.queue_free()
	for p in LevelCheck.for_id(app.problems, app.doc.selected):
		var label := Label.new()
		label.text = ("Must fix: " if p.level == "error" else "Check: ") + String(p.text)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45) if p.level == "error" else Color(1.0, 0.85, 0.4))
		_problems.add_child(label)


# --- Building blocks --------------------------------------------------------------------------

func _title(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	_box.add_child(label)


func _section(text: String) -> void:
	_box.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	_box.add_child(label)


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	_box.add_child(label)
	return label


func _row(text: String, editor: Control, tip := "") -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 150
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.tooltip_text = tip
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(label)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if tip != "" and editor.tooltip_text == "":
		editor.tooltip_text = tip
	row.add_child(editor)
	_box.add_child(row)


func _button(text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(on_press)
	return b


## Saves a change made here without redrawing the panel.
func _commit(key: String, redraw := false) -> void:
	_own_change = not redraw
	app.doc.commit("inspector:" + key)
	_own_change = false


static func get_path_value(d: Dictionary, key: String, fallback: Variant) -> Variant:
	var at: Variant = d
	for part in key.split("."):
		if not (at is Dictionary) or not (at as Dictionary).has(part):
			return fallback
		at = at[part]
	return at


static func set_path_value(d: Dictionary, key: String, value: Variant) -> void:
	var parts := key.split(".")
	var at := d
	for i in parts.size() - 1:
		if not (at.get(parts[i]) is Dictionary):
			at[parts[i]] = {}
		at = at[parts[i]]
	at[parts[parts.size() - 1]] = value


func _spin(value: float, lo: float, hi: float, step: float, on_change: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.custom_arrow_step = step
	spin.allow_greater = hi >= 9999.0
	spin.allow_lesser = lo <= -9999.0
	spin.set_value_no_signal(value)
	spin.value_changed.connect(on_change)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


## Three number boxes for [x, y, z]. `on_change` gets the new Vector3.
func _vec3(value: Vector3, f: Dictionary, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var spins: Array[SpinBox] = []
	for axis in 3:
		var step := float(f.get("ystep", f.get("step", 0.5))) if axis == 1 else float(f.get("step", 0.5))
		var lo := float(f.get("ymin", f.get("min", -10000))) if axis == 1 else float(f.get("min", -10000))
		var spin := _spin(value[axis], lo, 10000.0, 0.01, func(_v: float) -> void:
			on_change.call(Vector3(spins[0].value, spins[1].value, spins[2].value)))
		spin.custom_arrow_step = step
		spin.tooltip_text = ["Left / right (X)", "Up / down (Y)", "Forward / back (Z)"][axis]
		spins.append(spin)
		row.add_child(spin)
	return row


func _options(options: Array, current: Variant, on_pick: Callable) -> OptionButton:
	var ob := OptionButton.new()
	ob.fit_to_longest_item = false
	ob.clip_text = true
	for i in options.size():
		ob.add_item(String(options[i][1]))
		ob.set_item_metadata(i, options[i][0])
		if options[i][0] == current:
			ob.select(i)
	ob.item_selected.connect(func(index: int) -> void: on_pick.call(ob.get_item_metadata(index)))
	return ob


## One field from Catalog.fields, editing dictionary `d`.
func _field(d: Dictionary, f: Dictionary, id: String) -> void:
	var key: String = f.k
	var tip := String(f.get("tip", ""))
	var redraw := bool(f.get("rebuild", false))
	var value: Variant = get_path_value(d, key, f.get("def"))
	var save := func(v: Variant) -> void:
		if bool(f.get("unset_empty", false)) and v is String and v == "":
			d.erase(key)
		else:
			set_path_value(d, key, v)
		if key == "pos" and app.doc.kind_of(id) == "enemy":
			app.doc.settle_enemy(id)
		_commit(id + ":" + key, redraw)
	match String(f.t):
		"text":
			var edit := LineEdit.new()
			edit.text = String(value) if value != null else ""
			edit.text_changed.connect(save)
			_row(f.l, edit, tip)
		"float", "int":
			var is_int: bool = f.t == "int"
			var spin := _spin(float(value) if value != null else 0.0, float(f.get("min", -10000)), float(f.get("max", 10000)),
				1.0 if is_int else 0.01, func(v: float) -> void: save.call(int(v) if is_int else v))
			spin.custom_arrow_step = float(f.get("step", 1.0))
			_row(f.l, spin, tip)
		"bool":
			var check := CheckBox.new()
			check.text = f.l
			check.tooltip_text = tip
			check.button_pressed = bool(value) if value != null else false
			check.toggled.connect(save)
			_box.add_child(check)
		"enum":
			_row(f.l, _options(f.o, value, save), tip)
		"vec3":
			var label := Label.new()
			label.text = f.l
			label.tooltip_text = tip
			label.mouse_filter = Control.MOUSE_FILTER_STOP
			_box.add_child(label)
			_box.add_child(_vec3(LevelData.vec3(value), f, func(v: Vector3) -> void: save.call(LevelData.arr3(v))))
		"vec2":
			var dims: Array = value if value is Array else [4, 4]
			var row := HBoxContainer.new()
			var spins: Array[SpinBox] = []
			for axis in 2:
				var spin := _spin(float(dims[axis]) if dims.size() > axis else 4.0, float(f.get("min", 0.1)), 10000.0, 0.01,
					func(_v: float) -> void: save.call([spins[0].value, spins[1].value]))
				spin.custom_arrow_step = float(f.get("step", 0.5))
				spin.tooltip_text = ["Wide", "Tall"][axis]
				spins.append(spin)
				row.add_child(spin)
			_row(f.l, row, tip)
		"scale":
			var s := LevelData.vec3(value, Vector3.ONE).x
			_row(f.l, _spin(s, float(f.min), float(f.max), 0.01, func(v: float) -> void: save.call([v, v, v])), tip)
		"color":
			var picker := ColorPickerButton.new()
			picker.edit_alpha = false
			picker.custom_minimum_size.y = 28
			picker.color = ItemVisuals._color(value, Color.WHITE)
			picker.color_changed.connect(func(c: Color) -> void: save.call([snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001)]))
			_row(f.l, picker, tip)
		"dest":
			_destination(d, key, f, save)


## Where a teleporter goes: Nomad-2, nowhere, an area, or typed by hand.
func _destination(d: Dictionary, key: String, f: Dictionary, save: Callable) -> void:
	var current := String(d.get(key, ""))
	var options := [["hub", "Nomad-2 (the ship)"], ["", "Nowhere"]]
	var areas := Catalog.game_areas()
	var own_area := String(app.doc.level.meta.get("area", ""))
	for area in areas:
		options.append(["area:" + area, "Area: %s" % area])
	var known := false
	for o in options:
		known = known or o[0] == current
	options.append(["?", "Somewhere else (type it)"])
	var edit := LineEdit.new()
	edit.text = current
	edit.placeholder_text = "area:forest_2"
	edit.tooltip_text = "\"area:forest_2\" sends Seekers to whichever Forest 2 level the game picked this session. \"hub\" is Nomad-2."
	edit.visible = not known
	edit.text_changed.connect(save)
	_row(f.l, _options(options, current if known else "?", func(v: Variant) -> void:
		edit.visible = v == "?"
		if v != "?":
			edit.text = String(v)
			save.call(v)), String(f.get("tip", "")))
	_box.add_child(edit)
	if own_area != "" and areas.is_empty():
		_note("Tip: set the game folder in Settings to list its areas here.")


# --- Sections ---------------------------------------------------------------------------------

func _fight_section(room: String) -> void:
	var doc: EditorDoc = app.doc
	var c := doc.level.combat_room(room)
	_section("Fight in this room")
	if c.is_empty():
		_note("No fight here. On the Combat layer, place enemies inside this room to give it waves.")
		return
	var enemies := 0
	for w in c.waves:
		enemies += (w.get("enemies", []) as Array).size()
	_note("%d wave(s), %d enemies. Each wave appears when the one before is beaten." % [(c.waves as Array).size(), enemies])
	_field(c, {"k": "start", "l": "The fight starts", "t": "enum", "def": "enter",
		"o": [["enter", "When a Seeker walks in"], ["event", "When a trigger starts it"]],
		"tip": "\"When a trigger starts it\": add a trigger with the action \"Start a room's fight\" (after a button, a dialogue, anything)."}, room)
	_field(c, {"k": "start_delay", "l": "Delay before wave 1 (s)", "t": "float", "min": 0, "max": 10, "step": 0.1, "def": 0.8}, room)
	_field(c, {"k": "wave_delay", "l": "Delay between waves (s)", "t": "float", "min": 0, "max": 10, "step": 0.1, "def": 1.0}, room)
	_box.add_child(_button("Add a wave", "Adds an empty wave to this room. Then place enemies into it.", func() -> void:
		app.set_place_wave(doc.add_wave(room) + 1)
		doc.commit()))


func _wave_section(id: String, d: Dictionary) -> void:
	var doc: EditorDoc = app.doc
	_section("Wave")
	var slot := doc.enemy_slot(id)
	var here := doc.room_at(LevelData.vec3(d.get("pos")), true)
	if here == "":
		_note("It isn't inside a room, so it's there from the start and isn't part of a wave. Move it into a room to give it a wave.")
		return
	var c := doc.level.combat_room(here)
	var count: int = (c.get("waves", []) as Array).size()
	var options := [[-1, "Not in a wave (there from the start)"]]
	for w in count:
		options.append([w, "Wave %d of %s" % [w + 1, doc.label_of(here)]])
	options.append([count, "A new wave"])
	var current: int = int(slot.get("wave", -1)) if String(slot.get("room", "")) == here else -1
	_row("Appears in", _options(options, current, func(v: Variant) -> void:
		if int(v) < 0:
			d.loose = true
			doc.set_enemy_slot(id, "", 0)
		else:
			d.erase("loose")
			doc.set_enemy_slot(id, here, int(v))
		_commit(id + ":wave", true)), "Which of the room's waves this enemy belongs to.")


func _door_section(id: String, d: Dictionary) -> void:
	var doc: EditorDoc = app.doc
	_section("What opens this door?")
	var fights := [["", "(not used)"]]
	for c in doc.level.combat.rooms:
		fights.append([String(c.room), doc.label_of(String(c.room))])
	for spec in [["open_when_cleared", "Opens when this fight is won", "The door opens when every wave in that room has been beaten."],
			["shut_during_combat", "Shut while this room fights", "The door closes when that room's fight starts and opens again when it's won (to hold Seekers in)."]]:
		var key: String = spec[0]
		_row(spec[1], _options(fights, String(d.get(key, "")), func(v: Variant) -> void:
			if String(v) == "":
				d.erase(key)
			else:
				d[key] = v
			_commit(id + ":" + key)), spec[2])
	if fights.size() == 1:
		_note("No room has a fight yet. Place enemies in a room (Combat layer) to use these.")
	var sources := [["", "Choose a button..."]]
	sources.append_array(Wiring.candidates("button", doc))
	if sources.size() > 1:
		_row("Open with a button", _options(sources, "", func(v: Variant) -> void:
			if String(v) != "":
				doc.put_rule({"id": doc.new_rule_id(), "when": {"event": "pressed", "source": v},
					"do": [{"action": "open", "target": id}], "once": true})
				_commit(id + ":button", true)), "Adds a trigger: when that button (or plate group) is pressed, open this door.")
	else:
		_note("To open it with a button, place a Button or Floor plate first.")
	var check := CheckBox.new()
	check.text = "Stays locked on purpose (decoration)"
	check.tooltip_text = "Tick this for a door that's never meant to open, so the level check doesn't flag it."
	check.button_pressed = bool(d.get("decorative", false))
	check.toggled.connect(func(on: bool) -> void:
		if on:
			d.decorative = true
		else:
			d.erase("decorative")
		_commit(id + ":decorative"))
	_box.add_child(check)


func _group_section(id: String) -> void:
	var doc: EditorDoc = app.doc
	_section("Pressed together with")
	var g := doc.group_of(id)
	var options := [["", "Nothing: it works on its own"]]
	for other in doc.level.interaction.button_groups:
		options.append([String(other.id), "%s: %d button(s)" % [other.id, (other.buttons as Array).size()]])
	options.append(["+", "A new group"])
	_row("Group", _options(options, String(g.get("id", "")), func(v: Variant) -> void:
		doc.set_group(id, String(v))
		_commit(id + ":group", true)),
		"Buttons in a group must all be down at once. With fewer Seekers than floor plates, the extra plates stay down by themselves.")
	if not g.is_empty():
		_field(g, {"k": "once", "l": "The group fires only once", "t": "bool", "def": true}, id)


func _zones_section(id: String, d: Dictionary) -> void:
	var doc: EditorDoc = app.doc
	_section("Areas it covers")
	var zones: Array = d.get("zones", [])
	for i in zones.size():
		var z: Dictionary = zones[i]
		var head := HBoxContainer.new()
		var label := Label.new()
		label.text = "Area %d" % (i + 1)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(label)
		head.add_child(_button("Remove", "", func() -> void:
			zones.remove_at(i)
			_commit(id + ":zones", true)))
		_box.add_child(head)
		_field(z, {"k": "pos", "l": "Middle of its floor", "t": "vec3", "step": 1}, id)
		_field(z, {"k": "size", "l": "Size (wide, tall, deep)", "t": "vec3", "step": 1, "min": 1}, id)
	var rooms := [["", "Cover a room or corridor..."]]
	for r in doc.level.map.areas:
		rooms.append([String(r.id), doc.label_of(String(r.id))])
	_row("Add an area", _options(rooms, "", func(v: Variant) -> void:
		var room := doc.level.find_area(String(v))
		if not room.is_empty():
			if not d.has("zones"):
				d.zones = []
			# A box around the room's navmesh.
			var box := Items.local_aabb("area", room, doc.level)
			box.position += Items.get_pos("area", room)
			var bottom := Vector3(box.get_center().x, box.position.y - 0.5, box.get_center().z)
			d.zones.append({"pos": LevelData.arr3(bottom.snapped(Vector3(0.5, 0.5, 0.5))),
				"size": [snappedf(box.size.x, 0.5), 4.0, snappedf(box.size.z, 0.5)]})
			_commit(id + ":zones", true)), "One hazard can cover several rooms, or a room and its corridor.")


func _stops_section(id: String, d: Dictionary) -> void:
	_section("Stops")
	_note("The platform starts on stop 1. Each stop is where the top of the platform will be.")
	var pts: Array = d.get("points", [])
	for i in pts.size():
		var head := HBoxContainer.new()
		var label := Label.new()
		label.text = "Stop %d" % (i + 1)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(label)
		if pts.size() > 2:
			head.add_child(_button("Remove", "", func() -> void:
				pts.remove_at(i)
				_commit(id + ":stops", true)))
		_box.add_child(head)
		_box.add_child(_vec3(LevelData.vec3(pts[i]), {"step": 0.5}, func(v: Vector3) -> void:
			pts[i] = LevelData.arr3(v)
			_commit(id + ":stop%d" % i)))
	_box.add_child(_button("Add a stop", "Adds a stop 4 m past the last one. Then set where it is.", func() -> void:
		var last := LevelData.vec3(pts[pts.size() - 1]) if not pts.is_empty() else Vector3.ZERO
		pts.append(LevelData.arr3(last + Vector3(0, 0, -4)))
		d.points = pts
		_commit(id + ":stops", true)))


func _trigger_section(id: String, kind: String, d: Dictionary) -> void:
	var doc: EditorDoc = app.doc
	var about := doc.rules_about(id)
	_section("Triggers")
	if (about.from as Array).is_empty() and (about.onto as Array).is_empty():
		_note("Nothing yet. A trigger says \"when this happens, do that\".")
	for pair in [["from", "This sets off:"], ["onto", "This is acted on by:"]]:
		var list: Array = about[pair[0]]
		if list.is_empty():
			continue
		_note(pair[1])
		for rule in list:
			var row := HBoxContainer.new()
			var text := Label.new()
			text.text = Wiring.describe(rule, doc)
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(text)
			var rid := String(rule.id)
			row.add_child(_button("Edit", "", func() -> void: app.dialogs.edit_rule(doc.find_rule(rid))))
			row.add_child(_button("X", "Delete this trigger.", func() -> void:
				doc.remove_rule(rid)
				_commit(id + ":rule", true)))
			_box.add_child(row)
	var events := Wiring.events_for(kind, d, doc)
	if not events.is_empty():
		var source := doc.press_source(id) if String(d.get("type", "")) == "button" else id
		var event := events[0]
		if event == "entered" and bool(d.get("whole_party", false)):
			event = "party_present"
		_box.add_child(_button("Add a trigger: when this...", "Choose what happens when this is %s." % (
			"pressed" if event == "pressed" else "set off"), func() -> void:
			app.dialogs.edit_rule({"id": "", "when": {"event": event, "source": source}, "do": [], "once": true})))
	else:
		_box.add_child(_button("Add a trigger that acts on this...", "Open the trigger editor.", func() -> void:
			var action := "toggle"
			for row in Wiring.ACTIONS:
				if String(row[2]).split(",").has(String(d.get("type", ""))):
					action = row[0]
					break
			app.dialogs.edit_rule({"id": "", "when": {"event": "", "source": ""},
				"do": [{"action": action, "target": id}], "once": true})))
