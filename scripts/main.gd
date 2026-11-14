extends Control
## The level editor's window: menus and toolbar on top, the palette on the
## left, the 3D view in the middle with the Problems / Triggers / Waves /
## Dialogues tabs under it, and the outline and inspector on the right.
##
## Everything edits one EditorDoc. After any change the navmesh is baked
## again (a moment later, so dragging stays smooth), the level is checked
## again (LevelCheck) and every panel redraws from the data.

const CONTROLS := """Looking around
  Right-drag: look around (hold it and W A S D to fly)          Wheel: zoom
  Middle-drag or Shift + right-drag: slide the view
  Arrow keys: slide the view        F: centre on the selection
  O (or Numpad 5): perspective / orthographic        Numpad 7: top-down view

Building (like Godot)
  Click something in the Place list, then click in the view. Keep clicking to place more.
  R while placing: turn it a quarter turn.    Esc or right-click: stop placing
  Click: select        Drag: slide along the ground
  Q: select only    W: move handles    E: rotate handles    R: resize handles
  T: move and rotate along the world's axes (Global) or the piece's own (Local)
  R again: resize from the centre, or by sides (pull any face or corner;
           the opposite face or corner stays put)
  Move: drag an arrow along its axis, or a square to slide across that plane.
  Drag a handle to move, turn or resize along it. Hold Alt for no snapping.
  Page Up / Page Down: raise / lower by half a metre
  Ctrl + D: duplicate        Delete: remove

Rooms
  The colored navmesh is where Seekers can walk; each color is a room.
  Put a Room boundary across a doorway to split it. N: click picks rooms instead of pieces.

Layers
  1, 2, 3: Map, Interaction, Combat. Only the current layer's things can be clicked.

Files
  Ctrl + S: save      Ctrl + Z / Ctrl + Y: undo / redo
  Ctrl + E: check and export      F5: playtest in the game"""

var doc: EditorDoc
var layer := 1
var problems: Array = []
var snap_step := 0.5
var gizmo_mode := TransformGizmo.Mode.MOVE
var place_wave := 1

var view: LevelView
var dialogs: Dialogs
var quests: QuestDialogs
var palette: Palette
var outline: Outline
var inspector: Inspector
var bottom: BottomPanels

var _layer_buttons: Array[Button] = []
var _status: Label
var _counts: Label
var _badge: Button
var _undo: Button
var _redo: Button
var _body: Control
var _empty: Control
var _view_menu: PopupMenu
var _toast_until := 0
var _nav_due := 0
var _mode_buttons: Array[Button] = []
var _pick_rooms: Button
var _space: Button
var _ortho: Button
var _pending := {}
var _flush_queued := false


## The editor's text size (Godot's default is 16, too big for 1600 x 900).
const FONT_SIZE := 13

func _ready() -> void:
	get_tree().auto_accept_quit = false
	# Every control, menu and dialog that doesn't set its own size uses this
	# (themes pass down to every window, popups and dialogs included).
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE
	get_tree().root.theme = theme
	dialogs = Dialogs.new()
	dialogs.app = self
	add_child(dialogs)
	quests = QuestDialogs.new()
	quests.app = self
	quests.dialogs = dialogs
	add_child(quests)
	_build()
	_refresh_all()
	var open_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--open="):
			open_dir = arg.trim_prefix("--open=")
	if open_dir != "":
		open_path.call_deferred(open_dir)
	elif DisplayServer.get_name() != "headless":
		dialogs.welcome.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		dialogs.leave_level(func() -> void: get_tree().quit())


# --- Layout -----------------------------------------------------------------------------------

