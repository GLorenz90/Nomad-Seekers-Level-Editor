class_name EditorDoc
extends RefCounted
## The level being edited: its data (LevelData), the selection, undo / redo,
## and every change the editor can make to it. Views listen to `changed`
## and redraw from the data.
##
## Kinds of item: "start", "piece", "wall", "boundary", "decoration", "area"
## (Layer 1), "object" (Layer 2) and "enemy" (Layer 3). Every item is found by
## its id. Areas (rooms and corridors) aren't placed: they're the pieces of
## the navmesh, found by update_nav() (LevelNav).

signal changed
signal selection_changed
## The navmesh was baked again (and areas may have come or gone).
signal nav_updated

const START := "start"
const MAP_LISTS := {"piece": "pieces", "wall": "walls", "boundary": "boundaries",
	"decoration": "decorations", "area": "areas"}
const KIND_LAYER := {"start": 1, "piece": 1, "wall": 1, "boundary": 1, "decoration": 1, "area": 1,
	"object": 2, "enemy": 3}
const UNDO_LIMIT := 100

var level: LevelData
var selected := ""
var dirty := false
var _states: Array = []
var _index := -1
var _last_key := ""
var _last_time := 0
## The walkable navmesh (uncut) and the pieces of the boundary-cut one, each
## with its "area" id: {"mesh": NavigationMesh, "islands": [...]}.
var nav := {}
var nav_stale := true
## The quest this level belongs to (its nomad2/ or levels/<name>/), or null.
var quest: QuestDoc
## A quest's Nomad-2 additions (level.json kind "nomad2") sit on a read-only
## copy of Nomad-2 (catalog/nomad2_base.json): its pieces, signs and spots.
var base := {}

const NOMAD2_BASE := "res://catalog/nomad2_base.json"
static var _nomad2_cache := {}


# --- Opening and saving -----------------------------------------------------------------------

static func create(level_name: String, area: String, dir: String, kind := "level") -> EditorDoc:
	var doc := EditorDoc.new()
	doc.level = LevelData.create(level_name, area)
	doc.level.dir = dir
	if kind != "level":
		doc.level.meta.kind = kind
	doc._attach()
	doc._reset_history()
	return doc


## Opens a level folder; null if there's no level in it.
static func open(dir: String) -> EditorDoc:
	var data := LevelData.load_dir(dir)
	if data == null:
		return null
	var doc := EditorDoc.new()
	doc.level = data
	doc._attach()
	doc._reset_history()
	return doc


## Finds the level's quest and, for a Nomad-2 overlay, Nomad-2's copy.
func _attach() -> void:
	quest = QuestDoc.find_for(level.dir)
	base = nomad2_base() if is_nomad2() else {}


func is_nomad2() -> bool:
	return String(level.meta.get("kind", "level")) == "nomad2"


## The read-only copy of Nomad-2 ({} if the file is missing).
static func nomad2_base() -> Dictionary:
	if _nomad2_cache.is_empty() and FileAccess.file_exists(NOMAD2_BASE):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(NOMAD2_BASE))
		if parsed is Dictionary:
			_nomad2_cache = parsed
	return _nomad2_cache


## Nomad-2's own pieces (empty for ordinary levels).
func base_pieces() -> Array:
	return base.get("pieces", [])


## Every solid piece to stand things on: the level's and Nomad-2's.
func solid_pieces() -> Array:
	return base_pieces() + level.map.pieces


## The level the navmesh is baked from: Nomad-2's pieces under an overlay.
## Its areas are its own (an overlay keeps no rooms).
func nav_level() -> LevelData:
	if base_pieces().is_empty():
		return level
	var copy := LevelData.new()
	copy.dir = level.dir
	copy.meta = level.meta
	copy.map = level.map.duplicate()
	copy.map.pieces = base_pieces() + level.map.pieces
	copy.map.areas = []
	copy.interaction = level.interaction
	copy.combat = level.combat
	return copy


func save() -> Error:
	update_nav()  # saves each area's navmesh polygons for the game
	var err := level.save_dir(level.dir)
	if err == OK:
		dirty = false
		changed.emit()
	return err


