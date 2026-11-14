class_name Palette
extends VBoxContainer
## The left-hand panel: the things you can place on the current layer, as a
## tree. Click one, then click in the view (materials: click pieces to paint).
##
## On the Map layer it has six categories: Shapes, Decorations, Prefabs,
## Materials, Invisible and Effects. Your imported models (Decorations,
## Prefabs) and materials can be sorted into folders you name, nested as deep
## as you like. Right-click anything for its options; drag models and
## materials onto a folder to move them. Collapsed categories and folders
## stay collapsed (remembered between sessions).

const COLLAPSED_KEY := "palette_collapsed"
const CATEGORY_COLOR := Color(0.65, 0.85, 1.0)
const FOLDER_COLOR := Color(0.85, 0.8, 0.6)
const ACTION_COLOR := Color(0.6, 0.75, 0.6)

var app: Node
var _search: LineEdit
var _tree: Tree
var _wave_row: HBoxContainer
var _wave: SpinBox
var _menu: PopupMenu
var _menu_actions: Array[Callable] = []
var _signature := ""
var _filling := false


func _init() -> void:
	custom_minimum_size.x = 230
	var title := Label.new()
	title.text = "Place"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search..."
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: refresh(true))
	add_child(_search)
	_wave_row = HBoxContainer.new()
	var wave_label := Label.new()
	wave_label.text = "Into wave"
	wave_label.tooltip_text = "Enemies you place inside a room join this wave of that room. A number past the room's last wave adds a new wave."
	wave_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_wave_row.add_child(wave_label)
	_wave = SpinBox.new()
	_wave.min_value = 1
	_wave.max_value = 30
	_wave.value = 1
	_wave.tooltip_text = wave_label.tooltip_text
	_wave.value_changed.connect(func(v: float) -> void: app.place_wave = int(v))
	_wave_row.add_child(_wave)
	add_child(_wave_row)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.allow_search = false
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.select_mode = Tree.SELECT_ROW
	_tree.allow_rmb_select = true
	_tree.item_selected.connect(_on_selected)
	_tree.item_mouse_selected.connect(_on_mouse)
	_tree.item_collapsed.connect(_on_collapsed)
	_tree.set_drag_forwarding(_drag_data, _can_drop, _drop)
	add_child(_tree)
	_menu = PopupMenu.new()
	_menu.index_pressed.connect(func(i: int) -> void:
		if i < _menu_actions.size() and _menu_actions[i].is_valid():
			_menu_actions[i].call())
	add_child(_menu)


func set_wave(n: int) -> void:
	_wave.set_value_no_signal(n)


## Rebuilds the tree, unless nothing it shows has changed (so moving pieces
## around doesn't reset its scroll). `force` rebuilds anyway.
func refresh(force := false) -> void:
	if app.doc == null:
		_tree.clear()
		_signature = ""
		return
	var level: LevelData = app.doc.level
	var sig := "%d|%s|%s|%s|%s" % [app.layer, _search.text, str(level.map.assets.hash()),
		str(level.map.get("materials", []).hash()), str(level.map.get("folders", {}).hash())]
	if sig == _signature and not force:
		return
	_signature = sig
	_build()