func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var back := ColorRect.new()
	back.color = Color(0.13, 0.14, 0.17)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	move_child(back, 0)

	# Two rows: menus, layers and the level's actions on top; the editing
	# tools (handles, camera, picking, undo, snap) underneath.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	root.add_child(tools)
	_menu(bar, "File", [["New level...   Ctrl+N", func() -> void: dialogs.leave_level(dialogs.new_level)],
		["Open...   Ctrl+O", func() -> void: dialogs.leave_level(dialogs.welcome)],
		["Save   Ctrl+S", save_level], ["Check and export...   Ctrl+E", export_level], [],
		["Settings...", dialogs.settings], ["Quit", func() -> void: dialogs.leave_level(func() -> void: get_tree().quit())]])
	_menu(bar, "Level", [["Level settings...", func() -> void: _need_doc(dialogs.level_settings)],
		["Imported models...", func() -> void: _need_doc(dialogs.models)],
		["Import a model...", func() -> void: _need_doc(dialogs.import_model)],
		["New material from an image...", func() -> void: _need_doc(dialogs.import_material)],
		["Licenses...", func() -> void: _need_doc(dialogs.licenses)], [],
		["Playtest in the game   F5", playtest]])
	_menu(bar, "Quest", [["New quest...", func() -> void: dialogs.leave_level(quests.new_quest)],
		["Open a quest...", func() -> void: dialogs.leave_level(quests.open_quest)], [],
		["Quest details...", func() -> void: _need_doc(quests.quest_details)],
		["The quest's Nomad-2 and levels...", func() -> void: _need_doc(quests.quest_levels)],
		["New level for this quest...", func() -> void: _need_doc(quests.new_quest_level)], [],
		["Check and export the quest...", func() -> void: _need_doc(quests.export_current)],
		["Playtest the quest", func() -> void: _need_doc(quests.playtest)]])
	_view_menu = _menu(bar, "View", [["Top-down view   Numpad 7", func() -> void: toggle_top()],
		["Show the other layers' things", func() -> void: _toggle_view_option(1)],
		["Show trigger lines", func() -> void: _toggle_view_option(2)],
		["Show the navmesh", func() -> void: _toggle_view_option(3)],
		["Orthographic   O", func() -> void: set_ortho(not view.ortho)], [],
		["Show the whole level", func() -> void: view.focus("")]])
	for i in 5:
		_view_menu.set_item_as_checkable(i, true)
	for i in [1, 2, 3]:
		_view_menu.set_item_checked(i, true)
	_menu(bar, "Help", [["Controls", func() -> void: dialogs.tell("Controls", CONTROLS)],
		["Open the starter example", func() -> void: dialogs.leave_level(open_example)],
		["About layers", func() -> void: dialogs.tell("The three layers", "\n\n".join(Catalog.LAYER_HELP.values()))]])
	bar.add_child(VSeparator.new())
	var group := ButtonGroup.new()
	for n in [1, 2, 3]:
		var b := Button.new()
		b.text = "%d  %s" % [n, Catalog.LAYER_NAMES[n]]
		b.tooltip_text = Catalog.LAYER_HELP[n] + "  (Press %d)" % n
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = n == 1
		b.custom_minimum_size.x = 120
		b.pressed.connect(func() -> void: set_layer(n))
		bar.add_child(b)
		_layer_buttons.append(b)
	bar.add_child(VSeparator.new())
	var modes := ButtonGroup.new()
	for spec in [[TransformGizmo.Mode.SELECT, "Select", "Q: click to select, no handles."],
			[TransformGizmo.Mode.MOVE, "Move", "W: arrows move it along an axis; the squares slide it across a plane."],
			[TransformGizmo.Mode.ROTATE, "Rotate", "E: rings to turn it (snaps to 15°; hold Alt for free turning)."],
			[TransformGizmo.Mode.SCALE, "Resize: centre", "R: resize handles. Press R again to switch between resizing from the centre and by sides (pull a face or a corner; the opposite one stays put)."]]:
		var b := Button.new()
		b.text = spec[1]
		b.tooltip_text = spec[2]
		b.toggle_mode = true
		b.button_group = modes
		b.button_pressed = spec[0] == gizmo_mode
		var m: int = spec[0]
		b.pressed.connect(func() -> void: set_gizmo_mode(m))
		tools.add_child(b)
		_mode_buttons.append(b)
	_space = Button.new()
	_space.toggle_mode = true
	_space.text = "Global"
	_space.tooltip_text = "T: move and rotate along the world's axes (Global) or the piece's own axes (Local). Resizing always uses the piece's own axes."
	_space.toggled.connect(func(on: bool) -> void: set_local(on))
	tools.add_child(_space)
	_ortho = Button.new()
	_ortho.toggle_mode = true
	_ortho.text = "Perspective"
	_ortho.tooltip_text = "O (or Numpad 5): switch the camera between perspective and orthographic."
	_ortho.toggled.connect(func(on: bool) -> void: set_ortho(on))
	tools.add_child(_ortho)
	tools.add_child(VSeparator.new())
	_pick_rooms = Button.new()
	_pick_rooms.text = "Click picks: Pieces"
	_pick_rooms.toggle_mode = true
	_pick_rooms.tooltip_text = "N: switch between picking pieces and picking rooms (the navmesh). Pick a room to name it, make it a corridor, or join it with another."
	_pick_rooms.toggled.connect(func(on: bool) -> void: set_pick_rooms(on))
	tools.add_child(_pick_rooms)
	tools.add_child(VSeparator.new())
	_undo = _tool(tools, "Undo", "Undo (Ctrl+Z)", func() -> void: doc.undo())
	_redo = _tool(tools, "Redo", "Redo (Ctrl+Y)", func() -> void: doc.redo())
	tools.add_child(VSeparator.new())
	var snap_label := Label.new()
	snap_label.text = "Snap"
	tools.add_child(snap_label)
	var snap := OptionButton.new()
	snap.tooltip_text = "How things line up when you move, place or resize them (rotation snaps to 15°). Hold Alt while dragging to turn snapping off for a moment."
	for spec in [[4.0, "4 m"], [1.0, "1 m"], [0.5, "0.5 m"], [0.0, "Off"]]:
		snap.add_item(spec[1])
		snap.set_item_metadata(snap.item_count - 1, spec[0])
	snap.select(2)
	snap.item_selected.connect(func(index: int) -> void: snap_step = float(snap.get_item_metadata(index)))
	tools.add_child(snap)
	_tool(bar, "Playtest", "Save and run this level in the game (F5).", playtest)
	_tool(bar, "Check and export", "Check the level for problems, then export it (Ctrl+E).", export_level)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_badge = _tool(bar, "", "The live level check. Click to see the list.", func() -> void: bottom.show_tab("Problems"))

	_empty = CenterContainer.new()
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var empty_box := VBoxContainer.new()
	var empty_label := Label.new()
	empty_label.text = "No level open"
	empty_label.add_theme_font_size_override("font_size", 20)
	empty_box.add_child(empty_label)
	_tool(empty_box, "New level...", "", dialogs.new_level)
	_tool(empty_box, "Open a level...", "", dialogs.welcome)
	_empty.add_child(empty_box)
	root.add_child(_empty)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body = split
	root.add_child(split)
	palette = Palette.new()
	palette.app = self
	split.add_child(_padded(palette))
	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right_split)
	var middle := VSplitContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.add_child(middle)
	view = LevelView.new()
	view.app = self
	view.hint.connect(func(text: String) -> void: _set_hint(text))
	view.placed.connect(func(_id: String) -> void: pass)
	middle.add_child(view)
	bottom = BottomPanels.new()
	bottom.app = self
	middle.add_child(bottom)
	var right := VSplitContainer.new()
	right.custom_minimum_size.x = 330
	right_split.add_child(right)
	outline = Outline.new()
	outline.app = self
	outline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outline.size_flags_stretch_ratio = 1.0
	right.add_child(outline)
	inspector = Inspector.new()
	inspector.app = self
	var inspector_box := _padded(inspector)
	inspector_box.size_flags_stretch_ratio = 2.5
	right.add_child(inspector_box)

	var status := HBoxContainer.new()
	root.add_child(status)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	status.add_child(_status)
	_counts = Label.new()
	status.add_child(_counts)


