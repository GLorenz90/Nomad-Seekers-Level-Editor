class_name QuestDialogs
extends Node
## Quest windows (Grayson 2026-11-13: quests are sessions that change which
## maps are open, and place people around Nomad-2): New quest, Open quest,
## Quest details (briefing, reward, steps, areas), the quest's levels, and
## Check and export quest. A quest is a folder (QuestDoc); its Nomad-2
## additions and its own levels are edited like any level.

var app: Node
var dialogs: Dialogs
## The Quest details window's contents (rebuilt as steps and areas change).
var _box: VBoxContainer
var _data := {}


func _quest() -> QuestDoc:
	return app.doc.quest if app.doc else null


## Where new quests go: <library>/quests/<name>.
static func quests_dir() -> String:
	return AppSettings.library_dir().path_join("quests")


# --- New and open -----------------------------------------------------------------------------

func new_quest() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "New quest"
	dialog.ok_button_text = "Create"
	var box := dialogs._vbox(dialog)
	box.add_child(dialogs._label("A quest is its own session, like PSO's: accepting it at the Guild reloads Nomad-2 with the people you place, and the teleporter goes only to the quest's areas. Its steps are done in order.", true))
	var title := LineEdit.new()
	title.placeholder_text = "The Foreman's Favour"
	Dialogs._row(box, "Title", title)
	var client := LineEdit.new()
	client.placeholder_text = "Petram Solidus, foreman"
	Dialogs._row(box, "Client", client, "Who's asking, shown at the Guild counter.")
	box.add_child(dialogs._label("It's saved in: " + quests_dir(), true))
	dialog.confirmed.connect(func() -> void:
		var name := title.text.strip_edges() if title.text.strip_edges() != "" else "New quest"
		var dir := quests_dir().path_join(EditorDoc.slug(name))
		var n := 2
		while DirAccess.dir_exists_absolute(dir):
			dir = quests_dir().path_join("%s_%d" % [EditorDoc.slug(name), n])
			n += 1
		var problem := create_quest(dir, name, client.text.strip_edges())
		dialog.queue_free()
		if problem != "":
			dialogs.tell("Couldn't create the quest", problem)
			return
		open_quest_dir(dir)
		quest_details.call_deferred())
	dialogs._show(dialog)
	title.grab_focus.call_deferred()


## Makes a quest folder: quest.json and an empty Nomad-2 overlay. "" or why not.
static func create_quest(dir: String, title: String, client := "") -> String:
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		return "The folder %s couldn't be made (%s). Choose another library folder in Settings." % [dir, error_string(err)]
	var q := QuestDoc.create(dir, title)
	q.data.client = client
	if q.save() != OK:
		return "quest.json couldn't be written in %s." % dir
	var overlay := EditorDoc.create(title + ": Nomad-2", "", q.nomad2_dir(), "nomad2")
	overlay.level.meta.author = String(AppSettings.get_value("author", ""))
	if overlay.save() != OK:
		return "The quest's Nomad-2 folder couldn't be written."
	return ""


func open_quest() -> void:
	dialogs.pick_file(FileDialog.FILE_MODE_OPEN_DIR, "Open a quest folder", PackedStringArray(),
		func(path: String) -> void: open_quest_dir(path), quests_dir())


## Opens a quest at its Nomad-2 additions (made if missing).
func open_quest_dir(dir: String) -> void:
	if dir.get_file() == "quest.json":
		dir = dir.get_base_dir()
	var q := QuestDoc.open(dir)
	if q == null:
		dialogs.tell("That isn't a quest", "There's no quest.json in %s. Choose a quest's own folder." % dir)
		return
	if not LevelData.is_level_dir(q.nomad2_dir()):
		EditorDoc.create(q.title() + ": Nomad-2", "", q.nomad2_dir(), "nomad2").save()
	app.open_path(q.nomad2_dir())


# --- Details ----------------------------------------------------------------------------------

