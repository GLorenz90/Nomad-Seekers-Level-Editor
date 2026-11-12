class_name LevelCheck
extends RefCounted
## The level check: everything that would cause trouble in the game, in
## plain words, each pointing at the thing to fix. It runs live in the
## Problems tab and again when exporting.
##
## Errors block exporting (the level would be broken or unbeatable).
## Warnings don't (something is probably a mistake, but the level works).
##
## Each problem: {"level": "error" | "warning", "text", "id", "layer"}.
## `id` is what to select ("" for the level as a whole).


static func run(doc: EditorDoc) -> Array:
	var out := []
	var level := doc.level
	_check_level(doc, out)
	_check_map(doc, out)
	_check_interaction(doc, out)
	_check_combat(doc, out)
	_check_rules(doc, out)
	# The shared format check has the last word: anything it still objects
	# to that wasn't already caught above is reported as it says it.
	if errors(out).is_empty():
		for text in level.validate(Catalog.enemy_ids()):
			_add(out, "error", text, "", 1)
	return out


static func errors(problems: Array) -> Array:
	return problems.filter(func(p: Dictionary) -> bool: return p.level == "error")


static func warnings(problems: Array) -> Array:
	return problems.filter(func(p: Dictionary) -> bool: return p.level == "warning")


## Problems that point at one item.
static func for_id(problems: Array, id: String) -> Array:
	return problems.filter(func(p: Dictionary) -> bool: return p.id == id)


static func _add(out: Array, severity: String, text: String, id: String, layer: int) -> void:
	out.append({"level": severity, "text": text, "id": id, "layer": layer})


# --- The level as a whole ----------------------------------------------------------------------

static func _check_level(doc: EditorDoc, out: Array) -> void:
	var level := doc.level
	var size := String(level.meta.get("size", ""))
	if not LevelData.SIZES.has(size):
		_add(out, "error", "The level has no size. Pick one in Level settings.", "", 1)
	else:
		var lim: Array = LevelData.SIZES[size]
		var rooms := level.room_count()
		var want := "1 room" if lim[1] == 1 else "%d to %d rooms" % [lim[0], lim[1]]
		if rooms < lim[0]:
			_add(out, "error", "%s levels have %s. This one has %d: add %d more, or pick a smaller size in Level settings." % [
				level.size_name(), want, rooms, lim[0] - rooms], "", 1)
		elif rooms > lim[1]:
			_add(out, "error", "%s levels have %s. This one has %d: remove %d (or turn some into corridors), or pick a bigger size in Level settings." % [
				level.size_name(), want, rooms, rooms - lim[1]], "", 1)
		if size == "arena":
			for r in level.map.rooms:
				if String(r.get("kind", "room")) == "corridor":
					_add(out, "error", "An Arena is one room and nothing else. Remove this corridor.", String(r.id), 1)
	var level_name := String(level.meta.get("name", "")).strip_edges()
	if level_name == "" or level_name == "Untitled":
		_add(out, "warning", "The level has no name. Give it one in Level settings.", "", 1)


# --- Layer 1 ----------------------------------------------------------------------------------

