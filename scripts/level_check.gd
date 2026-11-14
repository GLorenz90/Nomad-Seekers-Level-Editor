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

const IMAGE_NAMES := {"albedo": "colour image", "normal": "normal map", "roughness_map": "roughness map",
	"metallic_map": "metallic map", "ao_map": "occlusion map", "emission_map": "glow map", "height_map": "height map"}


static func run(doc: EditorDoc) -> Array:
	var out := []
	var level := doc.level
	doc.update_nav()
	_check_level(doc, out)
	_check_map(doc, out)
	_check_interaction(doc, out)
	_check_combat(doc, out)
	_check_rules(doc, out)
	_check_quest(doc, out)
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
	var rooms := level.room_count()
	if doc.is_nomad2():
		pass  # laid over Nomad-2: no rooms of its own
	elif level.size() == "":
		if rooms == 0:
			_add(out, "error", "There are no rooms yet. Build a floor: the navmesh on it becomes your first room.", "", 1)
		elif rooms < 5:
			_add(out, "error", "%d rooms fits no level size: an Arena is 1 room, a Small level needs 5. Add %d more (split a big room with a Room boundary), or join them into one." % [
				rooms, 5 - rooms], "", 1)
		else:
			_add(out, "error", "%d rooms is more than a Huge level's 25. Turn %d into corridors, join some together, or split the level in two." % [
				rooms, rooms - 25], "", 1)
	elif level.size() == "arena":
		for a in level.map.areas:
			if String(a.get("kind", "room")) == "corridor":
				_add(out, "error", "An Arena is one room and nothing else. Make this corridor part of the room (remove the boundary between them) or turn it into a room.", String(a.id), 1)
	var level_name := String(level.meta.get("name", "")).strip_edges()
	if level_name == "" or level_name == "Untitled":
		_add(out, "warning", "The level has no name. Give it one in Level settings.", "", 1)


# --- Layer 1 ----------------------------------------------------------------------------------

## A bridge's or platform's two ends ([] for anything else).
static func _carrier_ends(o: Dictionary) -> Array:
	match String(o.get("type", "")):
		"bridge":
			var p := LevelData.vec3(o.get("pos"))
			var dir := Basis(Vector3.UP, deg_to_rad(float(o.get("yaw", 0.0)))) * Vector3.FORWARD
			return [p - dir * 1.0, p + dir * (float(o.get("length", 8.0)) + 1.0)]
		"platform":
			var pts: Array = o.get("points", [])
			if pts.size() >= 2:
				return [LevelData.vec3(pts[0]), LevelData.vec3(pts[pts.size() - 1])]
	return []


## The piece of navmesh nearest a point, within 3.5 m (-1 if none).
static func _island_near(walk: Array, p: Vector3) -> int:
	var best := 3.5
	var pick := -1
	for i in walk.size():
		var d := LevelNav._island_distance(walk[i], p)
		if d < best:
			best = d
			pick = i
	return pick


static func _area_size(a: Dictionary) -> float:
	var total := 0.0
	for poly in a.get("polys", []):
		var pts := PackedVector3Array()
		for v in poly:
			pts.append(LevelData.vec3(v))
		total += LevelNav._poly_area(pts)
	return total