func _padded(inner: Control) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 6)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.add_child(inner)
	return m


func _menu(bar: Container, title: String, entries: Array) -> PopupMenu:
	var mb := MenuButton.new()
	mb.text = title
	mb.flat = false
	var popup := mb.get_popup()
	var actions := []
	for entry in entries:
		if entry.is_empty():
			popup.add_separator()
			actions.append(Callable())
		else:
			popup.add_item(entry[0])
			actions.append(entry[1])
	popup.index_pressed.connect(func(index: int) -> void:
		var action: Callable = actions[index]
		if action.is_valid():
			action.call())
	bar.add_child(mb)
	return popup


func _tool(bar: Container, text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(func() -> void:
		if doc != null or bar != _body:
			on_press.call())
	bar.add_child(b)
	return b


func _need_doc(then: Callable) -> void:
	if doc != null:
		then.call()


# --- The level --------------------------------------------------------------------------------

func set_doc(new_doc: EditorDoc) -> void:
	doc = new_doc
	Catalog.quest_steps = doc.quest.step_options() if doc.quest else []
	doc.changed.connect(_on_changed)
	doc.selection_changed.connect(_on_selection)
	AppSettings.add_recent(doc.level.dir)
	Catalog.enemies()
	view.set_doc(doc)
	view.focus("")
	set_layer(1)
	_refresh_all()
	_set_hint("")


func open_path(path: String) -> void:
	if path.get_file() == "level.json":
		path = path.get_base_dir()
	var opened := EditorDoc.open(path)
	if opened == null:
		dialogs.tell("That isn't a level", "There's no level.json in %s. Choose a level's own folder." % path)
		return
	set_doc(opened)


const EXAMPLE := "res://examples/starter_large"

## Opens the user's own copy of the bundled example (made on first use).
func open_example() -> void:
	var dest := AppSettings.library_dir().path_join("Starter - Mossy Ruins")
	if not FileAccess.file_exists(dest.path_join("level.json")):
		DirAccess.make_dir_recursive_absolute(dest)
		for file in DirAccess.get_files_at(EXAMPLE):
			if file.ends_with(".json"):
				var text := FileAccess.get_file_as_string(EXAMPLE.path_join(file))
				var f := FileAccess.open(dest.path_join(file), FileAccess.WRITE)
				if f == null:
					dialogs.tell("Couldn't copy the example", "The example couldn't be written to %s." % dest)
					return
				f.store_string(text)
				f.close()
	open_path(dest)


func save_level() -> void:
	if doc == null:
		return
	var err := doc.save()
	if err != OK:
		dialogs.tell("Couldn't save", "The level couldn't be written to %s (%s)." % [doc.level.dir, error_string(err)])
	else:
		toast("Saved.")


func export_level() -> void:
	if doc != null:
		dialogs.export_level()


func settings_changed() -> void:
	Catalog._enemies_from = "?"
	_refresh_all()


func _on_changed() -> void:
	# The navmesh (and with it the rooms and the level check) catches up a
	# moment after the last change.
	_nav_due = Time.get_ticks_msec() + 200
	# Note now whether the change came from the inspector or dialogue editor
	# (so they keep focus while typing); the redraw itself waits for the end
	# of the frame, so no panel is rebuilt while one of its own controls is
	# still sending the signal that caused it. Godot crashes (or blocks the
	# Tree, leaving it empty) when that happens.
	if inspector._own_change and inspector._shown == doc.selected:
		inspector._fill_problems()
	else:
		_pending["inspector"] = true
	if not bottom._talk_own:
		_pending["dialogue"] = true
	for what in ["view", "outline", "bottom", "bars"]:
		_pending[what] = true
	if layer == 1:
		_pending["palette"] = true  # imported models may have changed
	_schedule()


func _on_selection() -> void:
	for what in ["overlay", "inspector", "outline"]:
		_pending[what] = true
	_schedule()


## Redraw everything (used when a level is opened).
func _refresh_all() -> void:
	_empty.visible = doc == null
	_body.visible = doc != null
	if doc != null:
		problems = LevelCheck.run(doc)
		view.refresh_nav()
		for what in ["view", "palette", "outline", "inspector", "bottom", "dialogue"]:
			_pending[what] = true
	_pending["bars"] = true
	_schedule()


func _schedule() -> void:
	if not _flush_queued:
		_flush_queued = true
		_flush.call_deferred()


## Does the queued redraws, once each, after the current signal has finished.
func _flush() -> void:
	_flush_queued = false
	var todo := _pending
	_pending = {}
	if doc == null:
		_refresh_bars()
		return
	if todo.has("view"):
		view.rebuild()
	elif todo.has("overlay"):
		view.refresh_overlay()
	if todo.has("palette"):
		palette.refresh()
	if todo.has("outline"):
		outline.refresh()
	if todo.has("inspector"):
		inspector.rebuild()
	if todo.has("bottom"):
		bottom.refresh(todo.has("dialogue"))
	if todo.has("bars"):
		_refresh_bars()


func _refresh_bars() -> void:
	if doc == null:
		get_window().title = "Nomad's Seekers Level Editor"
		_badge.text = ""
		_counts.text = ""
		return
	get_window().title = "%s%s - Nomad's Seekers Level Editor" % [doc.level.meta.get("name", "Untitled"), " *" if doc.dirty else ""]
	_undo.disabled = not doc.can_undo()
	_redo.disabled = not doc.can_redo()
	var errors := LevelCheck.errors(problems).size()
	var warnings := LevelCheck.warnings(problems).size()
	if errors == 0 and warnings == 0:
		_badge.text = "No problems"
		_badge.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6))
	else:
		_badge.text = ("%d to fix" % errors if errors > 0 else "") + (", " if errors > 0 and warnings > 0 else "") \
			+ ("%d to check" % warnings if warnings > 0 else "")
		_badge.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if errors > 0 else Color(1.0, 0.85, 0.45))
	var level := doc.level
	_layer_buttons[2].disabled = doc.is_nomad2()
	var part := ""
	if doc.quest:
		part = "Quest \"%s\": %s    " % [doc.quest.title(), "Nomad-2" if doc.is_nomad2() else "its own level"]
	if doc.is_nomad2():
		_counts.text = "%s%s   " % [part, "Unsaved changes" if doc.dirty else "Saved"]
		return
	_counts.text = "%s%s: %d room%s, %d corridor%s    %s   " % [part, level.size_name(), level.room_count(),
		"" if level.room_count() == 1 else "s", level.corridor_count(), "" if level.corridor_count() == 1 else "s",
		"Unsaved changes" if doc.dirty else "Saved"]