## The quest's briefing, reward, steps and areas.
func quest_details() -> void:
	var q := _quest()
	if q == null:
		dialogs.tell("Not a quest", "This level isn't part of a quest. Use Quest > New quest, or open a quest folder.")
		return
	var data := q.data.duplicate(true)
	var dialog := ConfirmationDialog.new()
	dialog.title = "Quest: " + q.title()
	dialog.ok_button_text = "Save quest"
	var outer := dialogs._vbox(dialog)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_box)
	outer.add_child(scroll)
	_data = data
	_rebuild()
	dialog.confirmed.connect(func() -> void:
		q.data = data
		if String(q.data.get("id", "")) == "":
			q.data.id = EditorDoc.slug(q.title())
		var err := q.save()
		dialog.queue_free()
		if err != OK:
			dialogs.tell("Couldn't save the quest", "quest.json couldn't be written (%s)." % error_string(err))
			return
		app.quest_changed()
		app.toast("Saved the quest."))
	dialogs._show(dialog, Vector2i(860, 0))


func _rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_fill_details(_box, _data, _rebuild)


func _small_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(on_press)
	return b


func _fill_details(box: VBoxContainer, data: Dictionary, rebuild: Callable) -> void:
	var q := _quest()
	for spec in [["title", "Title", ""], ["client", "Client", "Who's asking, shown at the Guild counter."],
			["place", "Where (in words)", "Optional: \"The Forest\". The areas below are named on the teleporter either way."]]:
		var edit := LineEdit.new()
		edit.text = String(data.get(spec[0], ""))
		var key: String = spec[0]
		edit.text_changed.connect(func(t: String) -> void: data[key] = t)
		Dialogs._row(box, spec[1], edit, spec[2])
	var text := TextEdit.new()
	text.text = String(data.get("text", ""))
	text.custom_minimum_size = Vector2(0, 80)
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.placeholder_text = "The briefing at the Guild counter."
	text.text_changed.connect(func() -> void: data.text = text.text)
	Dialogs._row(box, "Briefing", text)
	var reward := SpinBox.new()
	reward.max_value = 999999
	reward.step = 10
	reward.suffix = "Oro"
	reward.value = float(data.get("reward", 0))
	reward.value_changed.connect(func(v: float) -> void: data.reward = int(v))
	Dialogs._row(box, "Reward", reward, "Every Seeker in the party gets it when the quest is reported.")

	# Steps.
	box.add_child(HSeparator.new())
	box.add_child(dialogs._label("STEPS (done in order)", false, 14))
	box.add_child(dialogs._label("\"Done by a trigger\" steps are completed by a trigger's \"Complete a quest step\": after a talk, a hand-over, reaching a spot. People can change what they say, show up or leave as steps are done.", true))
	var steps: Array = data.get("steps", [])
	data.steps = steps
	var enemies := []
	for e in Catalog.enemies():
		enemies.append([e.id, e.name])
	for i in steps.size():
		var s: Dictionary = steps[i]
		var row := HBoxContainer.new()
		var number := Label.new()
		number.text = "%d." % (i + 1)
		number.custom_minimum_size.x = 24
		row.add_child(number)
		var goal := LineEdit.new()
		goal.text = String(s.get("goal", ""))
		goal.placeholder_text = "What to do, as the Guild says it"
		goal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		goal.text_changed.connect(func(t: String) -> void: s.goal = t)
		row.add_child(goal)
		var type := Dialogs._options(QuestDoc.STEP_TYPES, String(s.get("type", "event")))
		type.custom_minimum_size.x = 210
		type.clip_text = true
		type.item_selected.connect(func(index: int) -> void:
			s.type = type.get_item_metadata(index)
			rebuild.call())
		row.add_child(type)
		match String(s.get("type", "event")):
			"defeat":
				var who := Dialogs._options(enemies if not enemies.is_empty() else [["", "(no enemies)"]], String(s.get("enemy", "")))
				who.item_selected.connect(func(index: int) -> void: s.enemy = who.get_item_metadata(index))
				if String(s.get("enemy", "")) == "" and not enemies.is_empty():
					s.enemy = enemies[0][0]
				row.add_child(who)
				row.add_child(_count(s))
			"bank_lumidium":
				row.add_child(_count(s))
			"clear":
				var where := [["", "Any of its areas"]]
				for a in data.get("areas", []):
					var key := String(a.get("area", "")) if String(a.get("area", "")) != "" else String(a.get("quest_level", ""))
					where.append([key, String(a.get("name", key))])
				var area := Dialogs._options(where, String(s.get("area", "")))
				area.item_selected.connect(func(index: int) -> void: s.area = area.get_item_metadata(index))
				row.add_child(area)
		var id_label := Label.new()
		id_label.text = String(s.get("id", ""))
		id_label.tooltip_text = "The step's id, used by triggers. It stays the same when you change the goal."
		id_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
		row.add_child(id_label)
		if i > 0:
			row.add_child(_small_button("Up", func() -> void:
				steps[i] = steps[i - 1]
				steps[i - 1] = s
				rebuild.call()))
		row.add_child(_small_button("X", func() -> void:
			steps.remove_at(i)
			rebuild.call()))
		box.add_child(row)
	box.add_child(_small_button("Add a step", func() -> void:
		var temp := QuestDoc.new()
		temp.data = data
		steps.append({"id": temp.new_step_id("step %d" % (steps.size() + 1)), "type": "event", "goal": ""})
		rebuild.call()))

	# Areas.
	box.add_child(HSeparator.new())
	box.add_child(dialogs._label("WHERE THE TELEPORTER GOES", false, 14))
	box.add_child(dialogs._label("While the quest is on, Nomad-2's teleporter offers only these. An area from the game gets a fresh pick of its levels each quest, or the level you name. The quest's own levels are only in this quest.", true))
	var areas: Array = data.get("areas", [])
	data.areas = areas
	var game_areas := Catalog.game_areas()
	for i in areas.size():
		var a: Dictionary = areas[i]
		var row := HBoxContainer.new()
		var own := String(a.get("quest_level", "")) != ""
		var name := LineEdit.new()
		name.text = String(a.get("name", ""))
		name.placeholder_text = "Name on the teleporter"
		name.custom_minimum_size.x = 180
		name.text_changed.connect(func(t: String) -> void: a.name = t)
		row.add_child(name)
		if own:
			var levels := []
			for l in q.levels():
				levels.append([l, "This quest's level: " + l])
			if levels.is_empty():
				levels = [[String(a.quest_level), "This quest's level: %s (missing)" % a.quest_level]]
			var pick := Dialogs._options(levels, String(a.quest_level))
			pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pick.item_selected.connect(func(index: int) -> void: a.quest_level = pick.get_item_metadata(index))
			row.add_child(pick)
		else:
			var area := LineEdit.new()
			area.text = String(a.get("area", ""))
			area.placeholder_text = "Area (forest_1)"
			area.custom_minimum_size.x = 140
			area.tooltip_text = "An area folder in the game's levels folder." + ("\nIn the game: " + ", ".join(game_areas) if not game_areas.is_empty() else "")
			area.text_changed.connect(func(t: String) -> void: a.area = EditorDoc.slug(t) if t.strip_edges() != "" else "")
			row.add_child(area)
			var level := LineEdit.new()
			level.text = String(a.get("level", "")).get_file()
			level.placeholder_text = "a fresh pick (or a level's folder name)"
			level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			level.tooltip_text = "Leave empty for a fresh pick from the area each quest, or name one of the area's levels (its folder) to always use it."
			level.text_changed.connect(func(t: String) -> void:
				if t.strip_edges() == "":
					a.erase("level")
				else:
					a.level = "res://levels/%s/%s" % [String(a.get("area", "")), t.strip_edges()])
			row.add_child(level)
		row.add_child(_small_button("X", func() -> void:
			areas.remove_at(i)
			rebuild.call()))
		box.add_child(row)
		box.add_child(_opens_row(a, rebuild))
	var add_row := HBoxContainer.new()
	add_row.add_child(_small_button("Add an area from the game", func() -> void:
		areas.append({"area": game_areas[0] if not game_areas.is_empty() else "", "name": ""})
		rebuild.call()))
	if not q.levels().is_empty():
		add_row.add_child(_small_button("Add one of the quest's levels", func() -> void:
			areas.append({"quest_level": q.levels()[0], "name": q.levels()[0].capitalize()})
			rebuild.call()))
	box.add_child(add_row)

	_endings_section(box, data, rebuild)

	# Offered only if.
	box.add_child(HSeparator.new())
	box.add_child(dialogs._label("OFFERED ONLY IF", false, 14))
	box.add_child(dialogs._label("Story flags the character must have (or not) for the Guild to list this quest, so earlier choices can open or close quests. Leave empty to always offer it.", true))
	var requires: Array = data.get("requires", [])
	data.requires = requires
	for i in requires.size():
		box.add_child(_flag_row(requires[i], false, func() -> void:
			requires.remove_at(i)
			rebuild.call()))
	box.add_child(_small_button("Add a story flag it needs", func() -> void:
		requires.append({"flag": "", "is": true})
		rebuild.call()))

	# What's left to do.
	var temp := QuestDoc.new()
	temp.dir = q.dir
	temp.data = data
	var problems := temp.problems()
	if not problems.is_empty():
		box.add_child(HSeparator.new())
		for p in problems:
			var label := dialogs._label("Must fix: " + p, false)
			label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
			box.add_child(label)