## A folder name for a level name: "Glade of Echoes" -> "glade_of_echoes".
static func slug(text: String) -> String:
	var out := ""
	for ch in text.to_lower().strip_edges():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif out != "" and not out.ends_with("_"):
			out += "_"
	out = out.trim_suffix("_")
	return out if out != "" else "level"


# --- Undo and redo ----------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	return {"meta": level.meta.duplicate(true), "map": level.map.duplicate(true),
		"interaction": level.interaction.duplicate(true), "combat": level.combat.duplicate(true)}


func _reset_history() -> void:
	normalize()
	_states = [_snapshot()]
	_index = 0
	dirty = false


## Call after changing the data. Edits with the same `key` made within a
## moment of each other (dragging a slider, typing) undo as one step.
func commit(key := "") -> void:
	nav_stale = true
	normalize()
	var now := Time.get_ticks_msec()
	if key != "" and key == _last_key and now - _last_time < 1500 and _index > 0:
		_states[_index] = _snapshot()
	else:
		_states.resize(_index + 1)
		_states.append(_snapshot())
		if _states.size() > UNDO_LIMIT:
			_states.pop_front()
		_index = _states.size() - 1
	_last_key = key
	_last_time = now
	dirty = true
	changed.emit()


func can_undo() -> bool:
	return _index > 0


func can_redo() -> bool:
	return _index < _states.size() - 1


func undo() -> void:
	if can_undo():
		_index -= 1
		_restore()


func redo() -> void:
	if can_redo():
		_index += 1
		_restore()


func _restore() -> void:
	var s: Dictionary = _states[_index]
	level.meta = s.meta.duplicate(true)
	level.map = s.map.duplicate(true)
	level.interaction = s.interaction.duplicate(true)
	level.combat = s.combat.duplicate(true)
	_last_key = ""
	dirty = true
	nav_stale = true
	if selected != "" and kind_of(selected) == "":
		selected = ""
		selection_changed.emit()
	changed.emit()


# --- Finding things ---------------------------------------------------------------------------

func select(id: String) -> void:
	if id != selected:
		selected = id
		selection_changed.emit()


## Every item you can select: [{id, kind, data}].
func items() -> Array:
	var out := [{"id": START, "kind": "start", "data": level.map.start}]
	for kind in MAP_LISTS:
		for d in level.map[MAP_LISTS[kind]]:
			out.append({"id": String(d.get("id", "")), "kind": kind, "data": d})
	for d in level.interaction.objects:
		out.append({"id": String(d.get("id", "")), "kind": "object", "data": d})
	for d in level.placements():
		out.append({"id": String(d.get("id", "")), "kind": "enemy", "data": d})
	return out


func item(id: String) -> Dictionary:
	if id == "":
		return {}
	for it in items():
		if it.id == id:
			return it
	return {}


func find(id: String) -> Dictionary:
	return item(id).get("data", {})


func kind_of(id: String) -> String:
	return String(item(id).get("kind", ""))


## A readable name for anything with an id (items, button groups, dialogues).
func label_of(id: String) -> String:
	var it := item(id)
	if not it.is_empty():
		return Catalog.label(it.kind, it.data, id)
	for g in level.interaction.button_groups:
		if String(g.get("id", "")) == id:
			return "Button group (%s)" % id
	for d in level.interaction.dialogues:
		if String(d.get("id", "")) == id:
			return "Dialogue (%s)" % id
	return "%s (missing)" % id


func position_of(id: String) -> Vector3:
	var it := item(id)
	if not it.is_empty():
		return Items.get_pos(it.kind, it.data)
	for g in level.interaction.button_groups:
		if String(g.get("id", "")) == id and not (g.get("buttons", []) as Array).is_empty():
			return position_of(String(g.buttons[0]))
	return Vector3.INF


func new_id(prefix: String) -> String:
	var taken := level.ids()
	taken[START] = true
	var n := 1
	while taken.has("%s_%d" % [prefix, n]):
		n += 1
	return "%s_%d" % [prefix, n]


## The room or corridor (navmesh area) a point stands in ("" if none).
## `rooms_only` skips corridors.
func room_at(point: Vector3, rooms_only := false) -> String:
	if nav_stale:
		update_nav()
	for a in level.map.areas:
		if rooms_only and String(a.get("kind", "room")) != "room":
			continue
		if LevelData.area_contains(a, point):
			return String(a.get("id", ""))
	return ""