func set_layer(n: int) -> void:
	layer = clampi(n, 1, 3)
	if doc != null and doc.is_nomad2() and layer == 3:
		layer = 2  # Nomad-2 is peaceful: no Combat layer
		toast("Nomad-2 is peaceful, so it has no Combat layer.")
	for i in _layer_buttons.size():
		_layer_buttons[i].set_pressed_no_signal(i + 1 == layer)
	_pick_rooms.visible = layer == 1
	if doc == null:
		return
	view.cancel_place()
	var kind := doc.kind_of(doc.selected)
	if kind != "" and EditorDoc.KIND_LAYER[kind] != layer and not (kind == "area" and layer == 3):
		doc.select("")
	for what in ["view", "palette", "outline", "inspector"]:
		_pending[what] = true
	_schedule()
	_set_hint("")


func set_place_wave(n: int) -> void:
	place_wave = maxi(n, 1)
	palette.set_wave(place_wave)


func begin_place(entry: Dictionary) -> void:
	view.begin_place(entry)
	view.grab_focus()


func toggle_top() -> void:
	view.set_top_view(not view.is_top_view())
	_view_menu.set_item_checked(0, view.is_top_view())


func _toggle_view_option(index: int) -> void:
	var on := not _view_menu.is_item_checked(index)
	_view_menu.set_item_checked(index, on)
	if index == 1:
		view.show_all_layers = on
	elif index == 2:
		view.show_wires = on
	else:
		view.show_nav = on
		view.refresh_nav()
	view.rebuild()