func _build() -> void:
	_filling = true
	_tree.clear()
	var root := _tree.create_item()
	var layer: int = app.layer
	_wave_row.visible = layer == 3
	var filter := _search.text.strip_edges().to_lower()
	var collapsed: Array = AppSettings.get_value(COLLAPSED_KEY, [])
	var entries := Catalog.palette(layer, app.doc)
	var groups := []
	for e in entries:
		if not groups.has(e.group):
			groups.append(e.group)
	if layer == 1:
		groups = Catalog.GROUP_ORDER.duplicate()
	for group in groups:
		var library := ""
		for key in Catalog.LIBRARY_GROUPS:
			if Catalog.LIBRARY_GROUPS[key] == group:
				library = key
		var mine := entries.filter(func(e): return e.group == group and (filter == "" or String(e.title).to_lower().contains(filter)))
		if filter != "" and mine.is_empty():
			continue
		var head := _row(root, group, {"type": "category", "group": group, "library": library}, CATEGORY_COLOR)
		head.collapsed = filter == "" and collapsed.has(group)
		var folders := {}  # path -> TreeItem
		if library != "":
			for path in app.doc.library_folders(library):
				var parent: TreeItem = head
				var parts := String(path).split("/", false)
				var so_far := ""
				for part in parts:
					so_far = part if so_far == "" else so_far + "/" + part
					if not folders.has(so_far):
						var f := _row(parent, part, {"type": "folder", "library": library, "path": so_far, "group": group}, FOLDER_COLOR)
						f.collapsed = filter == "" and collapsed.has(group + "/" + so_far)
						folders[so_far] = f
					parent = folders[so_far]
		for e in mine:
			var parent: TreeItem = folders.get(String(e.get("folder", "")), head)
			var row := _row(parent, e.title, {"type": "entry", "entry": e}, Color(1, 1, 1))
			row.set_tooltip_text(0, e.tip)
		if library != "" and filter == "":
			var label: String = {"decoration": "+ Import a model...", "prefab": "+ Import a model...", "material": "+ New material from an image..."}[library]
			_row(head, label, {"type": "action", "library": library, "path": ""}, ACTION_COLOR)
		# Hide folders the search left empty.
		if filter != "":
			for path in folders:
				if folders[path].get_child_count() == 0:
					folders[path].visible = false
	if layer == 1 and filter == "":
		_row(root, "Select the start point", {"type": "start"}, ACTION_COLOR).set_tooltip_text(0, "Where Seekers arrive. Drag it to move it.")
	_filling = false


func _row(parent: TreeItem, text: String, meta: Dictionary, color: Color) -> TreeItem:
	var it := _tree.create_item(parent)
	it.set_text(0, text)
	it.set_metadata(0, meta)
	it.set_custom_color(0, color)
	if meta.type == "category" or meta.type == "folder":
		it.set_selectable(0, false)
	return it


## Un-selects the entry (placing stopped).
func clear_pressed() -> void:
	_tree.deselect_all()


func _on_selected() -> void:
	if _filling:
		return
	var it := _tree.get_selected()
	if it == null:
		return
	var meta: Dictionary = it.get_metadata(0)
	match String(meta.type):
		"entry":
			app.begin_place(meta.entry)
		"action":
			_tree.deselect_all.call_deferred()
			_new_in(String(meta.library), String(meta.path))
		"start":
			_tree.deselect_all.call_deferred()
			app.doc.select(EditorDoc.START)
			app.view.focus(EditorDoc.START)


## A click on a category or folder opens or closes it; a right-click opens
## its menu.
func _on_mouse(at: Vector2, button: int) -> void:
	var it := _tree.get_item_at_position(at)
	if it == null:
		return
	var meta: Dictionary = it.get_metadata(0)
	if button == MOUSE_BUTTON_RIGHT:
		_open_menu(it, meta)
	elif meta.type == "category" or meta.type == "folder":
		it.collapsed = not it.collapsed


func _on_collapsed(it: TreeItem) -> void:
	if _filling or _search.text.strip_edges() != "":
		return
	var meta: Dictionary = it.get_metadata(0)
	var key := ""
	if meta.type == "category":
		key = String(meta.group)
	elif meta.type == "folder":
		key = String(meta.group) + "/" + String(meta.path)
	if key == "":
		return
	var list: Array = AppSettings.get_value(COLLAPSED_KEY, [])
	list = list.duplicate()
	if it.collapsed and not list.has(key):
		list.append(key)
	elif not it.collapsed:
		list.erase(key)
	AppSettings.set_value(COLLAPSED_KEY, list)


# --- Right-click menus ---------------------------------------------------------------------------