## Bakes the navmesh again (if anything changed since the last bake) and
## matches its pieces to the level's areas: new pieces become new rooms,
## areas whose piece is gone are dropped. Not an undo step: it follows the
## pieces, which are.
func update_nav(force := false) -> void:
	if not nav_stale and not force:
		return
	nav_stale = false
	var source := nav_level()
	var parts := LevelNav.collect(source, model_loader())
	var mesh := LevelNav.bake(source, Callable(), false, parts)
	var cut := LevelNav.bake(source, Callable(), true, parts)
	var before: int = level.map.areas.size()
	var found := LevelNav.assign_areas(source, cut)
	nav = {"mesh": mesh, "islands": found.islands, "added": found.added, "removed": found.removed}
	if not found.added.is_empty() or not found.removed.is_empty() or before != level.map.areas.size():
		if selected != "" and kind_of(selected) == "":
			selected = ""
			selection_changed.emit()
	nav_updated.emit()


## Loads imported models for the navmesh (glTF, cached).
func model_loader() -> Callable:
	return func(asset_id: String) -> Node3D: return Models.instance(level, asset_id)


# --- Library folders (the Place list's Decorations, Prefabs and Materials) --------------------
# Imported models and materials can live in folders the builder names, nested
# with "/" ("Forest/Trees"). Each model or material keeps its "folder"; empty
# folders are remembered in map.folders. The game ignores both.

const LIBRARY := ["decoration", "prefab", "material"]


## The category an imported model or material is in.
func library_category(entry: Dictionary, is_material := false) -> String:
	if is_material:
		return "material"
	var c := String(entry.get("category", "prefab"))
	return c if c in ["decoration", "prefab"] else "prefab"


## Models and materials in a category: [{"id", "folder", "data", "material"}].
func library_items(category: String) -> Array:
	var out := []
	if category == "material":
		for m in level.map.get("materials", []):
			out.append({"id": String(m.id), "folder": String(m.get("folder", "")), "data": m, "material": true})
	else:
		for a in level.map.assets:
			if library_category(a) == category:
				out.append({"id": String(a.id), "folder": String(a.get("folder", "")), "data": a, "material": false})
	return out


## Every folder path in a category, parents included, sorted.
func library_folders(category: String) -> Array:
	var found := {}
	var stored: Array = level.map.get("folders", {}).get(category, [])
	var all := stored.duplicate()
	for it in library_items(category):
		all.append(it.folder)
	for path in all:
		var parts := String(path).split("/", false)
		for i in parts.size():
			found["/".join(parts.slice(0, i + 1))] = true
	var out := found.keys()
	out.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
	return out


static func clean_folder(path: String) -> String:
	var parts := []
	for part in path.replace("\\", "/").split("/", false):
		var t := String(part).strip_edges()
		if t != "":
			parts.append(t)
	return "/".join(parts)


func add_folder(category: String, path: String) -> String:
	path = clean_folder(path)
	if path == "":
		return ""
	if not level.map.has("folders") or not (level.map.folders is Dictionary):
		level.map.folders = {}
	var list: Array = level.map.folders.get(category, [])
	if not list.has(path):
		list.append(path)
	level.map.folders[category] = list
	return path


## Renames (or moves) a folder and everything under it.
func rename_folder(category: String, old: String, new_path: String) -> void:
	new_path = clean_folder(new_path)
	if new_path == "" or new_path == old:
		return
	var swap := func(path: String) -> String:
		if path == old:
			return new_path
		if path.begins_with(old + "/"):
			return new_path + path.substr(old.length())
		return path
	for it in library_items(category):
		if String(it.folder) != "":
			it.data.folder = swap.call(String(it.folder))
	var list: Array = level.map.get("folders", {}).get(category, [])
	for i in list.size():
		list[i] = swap.call(String(list[i]))
	add_folder(category, new_path)


