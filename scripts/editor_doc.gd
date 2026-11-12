class_name EditorDoc
extends RefCounted
## The level being edited: its data (LevelData), the selection, undo / redo,
## and every change the editor can make to it. Views listen to `changed`
## and redraw from the data.
##
## Kinds of item: "start", "room", "piece", "wall", "decoration" (Layer 1),
## "object" (Layer 2) and "enemy" (Layer 3). Every item is found by its id.

signal changed
signal selection_changed

const START := "start"
const MAP_LISTS := {"room": "rooms", "piece": "pieces", "wall": "walls", "decoration": "decorations"}
const KIND_LAYER := {"start": 1, "room": 1, "piece": 1, "wall": 1, "decoration": 1, "object": 2, "enemy": 3}
const UNDO_LIMIT := 100

var level: LevelData
var selected := ""
var dirty := false
var _states: Array = []
var _index := -1
var _last_key := ""
var _last_time := 0


# --- Opening and saving -----------------------------------------------------------------------

static func create(level_name: String, size: String, area: String, dir: String) -> EditorDoc:
	var doc := EditorDoc.new()
	doc.level = LevelData.create(level_name, size, area)
	doc.level.dir = dir
	doc._reset_history()
	return doc


## Opens a level folder; null if there's no level in it.
static func open(dir: String) -> EditorDoc:
	var data := LevelData.load_dir(dir)
	if data == null:
		return null
	var doc := EditorDoc.new()
	doc.level = data
	doc._reset_history()
	return doc


func save() -> Error:
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
	if selected != "" and kind_of(selected) == "":
		selected = ""
		selection_changed.emit()
	changed.emit()


# --- Finding things ---------------------------------------------------------------------------

func select(id: String) -> void:
	if id != selected:
		selected = id
		selection_changed.emit()


## Every item you can select: [{id, kind, data}]. Generated floor and wall
## pieces belong to their room and aren't listed.
func items() -> Array:
	var out := [{"id": START, "kind": "start", "data": level.map.start}]
	for kind in MAP_LISTS:
		for d in level.map[MAP_LISTS[kind]]:
			if not d.has("generated_for"):
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


## The room or corridor whose footprint holds a point ("" if none).
## `rooms_only` skips corridors.
func room_at(point: Vector3, rooms_only := false) -> String:
	for r in level.map.rooms:
		if rooms_only and String(r.get("kind", "room")) != "room":
			continue
		var p := LevelData.vec3(r.get("pos"))
		var s := LevelData.vec3(r.get("size"), Vector3(16, 6, 16))
		if absf(point.x - p.x) <= s.x * 0.5 and absf(point.z - p.z) <= s.z * 0.5 \
				and point.y >= p.y - 2.0 and point.y <= p.y + s.y + 2.0:
			return String(r.get("id", ""))
	return ""


# --- Adding, removing, renaming ---------------------------------------------------------------

## Adds an item and returns its id. Enemies go into `wave` (0 = first) of
## the room they stand in, or outside waves when they aren't in a room.
func add(kind: String, data: Dictionary, wave := 0) -> String:
	var d := data.duplicate(true)
	d.id = new_id(Catalog.id_prefix(kind, d))
	match kind:
		"room", "piece", "wall", "decoration":
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
		"room", "piece", "wall", "decoration":
			_erase_id(level.map[MAP_LISTS[kind]], id)
			if kind == "room":
				var rooms := []
				for c in level.combat.rooms:
					if String(c.get("room", "")) != id:
						rooms.append(c)
					else:
						# Its enemies stay where they stand, outside waves.
						for w in c.get("waves", []):
							level.combat.free.append_array(w.get("enemies", []))
				level.combat.rooms = rooms
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
	if it.is_empty() or it.kind == "start":
		return ""
	var d: Dictionary = (it.data as Dictionary).duplicate(true)
	var step := 4.0 if it.kind == "room" else 1.0
	if it.kind == "room":
		step = LevelData.vec3(d.get("size"), Vector3(16, 6, 16)).x
		d.erase("name")
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
	for p in level.map.pieces:
		if String(p.get("generated_for", "")) == old:
			p.generated_for = id
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
	if selected == old and not is_group:
		selected = id
	return ""


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
	if room == "" or level.find_room(room).is_empty():
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
	RoomBuilder.rebuild(level)
	var fights := []
	for c in level.combat.rooms:
		if not (c.get("waves", []) as Array).is_empty() and not level.find_room(String(c.get("room", ""))).is_empty():
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


func find_dialogue(id: String) -> Dictionary:
	for d in level.interaction.dialogues:
		if String(d.get("id", "")) == id:
			return d
	return {}