func _open_menu(it: TreeItem, meta: Dictionary) -> void:
	_menu.clear()
	_menu_actions.clear()
	var doc: EditorDoc = app.doc
	match String(meta.type):
		"category", "folder":
			var library := String(meta.get("library", ""))
			var path := String(meta.get("path", ""))
			if library != "":
				_item("New folder here..." if meta.type == "folder" else "New folder...", func() -> void: _new_folder(library, path))
				_item("Import a model here..." if library != "material" else "New material from an image here...", func() -> void: _new_in(library, path))
				if library == "material":
					_item("New plain-color material here...", func() -> void: app.dialogs.material_dialog("", "", path))
			if meta.type == "folder":
				_menu.add_separator()
				_menu_actions.append(Callable())
				_item("Rename folder...", func() -> void: _rename_folder(library, path))
				_item("Delete folder (keeps what's in it)", func() -> void:
					doc.delete_folder(library, path)
					doc.commit())
			_menu.add_separator()
			_menu_actions.append(Callable())
			_item("Open everything inside", func() -> void: _set_collapsed(it, false))
			_item("Close everything inside", func() -> void: _set_collapsed(it, true))
		"entry":
			var e: Dictionary = meta.entry
			if not e.has("library"):
				return
			var library := String(e.library)
			var id := String(e.id)
			var data := doc.level.find_material(id) if library == "material" else doc.level.find_asset(id)
			if library == "material":
				_item("Edit material...", func() -> void: app.dialogs.material_dialog(id))
			else:
				_item("Model settings...", func() -> void: app.dialogs.models())
				var other := "prefab" if library == "decoration" else "decoration"
				_item("Move to %s" % Catalog.LIBRARY_GROUPS[other], func() -> void:
					data.category = other
					doc.set_folder(data, "")
					doc.commit())
			var move := PopupMenu.new()
			move.name = "MoveMenu"
			var targets := [""]
			targets.append_array(doc.library_folders(library))
			for t in targets:
				move.add_item("(top of %s)" % Catalog.LIBRARY_GROUPS[library] if t == "" else String(t))
			move.index_pressed.connect(func(i: int) -> void:
				doc.set_folder(data, String(targets[i]))
				doc.commit())
			for child in _menu.get_children():
				if child is PopupMenu:
					_menu.remove_child(child)
					child.queue_free()
			_menu.add_child(move)
			_menu.add_submenu_node_item("Move to folder", move)
			_menu_actions.append(Callable())
			_item("New folder for it...", func() -> void:
				app.dialogs.ask_text("New folder", "Folder name (use / for a folder inside a folder):", String(data.get("folder", "")),
					func(text: String) -> void:
						var path := doc.add_folder(library, text)
						if path != "":
							doc.set_folder(data, path)
							doc.commit()))
			_menu.add_separator()
			_menu_actions.append(Callable())
			if library == "material":
				_item("Delete material", func() -> void:
					var uses := doc.uses_of_material(id)
					var go := func() -> void:
						doc.remove_material(id)
						doc.commit()
					if uses == 0:
						go.call()
					else:
						app.dialogs.ask("Delete %s?" % e.title, "%d piece%s painted with it go back to their plain color." % [uses, "" if uses == 1 else "s"], "Delete", go))
			else:
				var uses := doc.uses_of_asset(id)
				_item("Remove from the level" if uses == 0 else "Remove from the level (used %d times)" % uses, func() -> void:
					if uses > 0:
						app.dialogs.tell("It's in use", "%d piece%s use %s. Delete them first (the outline lists them), then remove the model." % [uses, "" if uses == 1 else "s", e.title])
						return
					doc.level.map.assets.erase(data)
					doc.commit())
		_:
			return
	_menu.position = Vector2i(get_screen_position() + get_local_mouse_position())
	_menu.reset_size()
	_menu.popup()


func _item(text: String, action: Callable) -> void:
	_menu.add_item(text)
	_menu_actions.append(action)


func _set_collapsed(it: TreeItem, closed: bool) -> void:
	it.set_collapsed_recursive(closed)
	if not closed:
		it.collapsed = false
	var list: Array = (AppSettings.get_value(COLLAPSED_KEY, []) as Array).duplicate()
	var stack := [it]
	while not stack.is_empty():
		var node: TreeItem = stack.pop_back()
		var meta: Dictionary = node.get_metadata(0)
		var key := ""
		if meta.type == "category":
			key = String(meta.group)
		elif meta.type == "folder":
			key = String(meta.group) + "/" + String(meta.path)
		if key != "":
			list.erase(key)
			if closed:
				list.append(key)
		for c in node.get_children():
			stack.append(c)
	AppSettings.set_value(COLLAPSED_KEY, list)