# --- Acting on the selection --------------------------------------------------------------------

func delete_selected() -> void:
	if doc == null or doc.selected == "" or doc.selected == EditorDoc.START:
		return
	var id := doc.selected
	var refs := doc.references(id)
	var go := func() -> void:
		doc.remove(id)
		doc.commit()
	if refs.is_empty():
		go.call()
	else:
		dialogs.ask("Delete %s?" % doc.label_of(id),
			"Other things use it:\n\n- %s\n\nDelete it anyway? Anything left pointing at it will show up in the Problems tab." % "\n- ".join(refs),
			"Delete", go)


func duplicate_selected() -> void:
	if doc == null or doc.selected == "":
		return
	var id := doc.duplicate_item(doc.selected)
	if id != "":
		doc.select(id)
		doc.commit()


func rotate_selected(degrees: float) -> void:
	if view.is_placing():
		view.rotate_placing(degrees)
		return
	var it := doc.item(doc.selected)
	if it.is_empty():
		return
	Items.rotate(it.kind, it.data, degrees)
	doc.commit()


func raise_selected(by: float) -> void:
	var it := doc.item(doc.selected)
	if it.is_empty():
		return
	Items.set_pos(it.kind, it.data, Items.get_pos(it.kind, it.data) + Vector3(0, by, 0))
	doc.commit("raise:" + doc.selected)