static func _check_map(doc: EditorDoc, out: Array) -> void:
	var level := doc.level
	var areas: Array = level.map.areas
	var start := LevelData.vec3(level.map.start.get("pos"))
	var start_room := doc.room_at(start)
	if not areas.is_empty() and start_room == "":
		_add(out, "error", "The start point isn't on the navmesh, so Seekers would start in mid-air or inside something. Move it onto a floor.", EditorDoc.START, 1)
	for a in areas:
		if String(a.get("kind", "room")) == "room" and _area_size(a) < 12.0:
			_add(out, "warning", "%s is tiny (under 12 m²). Is it meant to be a room? Make it a corridor, join it to a neighbour, or move the boundary." % doc.label_of(String(a.id)),
				String(a.id), 1)
	# A boundary that doesn't close its opening splits nothing.
	for b in level.map.boundaries:
		var t := Items.xform("boundary", b)
		var normal := (t.basis * Vector3.BACK).normalized()
		var mid := t * Vector3(0, 0.3, 0)
		var one := doc.room_at(mid + normal * (LevelNav.CUT + LevelData.NAV.radius + 0.4))
		var two := doc.room_at(mid - normal * (LevelNav.CUT + LevelData.NAV.radius + 0.4))
		if one != "" and one == two and level.find_area(one).get("also", []).is_empty():
			_add(out, "warning", "%s doesn't split anything: the navmesh goes round it, so both sides are still %s. Make it wide and tall enough to close the opening (R for the resize handles)." % [
				doc.label_of(String(b.id)), doc.label_of(one)], String(b.id), 1)
	# Can every room be walked to from the start (on the uncut navmesh)?
	if start_room != "" and doc.nav.has("mesh"):
		var walk: Array = LevelNav.islands(doc.nav.mesh)
		# Bridges and moving platforms join the pieces at their two ends.
		var group := range(walk.size())
		for o in level.interaction.objects:
			var ends := _carrier_ends(o)
			if ends.size() == 2:
				var i := _island_near(walk, ends[0])
				var j := _island_near(walk, ends[1])
				if i >= 0 and j >= 0:
					var gi: int = group[i]
					var gj: int = group[j]
					for k in group.size():
						if group[k] == gj:
							group[k] = gi
		var home := -1
		for i in walk.size():
			if LevelNav._island_has(walk[i], start):
				home = group[i]
				break
		if home >= 0:
			for a in areas:
				var seeds := [a.get("seed")]
				seeds.append_array(a.get("also", []))
				var reached := false
				for sd in seeds:
					for i in walk.size():
						if group[i] == home and LevelNav._island_has(walk[i], LevelData.vec3(sd)):
							reached = true
				if not reached:
					_add(out, "warning", "Seekers can't walk from the start to %s. That's fine if a bridge, a moving platform or a teleporter gets them there; otherwise close the gap." % doc.label_of(String(a.id)),
						String(a.id), 1)
	# Imported models.
	var files := {}
	for a in level.map.assets:
		var id := String(a.get("id", ""))
		files[id] = true
		if not FileAccess.file_exists(level.dir.path_join(String(a.get("file", "")))):
			_add(out, "error", "The file for the imported model \"%s\" is missing (%s). Import it again." % [id, a.get("file", "")], "", 1)
	for key in ["pieces", "decorations"]:
		for p in level.map[key]:
			var asset := String(p.get("asset", ""))
			if not asset.begins_with("builtin:") and not files.has(asset):
				_add(out, "error", "%s uses a model that isn't imported (\"%s\"). Delete it or import the model again." % [
					doc.label_of(String(p.id)), asset], String(p.id), 1)
	# Materials.
	for m in level.map.get("materials", []):
		var id := String(m.get("id", ""))
		var shown := String(m.get("name", id))
		for key in LevelData.MATERIAL_IMAGES:
			var file := String(m.get(key, ""))
			if file == "":
				continue
			if not FileAccess.file_exists(level.dir.path_join(file)):
				_add(out, "error", "The %s for the material \"%s\" is missing (%s). Pick it again in the material's settings." % [
					IMAGE_NAMES.get(key, key), shown, file], "", 1)
		if String(m.get("height_map", "")) != "" and String(m.get("mapping", "world")) != "uv":
			_add(out, "warning", "The material \"%s\" has a height map, but height maps only show with Mapping: the model's own UVs." % shown, "", 1)
	for p in level.map.pieces:
		var mat := String(p.get("material", ""))
		if mat != "" and level.find_material(mat).is_empty():
			_add(out, "error", "%s is painted with a material that isn't in the level (\"%s\"). Pick another one in the inspector." % [
				doc.label_of(String(p.id)), mat], String(p.id), 1)


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
			"person":
				if (o.get("talk", []) as Array).is_empty() and not _targets(rules, id, ["set_talk"]):
					_add(out, "warning", "%s has nothing to say. Pick a dialogue for them (What they say)." % name, id, 2)
				for key in ["show_from", "show_until"]:
					var step := String(o.get(key, ""))
					if step != "" and (doc.quest == null or not doc.quest.has_step(step)):
						_add(out, "error", "%s waits for quest step \"%s\", which the quest doesn't have." % [name, step], id, 2)
				for t in o.get("talk", []):
					var from := String(t.get("from_step", "")) if t is Dictionary else ""
					if from != "" and (doc.quest == null or not doc.quest.has_step(from)):
						_add(out, "error", "%s has lines for quest step \"%s\", which the quest doesn't have." % [name, from], id, 2)
					elif t is Dictionary and String(t.get("dialogue", "")) == "":
						_add(out, "error", "%s has a line with no dialogue chosen." % name, id, 2)
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
	if doc.is_nomad2():
		pass  # Nomad-2 has its own teleporter and depot
	elif exits == 0:
		_add(out, "error", "There's no way out. Add a Teleporter (Interaction layer) and choose where it goes.", "", 2)
	if depots == 0 and not level.map.areas.is_empty() and not doc.is_nomad2():
		_add(out, "warning", "There's no Lumidium depot. Seekers usually get one near the start and one near the exit.", "", 2)
	# Dialogues people say (their talk lines, or set by a trigger) count as started.
	var said := {}
	for o in level.interaction.objects:
		for t in o.get("talk", []) if String(o.get("type", "")) == "person" else []:
			if t is Dictionary:
				said[String(t.get("dialogue", ""))] = true
	for rule in rules:
		for a in rule.get("do", []):
			if String(a.get("action", "")) == "set_talk":
				said[String(a.get("dialogue", ""))] = true
	for d in level.interaction.dialogues:
		var id := String(d.get("id", ""))
		if (d.get("lines", []) as Array).is_empty():
			_add(out, "error", "Dialogue \"%s\" has no lines." % id, "dialogue:" + id, 2)
		if not said.has(id) and not _targets(rules, id, ["start_dialogue"]):
			_add(out, "warning", "Dialogue \"%s\" is never started. Add a trigger that starts it, or have someone say it." % id, "dialogue:" + id, 2)


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
		if level.find_area(room).is_empty():
			var first := ""
			for w in waves:
				for e in w.get("enemies", []):
					first = String(e.get("id", "")) if first == "" else first
			_add(out, "error", "A fight is set for %s, but that room is gone (its floor was removed or it merged into another room). Move its enemies into a room, or delete them." % room, first, 3)
			continue
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
		if doc.room_at(LevelData.vec3(p.get("pos"))) == "":
			_add(out, "error", "%s stands outside every room and corridor, so it would fall or never be reached. Move it into a room or corridor, or delete it." % name, id, 3)
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
			elif event == "step_completed":
				if doc.quest == null or not doc.quest.has_step(source):
					_add(out, "error", "%s waits for quest step \"%s\", which %s." % [what, source,
						"this level's quest doesn't have" if doc.quest else "doesn't exist: this level isn't part of a quest"], rid, 2)
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
				"complete_step":
					var step := String(a.get("target", a.get("step", "")))
					if doc.quest == null:
						_add(out, "error", "%s completes a quest step, but this level isn't part of a quest. Make it from Quest > New quest level." % what, rid, 2)
					elif not doc.quest.has_step(step):
						_add(out, "error", "%s completes quest step \"%s\", which the quest doesn't have." % [what, step], rid, 2)
				"stop_escort":
					var who := String(a.get("target", ""))
					var known_people := Wiring.candidates("escort", doc).map(func(c): return c[0])
					if who == "" or not known_people.has(who):
						_add(out, "error", "%s stops escorting \"%s\", who isn't here or on the quest's Nomad-2." % [what, who], rid, 2)
				"set_quest_flag":
					if String(a.get("flag", "")) == "":
						_add(out, "error", "%s sets a quest flag with no name." % what, rid, 2)
				"set_talk":
					if doc.find_dialogue(String(a.get("dialogue", ""))).is_empty():
						_add(out, "error", "%s changes what someone says, but no dialogue is chosen." % what, rid, 2)
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


# --- The quest ----------------------------------------------------------------------------------

## The quest the level belongs to (title, steps, areas), and conditions that
## name its steps.
static func _check_quest(doc: EditorDoc, out: Array) -> void:
	if doc.quest:
		for text in doc.quest.problems():
			_add(out, "error", text, "", 2)
	for rule in doc.level.interaction.rules:
		for c in rule.get("if", []):
			if String(c.get("check", "")) == "quest_step":
				var step := String(c.get("step", ""))
				if doc.quest == null or not doc.quest.has_step(step):
					_add(out, "error", "A trigger checks quest step \"%s\", which %s." % [step,
						"the quest doesn't have" if doc.quest else "doesn't exist: this level isn't part of a quest"],
						"rule:" + String(rule.get("id", "")), 2)