## Deletes a folder: what was in it moves up to its parent.
func delete_folder(category: String, path: String) -> void:
	var parent := path.get_base_dir() if path.contains("/") else ""
	for it in library_items(category):
		var f := String(it.folder)
		if f == path or f.begins_with(path + "/"):
			var rest := f.substr(path.length()).trim_prefix("/")
			var moved := parent.path_join(rest) if parent != "" else rest
			if moved == "":
				it.data.erase("folder")
			else:
				it.data.folder = moved
	if level.map.has("folders") and level.map.folders is Dictionary:
		var kept := []
		for f in level.map.folders.get(category, []):
			var fs := String(f)
			if fs == path or fs.begins_with(path + "/"):
				var rest := fs.substr(path.length()).trim_prefix("/")
				if rest != "":
					kept.append(parent.path_join(rest) if parent != "" else rest)
			else:
				kept.append(fs)
		level.map.folders[category] = kept


## Puts a model or material in a folder ("" for the top of its category).
func set_folder(entry: Dictionary, path: String) -> void:
	path = clean_folder(path)
	if path == "":
		entry.erase("folder")
	else:
		entry.folder = path


## Removes a material; pieces painted with it go back to their color.
func remove_material(id: String) -> void:
	for p in level.map.pieces:
		if String(p.get("material", "")) == id:
			p.erase("material")
	_erase_id(level.map.materials, id)


## Pieces and decorations using an imported model.
func uses_of_asset(id: String) -> int:
	var n := 0
	for key in ["pieces", "decorations"]:
		for p in level.map[key]:
			if String(p.get("asset", "")) == id:
				n += 1
	return n


## The materials that came in with a model (imported with "Also add its
## materials"): marked from_model, or (older ones) named after it.
func materials_from_model(id: String) -> Array:
	return level.map.materials.filter(func(m):
		return String(m.get("from_model", "")) == id \
			or (not m.has("from_model") and String(m.get("id", "")).begins_with(id + "_") and String(m.get("folder", "")) == id.capitalize()))


## Takes imported models out of the level, with their placed copies and
## (with_materials) the materials that came with them. Their files stay in
## assets/ (Undo can bring them back; export leaves unused files out).
## Returns {"models", "placed", "materials"} counts.
func remove_assets(ids: Array, with_materials := true) -> Dictionary:
	var out := {"models": 0, "placed": 0, "materials": 0}
	for id in ids:
		var asset := level.find_asset(String(id))
		if asset.is_empty():
			continue
		for key in ["pieces", "decorations"]:
			var kept := []
			for p in level.map[key]:
				if String(p.get("asset", "")) == String(id):
					out.placed += 1
					if selected == String(p.get("id", "")):
						selected = ""
				else:
					kept.append(p)
			level.map[key] = kept
		if with_materials:
			for m in materials_from_model(String(id)):
				remove_material(String(m.id))
				out.materials += 1
		level.map.assets.erase(asset)
		out.models += 1
	return out


## Deletes a Place list folder with everything in it (and in the folders
## inside it): models with their placed copies and materials, or materials.
## Returns the counts (see remove_assets).
func delete_folder_contents(category: String, path: String) -> Dictionary:
	var inside := library_items(category).filter(func(it):
		var f := String(it.folder)
		return path == "" or f == path or f.begins_with(path + "/"))
	var out := {"models": 0, "placed": 0, "materials": 0}
	if category == "material":
		for it in inside:
			remove_material(String(it.id))
			out.materials += 1
	else:
		out = remove_assets(inside.map(func(it): return String(it.id)))
	delete_folder(category, path)
	return out


## Pieces painted with a material.
func uses_of_material(id: String) -> int:
	var n := 0
	for p in level.map.pieces:
		if String(p.get("material", "")) == id:
			n += 1
	return n


## Joins another area into this one (a room split by a pit or a low wall):
## its pieces of navmesh count as this area, and whatever pointed at it now
## points here. Its fight, if any, is dropped when this area has one.
func join_areas(keep: String, other: String) -> void:
	var a := level.find_area(keep)
	var b := level.find_area(other)
	if a.is_empty() or b.is_empty() or keep == other:
		return
	var also: Array = a.get("also", [])
	also.append(b.get("seed"))
	also.append_array(b.get("also", []))
	a.also = also
	var fight_b := level.combat_room(other)
	if not fight_b.is_empty():
		if level.combat_room(keep).is_empty():
			fight_b.room = keep
		else:
			for w in fight_b.get("waves", []):
				level.combat.free.append_array(w.get("enemies", []))
			level.combat.rooms.erase(fight_b)
	_erase_id(level.map.areas, other)
	_repoint(other, keep)
	nav_stale = true