## Jumps to whatever a problem points at.
func go_to_problem(p: Dictionary) -> void:
	var id := String(p.get("id", ""))
	if id.begins_with("rule:"):
		set_layer(2)
		bottom.select_rule(id.trim_prefix("rule:"))
	elif id.begins_with("dialogue:"):
		set_layer(2)
		bottom.show_dialogue(id.trim_prefix("dialogue:"))
	elif id != "":
		var kind := doc.kind_of(id)
		if kind != "":
			set_layer(int(p.get("layer", EditorDoc.KIND_LAYER[kind])) if kind == "area" else EditorDoc.KIND_LAYER[kind])
			doc.select(id)
			view.focus(id)
	else:
		set_layer(int(p.get("layer", layer)))
		if String(p.text).contains("Level settings"):
			dialogs.level_settings()


# --- Playtest -----------------------------------------------------------------------------------

## The quest was saved (Quest details): its steps and checks catch up.
func quest_changed() -> void:
	if doc == null or doc.quest == null:
		return
	doc.quest = QuestDoc.open(doc.quest.dir)
	Catalog.quest_steps = doc.quest.step_options() if doc.quest else []
	problems = LevelCheck.run(doc)
	_refresh_all()


func playtest() -> void:
	playtest_with("--level=" + doc.level.dir if doc else "")


## Runs the game with `arg` (--level=... or --quest=...).
func playtest_with(arg: String) -> void:
	if doc == null or arg == "":
		return
	var explicit := String(AppSettings.get_value("run_with", "")) != ""
	if not AppSettings.has_game() and not explicit:
		dialogs.tell("Where's the game?", "To playtest, the editor needs to know where Nomad's Seekers is. Open File > Settings and choose the game folder.")
		return
	if AppSettings.has_game() and not FileAccess.file_exists(AppSettings.game_dir().path_join("scripts/levels/data_level.gd")):
		dialogs.tell("This copy of the game can't load editor levels", "The game folder doesn't have level loading yet (it arrives with Part 13a). Update the game, then try again.")
		return
	save_level()
	var args := PackedStringArray()
	if AppSettings.has_game():
		args.append_array(["--path", AppSettings.game_dir()])
	args.append_array(["--", arg])
	var pid := OS.create_process(AppSettings.run_with(), args)
	if pid < 0:
		dialogs.tell("Couldn't start the game", "Running %s didn't work. Check \"Run the game with\" in Settings." % AppSettings.run_with())
	else:
		var errors := LevelCheck.errors(problems).size()
		toast("Playtest started." + (" The level still has %d problem(s) to fix, so parts may not work." % errors if errors > 0 else ""))


# --- Status bar ---------------------------------------------------------------------------------

func _set_hint(text: String) -> void:
	if text == "" and doc != null:
		text = Catalog.LAYER_HELP[layer]
		palette.clear_pressed()
	_status.text = "  " + text
	_status.remove_theme_color_override("font_color")
	_toast_until = 0


## A short message in the status bar.
func toast(text: String) -> void:
	_status.text = "  " + text
	_status.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_toast_until = Time.get_ticks_msec() + 6000


func _process(_delta: float) -> void:
	if _toast_until > 0 and Time.get_ticks_msec() > _toast_until and not view.is_placing():
		_set_hint("")
	if _nav_due > 0 and Time.get_ticks_msec() >= _nav_due and doc != null and not view.gizmo.is_dragging():
		_nav_due = 0
		_update_nav()


