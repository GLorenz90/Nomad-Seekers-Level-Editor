class_name BottomPanels
extends TabContainer
## The tabs under the view: Problems (the live level check), Triggers
## (every trigger as a sentence), Waves (each room's fight) and Dialogues.

var app: Node
var _problems: ItemList
var _rules: ItemList
var _waves: Tree
var _talk_list: ItemList
var _talk_box: VBoxContainer
var _talk_id := ""
var _talk_own := false


func _init() -> void:
	custom_minimum_size.y = 210
	# Problems
	_problems = ItemList.new()
	_problems.allow_search = false
	_problems.name = "Problems"
	_problems.item_selected.connect(func(index: int) -> void: app.go_to_problem(_problems.get_item_metadata(index)))
	add_child(_problems)
	# Triggers
	var rules_tab := VBoxContainer.new()
	rules_tab.name = "Triggers"
	var bar := HBoxContainer.new()
	bar.add_child(_button("New trigger...", "A trigger says \"when this happens, do that\".", func() -> void:
		app.dialogs.edit_rule({"id": "", "when": {"event": "", "source": ""}, "do": [], "once": true})))
	bar.add_child(_button("Edit", "Edit the selected trigger (or double-click it).", func() -> void: _edit_rule()))
	bar.add_child(_button("Delete", "Delete the selected trigger.", func() -> void:
		var picked := _rules.get_selected_items()
		if not picked.is_empty():
			app.doc.remove_rule(String(_rules.get_item_metadata(picked[0])))
			app.doc.commit()))
	rules_tab.add_child(bar)
	_rules = ItemList.new()
	_rules.allow_search = false
	_rules.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rules.item_activated.connect(func(_index: int) -> void: _edit_rule())
	rules_tab.add_child(_rules)
	add_child(rules_tab)
	# Waves
	var waves_tab := VBoxContainer.new()
	waves_tab.name = "Waves"
	var wave_bar := HBoxContainer.new()
	wave_bar.add_child(_button("Add a wave", "Adds a wave to the selected room (or the room of the selected wave or enemy).", func() -> void:
		var room := _wave_room()
		if room != "":
			app.set_place_wave(app.doc.add_wave(room) + 1)
			app.doc.commit()
		else:
			app.toast("Select a room first (click its floor on the Combat layer).")))
	wave_bar.add_child(_button("Delete wave", "Deletes the selected wave. Its enemies are deleted too.", func() -> void: _delete_wave()))
	wave_bar.add_child(_button("Place into this wave", "New enemies will go into the selected wave.", func() -> void:
		var meta = _waves.get_selected().get_metadata(0) if _waves.get_selected() else null
		if meta is Dictionary and meta.has("wave"):
			app.set_place_wave(int(meta.wave) + 1)
			app.toast("New enemies placed in that room will join wave %d." % (int(meta.wave) + 1))))
	waves_tab.add_child(wave_bar)
	_waves = Tree.new()
	_waves.allow_search = false
	_waves.hide_root = true
	_waves.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_waves.item_selected.connect(func() -> void:
		var meta = _waves.get_selected().get_metadata(0)
		if meta is Dictionary and meta.has("id"):
			app.set_layer(3)
			app.doc.select(String(meta.id)))
	waves_tab.add_child(_waves)
	add_child(waves_tab)
	# Dialogues
	var talk_tab := HSplitContainer.new()
	talk_tab.name = "Dialogues"
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 220
	var talk_bar := HBoxContainer.new()
	talk_bar.add_child(_button("New dialogue", "A short conversation: lines with a speaker, then optional choices. Start it with a trigger.", func() -> void:
		var id: String = app.doc.new_id("dialogue")
		app.doc.level.interaction.dialogues.append({"id": id, "lines": [{"speaker": "", "text": ""}]})
		_talk_id = id
		app.doc.commit()))
	talk_bar.add_child(_button("Delete", "Delete the selected dialogue.", func() -> void:
		var d: Dictionary = app.doc.find_dialogue(_talk_id)
		if not d.is_empty():
			(app.doc.level.interaction.dialogues as Array).erase(d)
			_talk_id = ""
			app.doc.commit()))
	left.add_child(talk_bar)
	_talk_list = ItemList.new()
	_talk_list.allow_search = false
	_talk_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_talk_list.item_selected.connect(func(index: int) -> void:
		_talk_id = String(_talk_list.get_item_metadata(index))
		_fill_dialogue())
	left.add_child(_talk_list)
	talk_tab.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_talk_box = VBoxContainer.new()
	_talk_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_talk_box)
	talk_tab.add_child(scroll)
	add_child(talk_tab)