func _new_folder(library: String, parent: String) -> void:
	var doc: EditorDoc = app.doc
	app.dialogs.ask_text("New folder", "Folder name:", "", func(text: String) -> void:
		var path := doc.add_folder(library, parent.path_join(text) if parent != "" else text)
		if path != "":
			doc.commit())


func _rename_folder(library: String, path: String) -> void:
	var doc: EditorDoc = app.doc
	app.dialogs.ask_text("Rename folder", "New name (use / to move it inside another folder):", path, func(text: String) -> void:
		doc.rename_folder(library, path, text)
		doc.commit())


## Imports a model, or starts a material, into a category and folder.
func _new_in(library: String, path: String) -> void:
	if library == "material":
		app.dialogs.import_material(path)
	else:
		app.dialogs.import_model(library, path)


# --- Dragging models and materials into folders ---------------------------------------------------

func _drag_data(at: Vector2) -> Variant:
	var it := _tree.get_item_at_position(at)
	if it == null:
		return null
	var meta: Dictionary = it.get_metadata(0)
	if meta.type != "entry" or not (meta.entry as Dictionary).has("library"):
		return null
	var label := Label.new()
	label.text = "  " + String(meta.entry.title)
	set_drag_preview(label)
	_tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM
	return {"palette_entry": meta.entry}


func _can_drop(at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or not data.has("palette_entry"):
		return false
	var target := _drop_target(at, data)
	return not target.is_empty()


func _drop(at: Vector2, data: Variant) -> void:
	_tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
	var target := _drop_target(at, data)
	if target.is_empty():
		return
	var e: Dictionary = data.palette_entry
	var doc: EditorDoc = app.doc
	var entry := doc.level.find_material(String(e.id)) if e.library == "material" else doc.level.find_asset(String(e.id))
	if entry.is_empty():
		return
	if e.library != "material":
		entry.category = target.library
	doc.set_folder(entry, String(target.path))
	doc.commit()


## Where a drop lands: {"library", "path"} (a folder, or a category's top),
## or {} if it can't go there. Models move between Decorations and Prefabs;
## materials stay in Materials.
func _drop_target(at: Vector2, data: Dictionary) -> Dictionary:
	var it := _tree.get_item_at_position(at)
	if it == null:
		return {}
	var meta: Dictionary = it.get_metadata(0)
	var library := String(meta.get("library", ""))
	var path := String(meta.get("path", ""))
	if meta.type == "entry":
		var e: Dictionary = meta.entry
		if not e.has("library"):
			return {}
		library = String(e.library)
		path = String(e.get("folder", ""))
	elif meta.type != "category" and meta.type != "folder":
		return {}
	var moving: Dictionary = data.palette_entry
	if library == "" or (library == "material") != (moving.library == "material"):
		return {}
	return {"library": library, "path": path}


# --- For tests ---------------------------------------------------------------------------------

## The tree's rows as text, indented by depth (hidden rows left out).
func outline_text() -> PackedStringArray:
	var out := PackedStringArray()
	var root := _tree.get_root()
	if root == null:
		return out
	var walk := func(walk_self: Callable, it: TreeItem, depth: int) -> void:
		if not it.visible:
			return
		out.append("  ".repeat(depth) + it.get_text(0) + (" [closed]" if it.collapsed and it.get_child_count() > 0 else ""))
		if not it.collapsed:
			for c in it.get_children():
				walk_self.call(walk_self, c, depth + 1)
	for c in root.get_children():
		walk.call(walk, c, 0)
	return out


## The row for a category, folder ("Prefabs/Trees") or entry title.
func find_row(label: String) -> TreeItem:
	var stack: Array = [_tree.get_root()]
	while not stack.is_empty():
		var it: TreeItem = stack.pop_back()
		if it == null:
			continue
		var meta = it.get_metadata(0)
		if meta is Dictionary:
			var key := String(it.get_text(0))
			if meta.type == "folder":
				key = String(meta.group) + "/" + String(meta.path)
			if key == label:
				return it
		for c in it.get_children():
			stack.append(c)
	return null