static func _check_map(doc: EditorDoc, out: Array) -> void:
	var level := doc.level
	var rooms: Array = level.map.rooms
	if rooms.is_empty():
		_add(out, "error", "There are no rooms yet. Place a Room from the Map layer's palette.", "", 1)
	var start := LevelData.vec3(level.map.start.get("pos"))
	var start_room := doc.room_at(start)
	if not rooms.is_empty() and start_room == "":
		_add(out, "warning", "The start point isn't inside a room or corridor. Seekers may start in mid-air.", EditorDoc.START, 1)
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			if RoomBuilder.overlapping(rooms[i], rooms[j]):
				_add(out, "warning", "%s overlaps %s. Rooms should sit side by side." % [
					doc.label_of(String(rooms[i].id)), doc.label_of(String(rooms[j].id))], String(rooms[j].id), 1)
	# Can every room be reached? Rooms and corridors that touch are joined.
	if start_room != "":
		var reached := {start_room: true}
		var grew := true
		while grew:
			grew = false
			for a in rooms:
				if not reached.has(String(a.id)):
					continue
				for b in rooms:
					if not reached.has(String(b.id)) and (RoomBuilder.touching(a, b) or RoomBuilder.overlapping(a, b)):
						reached[String(b.id)] = true
						grew = true
		for r in rooms:
			if not reached.has(String(r.id)):
				_add(out, "warning", "%s doesn't touch anything that leads back to the start. Join it with a corridor, or check Seekers can get there another way." % doc.label_of(String(r.id)),
					String(r.id), 1)
	# Imported models.
	var files := {}
	for a in level.map.assets:
		var id := String(a.get("id", ""))
		files[id] = true
		if String(a.get("license", "")).strip_edges() == "":
			_add(out, "error", "The imported model \"%s\" has no license. Set one under Level > Imported models." % id, "", 1)
		if not FileAccess.file_exists(level.dir.path_join(String(a.get("file", "")))):
			_add(out, "error", "The file for the imported model \"%s\" is missing (%s). Import it again." % [id, a.get("file", "")], "", 1)
	for key in ["pieces", "decorations"]:
		for p in level.map[key]:
			var asset := String(p.get("asset", ""))
			if not asset.begins_with("builtin:") and not files.has(asset):
				_add(out, "error", "%s uses a model that isn't imported (\"%s\"). Delete it or import the model again." % [
					doc.label_of(String(p.id)), asset], String(p.id), 1)


# --- Layer 2 ----------------------------------------------------------------------------------

static func _check_interaction(doc: EditorDoc, out: Array) -> void:
	var level := doc.level
	var rules: Array = level.interaction.rules
	var exits := 0
	var depots := 0
	var has_fights := not (level.combat.rooms as Array).is_empty()
	for o in level.interaction.objects:
		var id := String(o.get("id", ""))
		var name := doc.label_of(id)
		match String(o.get("type", "")):
			"door":
				var opened := _targets(rules, id, ["open", "toggle"])
				var closed := _targets(rules, id, ["close", "toggle"])
				var cleared := String(o.get("open_when_cleared", ""))
				var shut := String(o.get("shut_during_combat", ""))
				for room in [cleared, shut]:
					if room != "" and level.combat_room(room).is_empty():
						_add(out, "error", "%s waits on the fight in %s, but that room has no fight. Place enemies there or change the door." % [
							name, doc.label_of(room)], id, 2)
				var starts_open := String(o.get("start", "closed")) == "open"
				if not starts_open and not opened and cleared == "" and not bool(o.get("decorative", false)):
					_add(out, "error", "%s starts closed and nothing ever opens it. Give it a trigger (a button, or \"opens when a room is cleared\"), or tick \"Stays locked on purpose\"." % name, id, 2)
				elif starts_open and not opened and not closed and cleared == "" and shut == "":
					_add(out, "warning", "%s has no triggers: it starts open and nothing ever closes it, so it does nothing." % name, id, 2)
			"teleporter":
				var dest := String(o.get("destination", ""))
				if dest != "":
					exits += 1
				else:
					_add(out, "warning", "%s goes nowhere. Choose where it goes." % name, id, 2)
				if bool(o.get("dormant", false)) and not _targets(rules, id, ["wake", "toggle", "enable"]):
					_add(out, "error", "%s is asleep and nothing ever wakes it. Add a trigger that wakes it, or untick \"Asleep\"." % name, id, 2)
				if bool(o.get("requires_clear", false)) and not has_fights:
					_add(out, "warning", "%s needs every fight cleared, but the level has no fights." % name, id, 2)
			"lumidium_depot":
				depots += 1
			"button":
				var source := doc.press_source(id)
				if not _listens(rules, "pressed", source):
					_add(out, "warning", "%s does nothing when pressed. Add a trigger for it%s." % [
						name, "" if source == id else " (its group)"], id, 2)
			"trigger_zone":
				if not _listens(rules, "entered", id) and not _listens(rules, "party_present", id):
					_add(out, "warning", "%s does nothing when Seekers walk in. Add a trigger for it." % name, id, 2)
			"hazard":
				if (o.get("zones", []) as Array).is_empty():
					_add(out, "error", "%s covers nothing. Add an area for it to cover." % name, id, 2)
			"platform":
				var pts: Array = o.get("points", [])
				if pts.size() < 2:
					_add(out, "error", "%s needs at least 2 stops." % name, id, 2)
				else:
					var moved := false
					for pt in pts:
						moved = moved or LevelData.vec3(pt).distance_to(LevelData.vec3(pts[0])) > 0.1
					if not moved:
						_add(out, "warning", "All of %s's stops are in the same place, so it won't move." % name, id, 2)
				if String(o.get("mode", "")) == "step" and not _targets(rules, id, ["step", "start", "toggle", "enable"]):
					_add(out, "warning", "%s moves one stop per trigger, but nothing triggers it." % name, id, 2)
			"bridge":
				if not bool(o.get("extended", false)) and not _targets(rules, id, ["extend", "toggle"]):
					_add(out, "warning", "%s starts retracted and nothing ever extends it." % name, id, 2)
	if exits == 0:
		_add(out, "error", "There's no way out. Add a Teleporter (Interaction layer) and choose where it goes.", "", 2)
	if depots == 0 and not level.map.rooms.is_empty():
		_add(out, "warning", "There's no Lumidium depot. Seekers usually get one near the start and one near the exit.", "", 2)
	for d in level.interaction.dialogues:
		var id := String(d.get("id", ""))
		if (d.get("lines", []) as Array).is_empty():
			_add(out, "error", "Dialogue \"%s\" has no lines." % id, "dialogue:" + id, 2)
		if not _targets(rules, id, ["start_dialogue"]):
			_add(out, "warning", "Dialogue \"%s\" is never started. Add a trigger that starts it." % id, "dialogue:" + id, 2)