## Bakes the navmesh, finds the rooms, checks the level, redraws what changed.
func _update_nav() -> void:
	var before: int = doc.level.map.areas.size()
	doc.update_nav()
	problems = LevelCheck.run(doc)
	view.refresh_nav()
	for what in ["outline", "bottom", "bars", "overlay"]:
		_pending[what] = true
	if inspector._shown == "" or doc.kind_of(doc.selected) == "area" or before != doc.level.map.areas.size():
		_pending["inspector"] = true
	else:
		inspector._fill_problems()
	_schedule()


func set_gizmo_mode(m: int) -> void:
	# Pressing Resize again switches between from-the-centre and by-sides.
	if m == TransformGizmo.Mode.SCALE and gizmo_mode == TransformGizmo.Mode.SCALE:
		view.gizmo.scale_sides = not view.gizmo.scale_sides
		toast("Resize by sides: pull a face or a corner; the opposite one stays put." if view.gizmo.scale_sides
			else "Resize from the centre.")
	gizmo_mode = m
	for i in _mode_buttons.size():
		_mode_buttons[i].set_pressed_no_signal(i == m)
	_mode_buttons[TransformGizmo.Mode.SCALE].text = "Resize: sides" if view.gizmo.scale_sides else "Resize: centre"
	view.gizmo.mode = m
	view.gizmo.refresh()


## Move and rotate along the piece's own axes (true) or the world's.
func set_local(on: bool) -> void:
	view.gizmo.local = on
	_space.set_pressed_no_signal(on)
	_space.text = "Local" if on else "Global"
	view.gizmo.refresh()


func set_ortho(on: bool) -> void:
	view.set_ortho(on)
	_ortho.set_pressed_no_signal(on)
	_ortho.text = "Orthographic" if on else "Perspective"
	_view_menu.set_item_checked(4, on)
	view.gizmo.refresh()


func set_pick_rooms(on: bool) -> void:
	view.pick_rooms = on
	_pick_rooms.set_pressed_no_signal(on)
	_pick_rooms.text = "Click picks: Rooms" if on else "Click picks: Pieces"
	if layer == 1:
		_set_hint("Click a room's navmesh to select it." if on else "")


# --- Keys ---------------------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	var handled := true
	if key.ctrl_pressed or key.meta_pressed:
		match key.keycode:
			KEY_S:
				save_level()
			KEY_N:
				dialogs.leave_level(dialogs.new_level)
			KEY_O:
				dialogs.leave_level(dialogs.welcome)
			KEY_E:
				export_level()
			KEY_Z:
				if doc:
					if key.shift_pressed:
						doc.redo()
					else:
						doc.undo()
			KEY_Y:
				if doc:
					doc.redo()
			KEY_D:
				duplicate_selected()
			_:
				handled = false
	elif doc == null or key.echo:
		handled = false
	elif view.is_flying() and key.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E]:
		handled = true  # flying with the right mouse button: these move the camera
	else:
		match key.keycode:
			KEY_1, KEY_2, KEY_3:
				set_layer(key.keycode - KEY_0)
			KEY_DELETE, KEY_BACKSPACE:
				delete_selected()
			KEY_Q:
				set_gizmo_mode(TransformGizmo.Mode.SELECT)
			KEY_W:
				set_gizmo_mode(TransformGizmo.Mode.MOVE)
			KEY_E:
				set_gizmo_mode(TransformGizmo.Mode.ROTATE)
			KEY_R:
				if view.is_placing():
					view.rotate_placing(-90.0 if key.shift_pressed else 90.0)
				else:
					set_gizmo_mode(TransformGizmo.Mode.SCALE)
			KEY_N:
				set_pick_rooms(not view.pick_rooms)
			KEY_F:
				view.focus(doc.selected)
			KEY_T:
				set_local(not view.gizmo.local)
			KEY_O, KEY_KP_5:
				set_ortho(not view.ortho)
			KEY_KP_7:
				toggle_top()
			KEY_PAGEUP:
				raise_selected(0.5)
			KEY_PAGEDOWN:
				raise_selected(-0.5)
			KEY_F5:
				playtest()
			KEY_ESCAPE:
				if view.is_placing():
					view.cancel_place()
					_set_hint("")
				else:
					doc.select("")
			_:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()