## "Opens: right away / after step N / when a quest flag is on" for an area.
func _opens_row(a: Dictionary, rebuild: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var gap := Control.new()
	gap.custom_minimum_size.x = 24
	row.add_child(gap)
	var label := Label.new()
	label.text = "Opens"
	row.add_child(label)
	var modes := [["", "Right away"]]
	var q := QuestDoc.new()
	q.data = _data
	for st in q.step_options():
		modes.append(["step:" + String(st[0]), "After step " + String(st[1]).replace(". ", ": ")])
	modes.append(["flag", "When a quest flag is on"])
	var mode := "flag" if a.has("opens_with") else ("step:" + String(a.opens_after) if String(a.get("opens_after", "")) != "" else "")
	var pick := Dialogs._options(modes, mode)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.clip_text = true
	pick.tooltip_text = "Nomad-2's teleporter lists this area once it's open, and a banner says so. Use it to send the party through the quest's maps in order."
	pick.item_selected.connect(func(index: int) -> void:
		var v := String(pick.get_item_metadata(index))
		a.erase("opens_after")
		a.erase("opens_with")
		if v.begins_with("step:"):
			a.opens_after = v.trim_prefix("step:")
		elif v == "flag":
			a.opens_with = ""
		rebuild.call())
	row.add_child(pick)
	if a.has("opens_with"):
		var flag := LineEdit.new()
		flag.text = String(a.opens_with)
		flag.placeholder_text = "quest flag (set by a trigger)"
		flag.custom_minimum_size.x = 200
		flag.text_changed.connect(func(t: String) -> void: a.opens_with = t.strip_edges())
		row.add_child(flag)
	return row


## [flag name] [quest flag / story flag] [is on] [X] for a condition.
func _flag_row(c: Dictionary, can_be_quest: bool, on_remove: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var gap := Control.new()
	gap.custom_minimum_size.x = 24
	row.add_child(gap)
	var name := LineEdit.new()
	name.text = String(c.get("flag", ""))
	name.placeholder_text = "flag name"
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text_changed.connect(func(t: String) -> void: c.flag = t.strip_edges())
	row.add_child(name)
	if can_be_quest:
		var kind := Dialogs._options([["quest", "quest flag"], ["story", "story flag"]], "story" if bool(c.get("story", false)) else "quest")
		kind.item_selected.connect(func(index: int) -> void:
			if String(kind.get_item_metadata(index)) == "story":
				c.story = true
			else:
				c.erase("story"))
		row.add_child(kind)
	var on := CheckBox.new()
	on.text = "is on"
	on.tooltip_text = "Untick for \"is off\"."
	on.button_pressed = bool(c.get("is", true))
	on.toggled.connect(func(v: bool) -> void: c["is"] = v)
	row.add_child(on)
	row.add_child(_small_button("X", on_remove))
	return row


## Endings: told at the report, picked by flags; each can have its own
## reward and set story flags.
func _endings_section(box: VBoxContainer, data: Dictionary, rebuild: Callable) -> void:
	box.add_child(HSeparator.new())
	box.add_child(dialogs._label("ENDINGS", false, 14))
	box.add_child(dialogs._label("Told at the Guild when the quest is reported. The first ending whose flags all hold is the one told, so put the one with no conditions last as the default. An ending can pay its own reward and set story flags, which stay with every Seeker in the party for later quests.", true))
	var endings: Array = data.get("endings", [])
	data.endings = endings
	for i in endings.size():
		var e: Dictionary = endings[i]
		var head := HBoxContainer.new()
		var title := Label.new()
		title.text = "Ending %d%s" % [i + 1, "  (the default: no conditions)" if (e.get("if", []) as Array).is_empty() else ""]
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		if i > 0:
			head.add_child(_small_button("Up", func() -> void:
				endings[i] = endings[i - 1]
				endings[i - 1] = e
				rebuild.call()))
		head.add_child(_small_button("X", func() -> void:
			endings.remove_at(i)
			rebuild.call()))
		box.add_child(head)
		var text := TextEdit.new()
		text.text = String(e.get("text", ""))
		text.placeholder_text = "What happened, as the Guild tells it."
		text.custom_minimum_size = Vector2(0, 64)
		text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		text.text_changed.connect(func() -> void: e.text = text.text)
		box.add_child(text)
		var reward_row := HBoxContainer.new()
		var own := CheckBox.new()
		own.text = "Its own reward"
		own.button_pressed = e.has("reward")
		reward_row.add_child(own)
		var reward := SpinBox.new()
		reward.max_value = 999999
		reward.step = 10
		reward.suffix = "Oro"
		reward.value = float(e.get("reward", data.get("reward", 0)))
		reward.custom_minimum_size.x = 150
		reward.editable = e.has("reward")
		reward.value_changed.connect(func(v: float) -> void: e.reward = int(v))
		own.toggled.connect(func(v: bool) -> void:
			if v:
				e.reward = int(reward.value)
			else:
				e.erase("reward")
			reward.editable = v)
		reward_row.add_child(reward)
		box.add_child(reward_row)
		var conds: Array = e.get("if", [])
		e["if"] = conds
		if not conds.is_empty():
			box.add_child(dialogs._label("When:", false))
		for j in conds.size():
			box.add_child(_flag_row(conds[j], true, func() -> void:
				conds.remove_at(j)
				rebuild.call()))
		var sets: Dictionary = e.get("sets", {})
		e.sets = sets
		if not sets.is_empty():
			box.add_child(dialogs._label("Sets story flags:", false))
		for k in sets.keys():
			var key: String = k
			var row := HBoxContainer.new()
			var gap := Control.new()
			gap.custom_minimum_size.x = 24
			row.add_child(gap)
			var name := LineEdit.new()
			name.text = key
			name.placeholder_text = "story flag"
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name.text_submitted.connect(func(t: String) -> void:
				_rename_key(sets, key, t.strip_edges())
				rebuild.call())
			name.focus_exited.connect(func() -> void:
				if name.text.strip_edges() != key:
					_rename_key(sets, key, name.text.strip_edges())
					rebuild.call.call_deferred())
			row.add_child(name)
			var on := CheckBox.new()
			on.text = "on"
			on.button_pressed = bool(sets[key])
			on.toggled.connect(func(v: bool) -> void: sets[key] = v)
			row.add_child(on)
			row.add_child(_small_button("X", func() -> void:
				sets.erase(key)
				rebuild.call()))
			box.add_child(row)
		var adds := HBoxContainer.new()
		adds.add_child(_small_button("Add a condition", func() -> void:
			conds.append({"flag": "", "is": true})
			rebuild.call()))
		adds.add_child(_small_button("Add a story flag it sets", func() -> void:
			var n := 1
			while sets.has("story_flag_%d" % n):
				n += 1
			sets["story_flag_%d" % n] = true
			rebuild.call()))
		box.add_child(adds)
	box.add_child(_small_button("Add an ending", func() -> void:
		endings.append({"text": "", "if": []})
		rebuild.call()))


## Renames a dictionary key in place, keeping its value ("" removes it).
static func _rename_key(d: Dictionary, old: String, new: String) -> void:
	if old == new or not d.has(old):
		return
	var value: Variant = d[old]
	d.erase(old)
	if new != "" and not d.has(new):
		d[new] = value


func _count(s: Dictionary) -> SpinBox:
	var count := SpinBox.new()
	count.min_value = 1
	count.max_value = 9999
	count.value = float(s.get("count", 1))
	count.prefix = "x"
	count.value_changed.connect(func(v: float) -> void: s.count = int(v))
	return count


# --- The quest's levels -----------------------------------------------------------------------

## Its Nomad-2 and its own levels, to open; or make a new level.
func quest_levels() -> void:
	var q := _quest()
	if q == null:
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Quest: " + q.title()
	dialog.ok_button_text = "Close"
	var box := dialogs._vbox(dialog)
	box.add_child(dialogs._label("Open part of the quest. Each is edited like a level; triggers in any of them can complete the quest's steps.", true))
	var go := func(path: String) -> void:
		dialog.queue_free()
		dialogs.leave_level(func() -> void: app.open_path(path))
	var here: String = app.doc.level.dir
	var n2 := Button.new()
	n2.text = "Nomad-2 (people and props)" + ("  (open)" if here == q.nomad2_dir() else "")
	n2.disabled = here == q.nomad2_dir()
	n2.pressed.connect(func() -> void: go.call(q.nomad2_dir()))
	box.add_child(n2)
	for l in q.levels():
		var b := Button.new()
		var path := q.levels_dir().path_join(l)
		b.text = "Level: %s%s" % [l, "  (open)" if here == path else ""]
		b.disabled = here == path
		b.pressed.connect(func() -> void: go.call(path))
		box.add_child(b)
	var make := Button.new()
	make.text = "New level for this quest..."
	make.pressed.connect(func() -> void:
		dialog.queue_free()
		new_quest_level())
	box.add_child(make)
	dialog.confirmed.connect(dialog.queue_free)
	dialogs._show(dialog)


func new_quest_level() -> void:
	var q := _quest()
	if q == null:
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "New level for " + q.title()
	dialog.ok_button_text = "Create"
	var box := dialogs._vbox(dialog)
	box.add_child(dialogs._label("A level only this quest uses. It's added to where the teleporter goes, and starts with a floor and a teleporter back to Nomad-2.", true))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Survey site"
	Dialogs._row(box, "Name", name_edit)
	dialog.confirmed.connect(func() -> void:
		var name := name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "Quest level"
		dialog.queue_free()
		dialogs.leave_level(func() -> void:
			var path := create_quest_level(q, name)
			if path == "":
				dialogs.tell("Couldn't create the level", "The quest's levels folder couldn't be written.")
				return
			app.open_path(path)))
	dialogs._show(dialog)
	name_edit.grab_focus.call_deferred()


## Makes a level in the quest's levels folder and adds it to the quest's
## areas. Returns its folder ("" if it couldn't be written).
static func create_quest_level(q: QuestDoc, name: String) -> String:
	var slug := EditorDoc.slug(name)
	var dir := q.levels_dir().path_join(slug)
	var n := 2
	while DirAccess.dir_exists_absolute(dir):
		slug = "%s_%d" % [EditorDoc.slug(name), n]
		dir = q.levels_dir().path_join(slug)
		n += 1
	var doc := EditorDoc.create(name, "", dir)
	doc.add("piece", {"asset": "builtin:box", "size": [16, 0.5, 16], "pos": [0, -0.5, 0], "surface": "floor", "color": Catalog.FLOOR_COLOR})
	doc.level.map.start = {"pos": [0, 0.1, 4], "yaw": 0}
	doc.add("object", {"type": "teleporter", "destination": "hub", "label": "Back to Nomad-2", "pos": [0, 0, 6.5]})
	doc._reset_history()
	if doc.save() != OK:
		return ""
	(q.data.areas as Array).append({"quest_level": slug, "name": name})
	q.save()
	return dir


# --- Export -----------------------------------------------------------------------------------

## Checks the quest and all its levels; "" when they can be exported, else
## the problems, one per line.
static func check_quest(q: QuestDoc) -> String:
	var lines := PackedStringArray()
	for p in q.problems():
		lines.append("Quest: " + p)
	var parts := [["Nomad-2", q.nomad2_dir()]]
	for l in q.levels():
		parts.append(["Level " + l, q.levels_dir().path_join(l)])
	for part in parts:
		var doc := EditorDoc.open(String(part[1]))
		if doc == null:
			continue
		for p in LevelCheck.errors(LevelCheck.run(doc)):
			lines.append("%s: %s" % [part[0], p.text])
	return "\n".join(lines)


## Writes the finished quest into `dest`: quest.json, its Nomad-2 and its
## levels (each trimmed like an exported level). "" or what went wrong.
static func export_quest(q: QuestDoc, dest: String) -> String:
	var err := DirAccess.make_dir_recursive_absolute(dest)
	if err != OK:
		return "Couldn't make the folder %s (%s)." % [dest, error_string(err)]
	var copy := QuestDoc.new()
	copy.dir = dest
	copy.data = q.data.duplicate(true)
	if copy.save() != OK:
		return "Couldn't write quest.json in %s." % dest
	var n2 := LevelData.load_dir(q.nomad2_dir())
	if n2:
		var problem := Exporter.to_folder(n2, dest.path_join("nomad2"))
		if problem != "":
			return problem
	for l in q.levels():
		var level := LevelData.load_dir(q.levels_dir().path_join(l))
		if level:
			var problem := Exporter.to_folder(level, dest.path_join("levels").path_join(l))
			if problem != "":
				return problem
	return ""


func export_current() -> void:
	var q := _quest()
	if q == null:
		dialogs.tell("Not a quest", "This level isn't part of a quest.")
		return
	app.save_level()
	var problems := check_quest(q)
	if problems != "":
		dialogs.tell("The quest isn't ready yet", "Fix these first (open each part from Quest > The quest's levels):\n\n" + problems)
		return
	var id := String(q.data.get("id", EditorDoc.slug(q.title())))
	if AppSettings.has_game():
		var dest := AppSettings.game_dir().path_join("quests").path_join(id)
		dialogs.ask("Export the quest to the game?", "It goes to %s, where the Guild lists it. Anything already there is replaced." % dest, "Export", func() -> void:
			var problem := export_quest(q, dest)
			if problem != "":
				dialogs.tell("Couldn't export", problem)
			else:
				app.toast("Exported %s to the game's quests folder." % q.title()))
	else:
		dialogs.pick_file(FileDialog.FILE_MODE_OPEN_DIR, "Export the quest into a folder", PackedStringArray(), func(path: String) -> void:
			var problem := export_quest(q, path.path_join(id))
			if problem != "":
				dialogs.tell("Couldn't export", problem)
			else:
				app.toast("Exported %s to %s." % [q.title(), path.path_join(id)]))


func playtest() -> void:
	var q := _quest()
	if q == null:
		return
	app.playtest_with("--quest=" + q.dir)