static func _targets(rules: Array, id: String, actions: Array) -> bool:
	for rule in rules:
		for a in rule.get("do", []):
			if String(a.get("target", "")) == id and String(a.get("action", "")) in actions:
				return true
	return false


static func _listens(rules: Array, event: String, source: String) -> bool:
	for rule in rules:
		var when: Dictionary = rule.get("when", {})
		if String(when.get("event", "")) == event and String(when.get("source", "")) == source:
			return true
	return false


# --- Layer 3 ----------------------------------------------------------------------------------

static func _check_combat(doc: EditorDoc, out: Array) -> void:
	var level := doc.level
	var known := Catalog.enemy_ids()
	for c in level.combat.rooms:
		var room := String(c.get("room", ""))
		var name := doc.label_of(room)
		var waves: Array = c.get("waves", [])
		for i in waves.size():
			if (waves[i].get("enemies", []) as Array).is_empty():
				_add(out, "error", "Wave %d of %s is empty. Place an enemy into it or delete the wave (Waves tab)." % [i + 1, name], room, 3)
			for e in waves[i].get("enemies", []):
				if doc.room_at(LevelData.vec3(e.get("pos"))) != room:
					_add(out, "warning", "%s is in a wave of %s but stands outside it." % [doc.label_of(String(e.id)), name], String(e.id), 3)
		if String(c.get("start", "enter")) == "event" and not _targets(level.interaction.rules, room, ["start_combat", "start"]):
			_add(out, "error", "The fight in %s waits for a trigger, but no trigger starts it. Add one (\"Start a room's fight\"), or let it start when a Seeker walks in." % name, room, 3)
	for p in level.placements():
		var id := String(p.get("id", ""))
		var name := doc.label_of(id)
		var enemy := String(p.get("enemy", ""))
		if enemy == "" or not known.has(enemy):
			_add(out, "error", "%s is an enemy the game doesn't have (\"%s\"). Pick another." % [name, enemy], id, 3)
		var wander := bool(p.get("wander", false))
		var chase := bool(p.get("limited_chase", false))
		if wander and float(p.get("wander_radius", 0.0)) <= 0.0:
			_add(out, "error", "%s wanders, but its wander radius is 0. Set a radius or untick Wanders." % name, id, 3)
		if chase and float(p.get("chase_radius", 0.0)) <= 0.0:
			_add(out, "error", "%s has limited chase, but its chase radius is 0. Set a radius or untick Limited chase." % name, id, 3)
		if wander and chase and float(p.get("chase_radius", 0.0)) > 0.0 \
				and float(p.get("chase_radius", 0.0)) < float(p.get("wander_radius", 0.0)):
			_add(out, "error", "%s: the chase radius (%s m) is smaller than the wander radius (%s m), so it would give up on targets inside its own wander area. Make the chase radius at least %s m." % [
				name, str(p.chase_radius), str(p.wander_radius), str(p.wander_radius)], id, 3)
		if float(p.get("spawn_delay", 0.0)) < 0.0:
			_add(out, "error", "%s has a negative spawn delay." % name, id, 3)