## Splits off the pieces this area took in with join_areas: they become
## areas of their own again on the next bake.
func split_area(id: String) -> void:
	var a := level.find_area(id)
	a.erase("also")
	nav_stale = true


# --- Adding, removing, renaming ---------------------------------------------------------------

## Adds an item and returns its id. Enemies go into `wave` (0 = first) of
## the room they stand in, or outside waves when they aren't in a room.
func add(kind: String, data: Dictionary, wave := 0) -> String:
	var d := data.duplicate(true)
	d.id = new_id(Catalog.id_prefix(kind, d))
	match kind:
		"piece", "wall", "boundary", "decoration":
			level.map[MAP_LISTS[kind]].append(d)
		"object":
			level.interaction.objects.append(d)
		"enemy":
			var room := room_at(LevelData.vec3(d.get("pos")), true)
			_insert_enemy(d, room, wave)
	return String(d.id)


func remove(id: String) -> void:
	var kind := kind_of(id)
	match kind:
		"area":
			return  # areas come from the navmesh: split or remove floors instead
		"piece", "wall", "boundary", "decoration":
			_erase_id(level.map[MAP_LISTS[kind]], id)
		"object":
			_erase_id(level.interaction.objects, id)
			for g in level.interaction.button_groups:
				(g.buttons as Array).erase(id)
		"enemy":
			_take_enemy(id)
	if selected == id:
		select("")


func duplicate_item(id: String) -> String:
	var it := item(id)
	if it.is_empty() or it.kind == "start" or it.kind == "area":
		return ""
	var d: Dictionary = (it.data as Dictionary).duplicate(true)
	var step := maxf(Items.local_aabb(it.kind, d, level).size.x, 1.0)
	Items.set_pos(it.kind, d, Items.get_pos(it.kind, d) + Vector3(step, 0, 0))
	var slot := enemy_slot(id)
	return add(it.kind, d, int(slot.get("wave", 0)))


static func _erase_id(list: Array, id: String) -> void:
	for i in list.size():
		if String(list[i].get("id", "")) == id:
			list.remove_at(i)
			return


## "" when renamed, or why not.
func rename(old: String, new_id_text: String) -> String:
	var id := new_id_text.strip_edges().to_lower().replace(" ", "_")
	if id == old:
		return ""
	if id == "" or id == START:
		return "That id can't be used."
	for ch in id:
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"):
			return "Ids use only letters, numbers and underscores."
	if level.ids().has(id):
		return "Something else is already called \"%s\"." % id
	var d := find(old)
	var is_group := false
	if d.is_empty():
		for list in [level.interaction.button_groups, level.interaction.dialogues]:
			for entry in list:
				if String(entry.get("id", "")) == old:
					d = entry
					is_group = true
	if d.is_empty():
		return "Nothing is called \"%s\"." % old
	d.id = id
	_repoint(old, id)
	if selected == old and not is_group:
		selected = id
	return ""


## Points everything that mentioned `old` at `id` instead.
func _repoint(old: String, id: String) -> void:
	for o in level.interaction.objects:
		for key in ["open_when_cleared", "shut_during_combat"]:
			if String(o.get(key, "")) == old:
				o[key] = id
	for g in level.interaction.button_groups:
		var buttons: Array = g.get("buttons", [])
		for i in buttons.size():
			if String(buttons[i]) == old:
				buttons[i] = id
	for c in level.combat.rooms:
		if String(c.get("room", "")) == old:
			c.room = id
	for rule in level.interaction.rules:
		if String(rule.get("when", {}).get("source", "")) == old:
			rule.when.source = id
		for a in rule.get("do", []):
			if String(a.get("target", "")) == old:
				a.target = id