func _button(text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(on_press)
	return b


func show_tab(tab_name: String) -> void:
	for i in get_tab_count():
		if get_tab_title(i) == tab_name:
			current_tab = i


func show_dialogue(id: String) -> void:
	_talk_id = id
	show_tab("Dialogues")
	refresh()


func select_rule(id: String) -> void:
	show_tab("Triggers")
	for i in _rules.item_count:
		if String(_rules.get_item_metadata(i)) == id:
			_rules.select(i)
			_rules.ensure_current_is_visible()


func refresh(fill_dialogue := true) -> void:
	var doc: EditorDoc = app.doc
	if doc == null:
		return
	# Problems
	_problems.clear()
	var errors := LevelCheck.errors(app.problems)
	var warnings := LevelCheck.warnings(app.problems)
	for p in errors + warnings:
		var index := _problems.add_item(("MUST FIX   " if p.level == "error" else "CHECK      ") + String(p.text))
		_problems.set_item_metadata(index, p)
		_problems.set_item_tooltip(index, String(p.text) + "\n(Click to go to it.)")
		_problems.set_item_custom_fg_color(index, Color(1.0, 0.55, 0.5) if p.level == "error" else Color(1.0, 0.85, 0.45))
	if app.problems.is_empty():
		var index := _problems.add_item("No problems found. The level is ready to export.")
		_problems.set_item_selectable(index, false)
		_problems.set_item_custom_fg_color(index, Color(0.55, 0.95, 0.6))
	set_tab_title(0, "Problems" if app.problems.is_empty() else "Problems (%d)" % app.problems.size())
	# Triggers
	var picked := _rules.get_selected_items()
	var picked_id := String(_rules.get_item_metadata(picked[0])) if not picked.is_empty() else ""
	_rules.clear()
	for rule in doc.level.interaction.rules:
		var index := _rules.add_item(Wiring.describe(rule, doc))
		_rules.set_item_metadata(index, String(rule.get("id", "")))
		if String(rule.get("id", "")) == picked_id:
			_rules.select(index)
	set_tab_title(1, "Triggers (%d)" % _rules.item_count)
	_fill_waves()
	# Dialogues
	_talk_list.clear()
	for d in doc.level.interaction.dialogues:
		var index := _talk_list.add_item(String(d.id))
		_talk_list.set_item_metadata(index, String(d.id))
		if String(d.id) == _talk_id:
			_talk_list.select(index)
	set_tab_title(3, "Dialogues (%d)" % _talk_list.item_count)
	if fill_dialogue and not _talk_own:
		_fill_dialogue()


func _edit_rule() -> void:
	var picked := _rules.get_selected_items()
	if not picked.is_empty():
		app.dialogs.edit_rule(app.doc.find_rule(String(_rules.get_item_metadata(picked[0]))))


# --- Waves ------------------------------------------------------------------------------------

func _fill_waves() -> void:
	var doc: EditorDoc = app.doc
	_waves.clear()
	var root := _waves.create_item()
	for c in doc.level.combat.rooms:
		var room := String(c.room)
		var head := _waves.create_item(root)
		head.set_text(0, "%s: starts %s" % [doc.label_of(room),
			"when a Seeker walks in" if String(c.get("start", "enter")) == "enter" else "when a trigger starts it"])
		head.set_metadata(0, {"id": room, "room": room})
		head.set_custom_color(0, Color(0.65, 0.85, 1.0))
		var waves: Array = c.waves
		for w in waves.size():
			var enemies: Array = waves[w].get("enemies", [])
			var wave_item := _waves.create_item(head)
			wave_item.set_text(0, "Wave %d (%d)%s" % [w + 1, enemies.size(), "   EMPTY: place enemies or delete it" if enemies.is_empty() else ""])
			wave_item.set_metadata(0, {"room": room, "wave": w})
			if enemies.is_empty():
				wave_item.set_custom_color(0, Color(1.0, 0.55, 0.5))
			for e in enemies:
				_enemy_row(wave_item, e)
	if not (doc.level.combat.free as Array).is_empty():
		var head := _waves.create_item(root)
		head.set_text(0, "Not in waves (there from the start)")
		head.set_selectable(0, false)
		head.set_custom_color(0, Color(0.65, 0.85, 1.0))
		for e in doc.level.combat.free:
			_enemy_row(head, e)
	set_tab_title(2, "Waves (%d rooms)" % (doc.level.combat.rooms as Array).size())


func _enemy_row(parent: TreeItem, e: Dictionary) -> void:
	var row := _waves.create_item(parent)
	var delay := float(e.get("spawn_delay", 0.0))
	row.set_text(0, app.doc.label_of(String(e.id)) + ("   +%s s" % str(delay) if delay > 0.0 else ""))
	row.set_metadata(0, {"id": String(e.id)})
	if LevelData.placement_problem(e) != "":
		row.set_custom_color(0, Color(1.0, 0.55, 0.5))


## The room the Waves tab's buttons act on.
func _wave_room() -> String:
	var meta = _waves.get_selected().get_metadata(0) if _waves.get_selected() else null
	if meta is Dictionary and meta.has("room"):
		return String(meta.room)
	var doc: EditorDoc = app.doc
	if doc.kind_of(doc.selected) == "area":
		return doc.selected
	return String(doc.enemy_slot(doc.selected).get("room", ""))


func _delete_wave() -> void:
	var meta = _waves.get_selected().get_metadata(0) if _waves.get_selected() else null
	if not (meta is Dictionary and meta.has("wave")):
		app.toast("Select a wave in the list first.")
		return
	var c: Dictionary = app.doc.level.combat_room(String(meta.room))
	var waves: Array = c.get("waves", [])
	var count: int = (waves[int(meta.wave)].get("enemies", []) as Array).size()
	var go := func() -> void:
		waves.remove_at(int(meta.wave))
		app.doc.commit()
	if count == 0:
		go.call()
	else:
		app.dialogs.ask("Delete wave %d?" % (int(meta.wave) + 1), "Its %d enemies will be deleted too." % count, "Delete", go)


# --- Dialogues --------------------------------------------------------------------------------

func _fill_dialogue() -> void:
	for child in _talk_box.get_children():
		_talk_box.remove_child(child)
		child.queue_free()
	var doc: EditorDoc = app.doc
	var d := doc.find_dialogue(_talk_id)
	if d.is_empty():
		var note := Label.new()
		note.text = "Dialogues are short conversations shown at the bottom of the screen, like a holo-call.\nMake one, then start it with a trigger (for example, when Seekers walk into a zone).\nIts ending, and the choice picked, can set off other triggers."
		note.add_theme_color_override("font_color", Color(0.72, 0.75, 0.8))
		_talk_box.add_child(note)
		return
	var save := func(redraw: bool) -> void:
		_talk_own = not redraw
		doc.commit("dialogue:" + _talk_id)
		_talk_own = false
	var id_row := HBoxContainer.new()
	var id_label := Label.new()
	id_label.text = "Id"
	id_row.add_child(id_label)
	var id_edit := LineEdit.new()
	id_edit.text = _talk_id
	id_edit.custom_minimum_size.x = 220
	id_edit.text_submitted.connect(func(text: String) -> void:
		var problem := doc.rename(_talk_id, text)
		if problem != "":
			app.toast(problem)
		else:
			_talk_id = String(d.id)
			doc.commit())
	id_row.add_child(id_edit)
	_talk_box.add_child(id_row)
	var lines: Array = d.get("lines", [])
	for i in lines.size():
		var line: Dictionary = lines[i]
		var row := HBoxContainer.new()
		var speaker := LineEdit.new()
		speaker.text = String(line.get("speaker", ""))
		speaker.placeholder_text = "Who's speaking"
		speaker.custom_minimum_size.x = 180
		speaker.text_changed.connect(func(text: String) -> void:
			line.speaker = text
			save.call(false))
		row.add_child(speaker)
		var text_edit := LineEdit.new()
		text_edit.text = String(line.get("text", ""))
		text_edit.placeholder_text = "What they say"
		text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_edit.text_changed.connect(func(text: String) -> void:
			line.text = text
			save.call(false))
		row.add_child(text_edit)
		row.add_child(_button("X", "Remove this line.", func() -> void:
			lines.remove_at(i)
			save.call(true)))
		_talk_box.add_child(row)
	_talk_box.add_child(_button("Add a line", "", func() -> void:
		var last_speaker := String(lines[lines.size() - 1].get("speaker", "")) if not lines.is_empty() else ""
		lines.append({"speaker": last_speaker, "text": ""})
		d.lines = lines
		save.call(true)))
	var choices_label := Label.new()
	choices_label.text = "Choices at the end (optional)"
	choices_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	_talk_box.add_child(choices_label)
	var choices: Array = d.get("choices", [])
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var row := HBoxContainer.new()
		var text_edit := LineEdit.new()
		text_edit.text = String(choice.get("text", ""))
		text_edit.placeholder_text = "What the player can answer"
		text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_edit.text_changed.connect(func(text: String) -> void:
			choice.text = text
			save.call(false))
		row.add_child(text_edit)
		row.add_child(_button("X", "Remove this choice.", func() -> void:
			choices.remove_at(i)
			if choices.is_empty():
				d.erase("choices")
			save.call(true)))
		_talk_box.add_child(row)
	_talk_box.add_child(_button("Add a choice", "Triggers can react to which choice was picked.", func() -> void:
		var n := 1
		var taken := {}
		for c in choices:
			taken[String(c.get("id", ""))] = true
		while taken.has("choice_%d" % n):
			n += 1
		choices.append({"id": "choice_%d" % n, "text": ""})
		d.choices = choices
		save.call(true)))