# --- Triggers ---------------------------------------------------------------------------------

static func _check_rules(doc: EditorDoc, out: Array) -> void:
	var level := doc.level
	var known := level.ids()
	var timers := {}
	for rule in level.interaction.rules:
		for a in rule.get("do", []):
			if String(a.get("action", "")) == "start_timer":
				timers[String(a.get("id", ""))] = true
	var n := 0
	for rule in level.interaction.rules:
		n += 1
		var rid := "rule:" + String(rule.get("id", ""))
		var what := "Trigger %d" % n
		var when: Dictionary = rule.get("when", {})
		var event := String(when.get("event", ""))
		var source := String(when.get("source", ""))
		var row := Wiring.event_row(event)
		if not LevelData.EVENTS.has(event):
			_add(out, "error", "%s has no \"when\". Choose what sets it off." % what, rid, 2)
		elif String(row[2]) != "":
			if source == "":
				_add(out, "error", "%s doesn't say what sets it off. Choose one." % what, rid, 2)
			elif event == "timer_done":
				if not timers.has(source):
					_add(out, "error", "%s waits for timer \"%s\", but nothing starts that timer." % [what, source], rid, 2)
			elif event == "flag_set":
				pass
			elif not known.has(source):
				_add(out, "error", "%s is set off by \"%s\", which no longer exists. Choose something else or delete the trigger." % [what, source], rid, 2)
			elif String(row[2]) == "combat" and level.combat_room(source).is_empty():
				_add(out, "error", "%s waits on the fight in %s, but that room has no fight." % [what, doc.label_of(source)], rid, 2)
		var actions: Array = rule.get("do", [])
		if actions.is_empty():
			_add(out, "error", "%s does nothing. Add an action or delete it." % what, rid, 2)
		for a in actions:
			var action := String(a.get("action", ""))
			if not LevelData.ACTIONS.has(action):
				_add(out, "error", "%s has an action that isn't chosen." % what, rid, 2)
				continue
			if LevelData.TARGETED.has(action):
				var target := String(a.get("target", ""))
				if target == "":
					_add(out, "error", "%s: \"%s\" doesn't say what to act on. Choose a target." % [what, Wiring.action_row(action)[1]], rid, 2)
				elif not known.has(target):
					_add(out, "error", "%s acts on \"%s\", which no longer exists. Choose something else or remove the action." % [what, target], rid, 2)
				elif action == "start_combat" and level.combat_room(target).is_empty():
					_add(out, "error", "%s starts the fight in %s, but that room has no fight." % [what, doc.label_of(target)], rid, 2)
			match action:
				"banner":
					if String(a.get("text", "")).strip_edges() == "":
						_add(out, "warning", "%s shows a banner with no text." % what, rid, 2)
				"set_flag":
					if String(a.get("flag", "")) == "":
						_add(out, "error", "%s sets a flag with no name." % what, rid, 2)
				"start_timer":
					if String(a.get("id", "")) == "":
						_add(out, "error", "%s starts a timer with no name." % what, rid, 2)
				"complete_objective":
					if String(a.get("key", "")) == "":
						_add(out, "error", "%s completes a quest objective with no key." % what, rid, 2)