## What else mentions an id, in plain words (shown before deleting).
func references(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for rule in level.interaction.rules:
		var used := String(rule.get("when", {}).get("source", "")) == id
		for a in rule.get("do", []):
			used = used or String(a.get("target", "")) == id
		if used:
			out.append("Trigger: " + Wiring.describe(rule, self))
	for o in level.interaction.objects:
		if String(o.get("open_when_cleared", "")) == id:
			out.append("%s opens when this room is cleared" % label_of(String(o.id)))
		if String(o.get("shut_during_combat", "")) == id:
			out.append("%s shuts while this room fights" % label_of(String(o.id)))
	var c := level.combat_room(id)
	if not c.is_empty():
		out.append("Its fight (%d wave(s)); the enemies stay, outside waves" % (c.get("waves", []) as Array).size())
	return out


# --- Enemies and waves ------------------------------------------------------------------------

## Where an enemy is: {"room": id, "wave": index}, or {"room": "", "wave": -1}
## when it isn't in a wave. {} if there's no such enemy.
func enemy_slot(id: String) -> Dictionary:
	for c in level.combat.rooms:
		var waves: Array = c.get("waves", [])
		for w in waves.size():
			for e in waves[w].get("enemies", []):
				if String(e.get("id", "")) == id:
					return {"room": String(c.get("room", "")), "wave": w}
	for e in level.combat.free:
		if String(e.get("id", "")) == id:
			return {"room": "", "wave": -1}
	return {}


## Moves an enemy into a room's wave (a wave index past the end adds a
## wave), or out of waves with room "".
func set_enemy_slot(id: String, room: String, wave: int) -> void:
	var d := _take_enemy(id)
	if not d.is_empty():
		_insert_enemy(d, room, wave)


func _take_enemy(id: String) -> Dictionary:
	for c in level.combat.rooms:
		var waves: Array = c.get("waves", [])
		for w in waves.size():
			var list: Array = waves[w].get("enemies", [])
			for i in list.size():
				if String(list[i].get("id", "")) == id:
					var d: Dictionary = list[i]
					list.remove_at(i)
					if list.is_empty():
						waves.remove_at(w)  # a wave emptied by moving or deleting goes too
					return d
	for i in level.combat.free.size():
		if String(level.combat.free[i].get("id", "")) == id:
			var d: Dictionary = level.combat.free[i]
			level.combat.free.remove_at(i)
			return d
	return {}


func _insert_enemy(d: Dictionary, room: String, wave: int) -> void:
	if room == "" or level.find_area(room).is_empty():
		level.combat.free.append(d)
		return
	var c := level.combat_room(room)
	if c.is_empty():
		c = {"room": room, "start": "enter", "waves": []}
		level.combat.rooms.append(c)
	var waves: Array = c.waves
	wave = clampi(wave, 0, waves.size())
	if wave == waves.size():
		waves.append({"enemies": []})
	waves[wave].enemies.append(d)


func add_wave(room: String) -> int:
	var c := level.combat_room(room)
	if c.is_empty():
		c = {"room": room, "start": "enter", "waves": []}
		level.combat.rooms.append(c)
	c.waves.append({"enemies": []})
	return (c.waves as Array).size() - 1


## After an enemy moved: if it's now standing in a different room than the
## one whose wave it's in, it joins that room (same wave number if there is
## one), or leaves waves when it's no longer in any room.
func settle_enemy(id: String) -> void:
	var slot := enemy_slot(id)
	var d := find(id)
	if slot.is_empty() or d.is_empty():
		return
	var here := room_at(LevelData.vec3(d.get("pos")), true)
	if String(slot.room) == "" and here == "":
		return
	if String(slot.room) != "" and here == String(slot.room):
		return
	if String(slot.room) == "" and here != "" and bool(d.get("loose", false)):
		return  # told to stay out of waves
	set_enemy_slot(id, here, maxi(int(slot.wave), 0))


# --- Buttons ----------------------------------------------------------------------------------

## The button group a button is in ({} if none).
func group_of(button_id: String) -> Dictionary:
	for g in level.interaction.button_groups:
		if (g.get("buttons", []) as Array).has(button_id):
			return g
	return {}


## What a "pressed" trigger names for a button: its group, else itself.
func press_source(button_id: String) -> String:
	var g := group_of(button_id)
	return String(g.id) if not g.is_empty() else button_id


## Puts a button in a group ("" = none, "+" = a new group). Returns the group id.
func set_group(button_id: String, group_id: String) -> String:
	var old_source := press_source(button_id)
	for g in level.interaction.button_groups:
		(g.buttons as Array).erase(button_id)
	if group_id == "+":
		group_id = new_id("group")
		level.interaction.button_groups.append({"id": group_id, "buttons": [], "once": true})
	for g in level.interaction.button_groups:
		if String(g.id) == group_id:
			g.buttons.append(button_id)
	# Triggers that listened to the button alone follow it into its group
	# (and back out), unless the old group still has buttons.
	var new_source := press_source(button_id)
	var old_group_left := false
	for g in level.interaction.button_groups:
		if String(g.id) == old_source and not (g.buttons as Array).is_empty():
			old_group_left = true
	if not old_group_left:
		for rule in level.interaction.rules:
			var when: Dictionary = rule.get("when", {})
			if String(when.get("event", "")) == "pressed" and String(when.get("source", "")) == old_source:
				when.source = new_source
	return group_id


# --- Keeping the data tidy ---------------------------------------------------------------------

## Runs after every change: rebuilds generated floors and walls, drops
## fights with no waves and button groups with no buttons, makes sure every
## flag a trigger uses exists, and keeps zone triggers matched to whether
## the zone waits for the whole party.
func normalize() -> void:
	var fights := []
	for c in level.combat.rooms:
		if not (c.get("waves", []) as Array).is_empty():
			fights.append(c)
	level.combat.rooms = fights
	var groups := []
	for g in level.interaction.button_groups:
		var members := []
		for b in g.get("buttons", []):
			if String(level.find_object(String(b)).get("type", "")) == "button":
				members.append(b)
		g.buttons = members
		if not members.is_empty():
			groups.append(g)
	level.interaction.button_groups = groups
	for rule in level.interaction.rules:
		var when: Dictionary = rule.get("when", {})
		if String(when.get("event", "")) in ["entered", "party_present"]:
			var zone := level.find_object(String(when.get("source", "")))
			if not zone.is_empty():
				when.event = "party_present" if bool(zone.get("whole_party", false)) else "entered"
		for c in rule.get("if", []):
			if String(c.get("check", "")) == "flag" and String(c.get("flag", "")) != "":
				if not level.interaction.flags.has(String(c.flag)):
					level.interaction.flags[String(c.flag)] = false
		for a in rule.get("do", []):
			if String(a.get("action", "")) == "set_flag" and String(a.get("flag", "")) != "":
				if not level.interaction.flags.has(String(a.flag)):
					level.interaction.flags[String(a.flag)] = false


# --- Triggers and dialogues -------------------------------------------------------------------

func new_rule_id() -> String:
	var taken := {}
	for rule in level.interaction.rules:
		taken[String(rule.get("id", ""))] = true
	var n := 1
	while taken.has("rule_%d" % n):
		n += 1
	return "rule_%d" % n


func find_rule(id: String) -> Dictionary:
	for rule in level.interaction.rules:
		if String(rule.get("id", "")) == id:
			return rule
	return {}


## Adds a trigger, or replaces the one with the same id.
func put_rule(rule: Dictionary) -> void:
	var rules: Array = level.interaction.rules
	for i in rules.size():
		if String(rules[i].get("id", "")) == String(rule.get("id", "")):
			rules[i] = rule
			return
	rules.append(rule)


func remove_rule(id: String) -> void:
	_erase_id(level.interaction.rules, id)


## Triggers that an item sets off, and triggers that act on it.
func rules_about(id: String) -> Dictionary:
	var from := []
	var onto := []
	var sources := [id]
	if kind_of(id) == "object" and String(find(id).get("type", "")) == "button":
		sources.append(press_source(id))
	for rule in level.interaction.rules:
		if String(rule.get("when", {}).get("source", "")) in sources:
			from.append(rule)
		for a in rule.get("do", []):
			if String(a.get("target", "")) == id and not onto.has(rule):
				onto.append(rule)
	return {"from": from, "onto": onto}


## A new dialogue with one empty line from `speaker`; returns its id.
func add_dialogue(speaker := "") -> String:
	var id := new_id("dialogue")
	level.interaction.dialogues.append({"id": id, "lines": [{"speaker": speaker, "text": ""}]})
	return id


func find_dialogue(id: String) -> Dictionary:
	for d in level.interaction.dialogues:
		if String(d.get("id", "")) == id:
			return d
	return {}
