extends SceneTree
## Builds examples/starter_large: a 15-room Large level, put together in a
## deliberately scrambled order through the real editor window (every
## panel live), then made compliant. It doubles as a test that a level can
## be built in any order without breaking anything.
##
##   godot --headless --path . --script res://tools/build_starter_level.gd
##
## Scrambled order:
##   1. enemies first, before any room exists (some out in the void, one with a bad leash)
##   2. doors, buttons, the exit teleporter and a depot, still with no rooms
##   3. rooms dropped wherever, unattached and overlapping, in a random order
##   4. rooms renamed, then dragged into place one step at a time
##   5. a stray room added and deleted with enemies inside, undone, redone, deleted again
##   6. corridors last
##   7. triggers, a dialogue, the plains and the rest of the dressing
## Compliance pass:
##   enemies outside every room deleted, enemies moved into the waves of the
##   rooms they stand in, leashes fixed, every remaining problem resolved.

const OUT := "res://examples/starter_large"

var app: Control
var doc: EditorDoc
var log_lines: PackedStringArray = []


func step(text: String) -> void:
	log_lines.append(text)
	print("- ", text)


func settle() -> void:
	await process_frame
	await process_frame


func template(layer: int, title: String) -> Dictionary:
	for e in Catalog.palette(layer, doc):
		if e.title == title:
			return (e.data as Dictionary).duplicate(true)
	push_error("no palette entry " + title)
	return {}


## Places a palette entry the way a click in the view does (add, select, commit).
func place(layer: int, title: String, pos: Vector3, extra := {}, wave := 0) -> String:
	var d := template(layer, title)
	d.merge(extra, true)
	var kind := "enemy" if layer == 3 else String(Catalog.palette(layer, doc).filter(func(e): return e.title == title)[0].kind)
	if not d.has("points") and not d.has("zones"):
		d.pos = LevelData.arr3(pos + Vector3(0, float(d.get("pos_y", 0.0)), 0))
		d.erase("pos_y")
	var id := doc.add(kind, d, wave)
	doc.select(id)
	doc.commit()
	await settle()
	return id


func rename(old: String, to: String) -> String:
	var err := doc.rename(old, to)
	if err != "":
		push_error("rename %s -> %s: %s" % [old, to, err])
		return old
	doc.commit()
	await settle()
	return to


## Moves a room the way dragging does: a few metres at a time, rebuilding
## walls and doorways at every step, through whatever is in the way.
func drag_room(id: String, to: Vector3) -> void:
	var d := doc.find(id)
	var from := LevelData.vec3(d.pos)
	var steps := maxi(1, int(from.distance_to(to) / 6.0))
	for i in range(1, steps + 1):
		Items.set_pos("room", d, from.lerp(to, float(i) / steps).snapped(Vector3(4, 1, 4)) if i < steps else to)
		doc.normalize()
		app.view.rebuild()
		await process_frame
	doc.commit()
	await settle()


func rule(event: String, source: String, actions: Array, once := true) -> void:
	doc.put_rule({"id": doc.new_rule_id(), "when": {"event": event, "source": source}, "if": [], "do": actions, "once": once})
	doc.commit()
	await settle()


func problems_summary() -> String:
	var p := LevelCheck.run(doc)
	return "%d to fix, %d to check" % [LevelCheck.errors(p).size(), LevelCheck.warnings(p).size()]


func _init() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await settle()
	var dir := ProjectSettings.globalize_path(OUT)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.make_dir_recursive_absolute(dir)
	app.set_doc(EditorDoc.create("Starter: Mossy Ruins", "large", "forest", dir))
	doc = app.doc
	await settle()

	# 1. Enemies before any room exists. They land outside waves.
	app.set_layer(3)
	step("Enemies placed before any room exists")
	var hounds_r2 := []
	for p in [Vector3(20, 0, -4), Vector3(28, 0, 4), Vector3(24, 0, 0)]:
		hounds_r2.append(await place(3, "Grub Hound", p))
	await place(3, "Mutated Crawler", Vector3(44, 0, 20))
	await place(3, "Grub Hound", Vector3(52, 0, 28))
	await place(3, "Caustic Ooze", Vector3(48, 0, 52), {"wander": true, "wander_radius": 5.0})
	var bad_leash := await place(3, "Grub Hound", Vector3(84, 0, 44),
		{"wander": true, "wander_radius": 8.0, "limited_chase": true, "chase_radius": 4.0})
	step("  a Grub Hound with chase 4 m < wander 8 m (must be fixed later)")
	var void_enemies := []
	for p in [Vector3(-60, 0, 90), Vector3(300, 0, -80), Vector3(130, 0, 70)]:
		void_enemies.append(await place(3, "Umbral Eye", p))
	step("  three Umbral Eyes out in the void, far from any future room")
	await place(3, "Sentry Drone", Vector3(104, 0, 0), {"wander": true, "wander_radius": 4.0, "limited_chase": true, "chase_radius": 14.0})

	# 2. Interaction pieces before any room.
	app.set_layer(2)
	step("Doors, a floor plate, the exit teleporter and a depot placed with no rooms yet")
	var door_1 := await place(2, "Door", Vector3(8, 0, 0), {"yaw": 90.0})
	var plate := await place(2, "Floor plate", Vector3(0, 0, 4))
	var exit := await place(2, "Teleporter", Vector3(212, 0, 6), {"dormant": true, "label": "Back to Nomad-2"})
	await place(2, "Lumidium depot", Vector3(-5, 0, -5))

	# 3. Rooms dropped wherever, in a scrambled order, unattached and overlapping.
	app.set_layer(1)
	step("Fifteen rooms dropped in a scrambled order, unattached and overlapping")
	var final := {
		"start_room": [Vector3(0, 0, 0), Vector3(16, 6, 16)],
		"hound_den": [Vector3(24, 0, 0), Vector3(16, 6, 16)],
		"ruin_hall": [Vector3(48, 0, 0), Vector3(16, 6, 16)],
		"crawler_pit": [Vector3(48, 0, 24), Vector3(16, 6, 16)],
		"ooze_cellar": [Vector3(48, 0, 48), Vector3(16, 6, 16)],
		"plains_west": [Vector3(72, 0, 48), Vector3(16, 6, 16)],
		"plains_mid": [Vector3(88, 0, 48), Vector3(16, 6, 16)],
		"plains_east": [Vector3(104, 0, 48), Vector3(16, 6, 16)],
		"watch_post": [Vector3(104, 0, 32), Vector3(16, 6, 16)],
		"bridge_room": [Vector3(104, 0, 0), Vector3(16, 6, 16)],
		"lift_room": [Vector3(128, 0, 0), Vector3(16, 6, 16)],
		"junction": [Vector3(152, 0, 0), Vector3(16, 6, 16)],
		"side_vault": [Vector3(152, 0, -16), Vector3(16, 6, 16)],
		"drone_hall": [Vector3(176, 0, 0), Vector3(16, 6, 16)],
		"boss_arena": [Vector3(212, 0, 0), Vector3(24, 6, 24)],
	}
	var order := final.keys()
	var rng := RandomNumberGenerator.new()
	rng.seed = 90
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	var ids := {}
	var k := 0
	for name in order:
		# Scattered along a diagonal, many overlapping each other.
		var at := Vector3(-40 + k * 8, 0, -60 + (k % 3) * 8)
		var room_id := await place(1, "Room", at, {"size": LevelData.arr3(final[name][1])})
		ids[name] = room_id
		k += 1
	step("  " + problems_summary() + " with the rooms piled up")

	# 4. Rename, then drag each room into place through the others.
	step("Rooms renamed (references follow) and dragged into place one step at a time")
	for name in order:
		ids[name] = await rename(ids[name], name)
	for name in order:
		await drag_room(ids[name], final[name][0])
	step("  " + problems_summary() + " after the drag")

	# 5. A stray room with enemies inside: delete, undo, redo, delete for real.
	step("A stray room with two enemies added, deleted, undone, redone")
	var stray := await place(1, "Room", Vector3(0, 0, 80))
	app.set_layer(3)
	await place(3, "Lumen Sprite", Vector3(0, 0, 80))
	await place(3, "Lumen Sprite", Vector3(2, 0, 82))
	app.set_layer(1)
	doc.select(stray)
	doc.remove(stray)
	doc.commit()
	await settle()
	doc.undo()
	await settle()
	doc.redo()
	await settle()
	step("  the sprites it held are now outside every room: " + problems_summary())

	# 6. Corridors last.
	step("Corridors added last")
	for spec in [[Vector3(12, 0, 0), [8, 6, 4]], [Vector3(36, 0, 0), [8, 6, 4]], [Vector3(48, 0, 12), [4, 6, 8]],
			[Vector3(48, 0, 36), [4, 6, 8]], [Vector3(60, 0, 48), [8, 6, 4]], [Vector3(104, 0, 16), [4, 6, 16]],
			[Vector3(116, 0, 0), [8, 6, 4]], [Vector3(140, 0, 0), [8, 6, 4]], [Vector3(164, 0, 0), [8, 6, 4]],
			[Vector3(192, 0, 0), [16, 6, 4]]]:
		await place(1, "Corridor", spec[0], {"size": spec[1]})
	await place(1, "Corridor", Vector3(3, 0, 6), {"size": [4, 6, 8]})
	step("  plus one corridor dropped inside the start room by mistake: " + problems_summary())

	# The plains: three rooms that touch and open fully into one field, split up by rocks.
	step("The plains: three touching rooms set to 'Fully open', broken up by rock pillars")
	for name in ["plains_west", "plains_mid", "plains_east"]:
		doc.find(ids[name]).joins = "open"
		doc.find(ids[name]).floor_color = [0.36, 0.5, 0.3]
	doc.commit()
	await settle()
	for p in [Vector3(80, 0, 42), Vector3(80, 0, 54), Vector3(96, 0, 44), Vector3(96, 0, 52), Vector3(88, 0, 48)]:
		await place(1, "Pillar", p, {"size": [2.5, 3, 2.5], "color": [0.42, 0.4, 0.36]})
	for p in [Vector3(72, 0, 48), Vector3(104, 0, 48)]:
		await place(1, "Fireflies", p)
	for p in [Vector3(0, 0, 0), Vector3(48, 0, 0), Vector3(152, 0, 0), Vector3(212, 0, 0)]:
		await place(1, "Light", p, {"range": 12})

	# 7. Wiring and the rest.
	app.set_layer(2)
	step("Triggers, a dialogue, doors that open on a cleared fight, hazards, a bridge and a lift")
	await rule("pressed", plate, [{"action": "open", "target": door_1}])
	var door_2 := await place(2, "Door", Vector3(40, 0, 0), {"yaw": 90.0, "open_when_cleared": ids.hound_den})
	var door_3 := await place(2, "Door", Vector3(48, 0, 8), {"open_when_cleared": ids.ruin_hall})
	await place(2, "Door", Vector3(56, 0, 48), {"yaw": 90.0, "open_when_cleared": ids.ooze_cellar})
	# Ruin hall: walk in, hear the warning, then the fight starts.
	var zone := await place(2, "Trigger zone", Vector3(48, 0, -2), {"size": [8, 3, 4]})
	doc.level.interaction.dialogues.append({"id": "ruin_warning", "lines": [
		{"speaker": "Nomad-2", "text": "Movement in the ruins. Something has been nesting here."},
		{"speaker": "Nomad-2", "text": "Clear it out and the way south opens."}]})
	doc.commit()
	await rule("entered", zone, [{"action": "start_dialogue", "target": "ruin_warning"}])
	await rule("dialogue_ended", "ruin_warning", [{"action": "start_combat", "target": ids.ruin_hall}])
	app.set_layer(3)
	await place(3, "Mutated Crawler", Vector3(46, 0, -3))
	await place(3, "Mutated Crawler", Vector3(50, 0, 3))
	doc.level.combat_room(ids.ruin_hall).start = "event"
	doc.commit()
	app.set_layer(2)
	await place(2, "Supply box", Vector3(42, 0, 28))
	await place(2, "Lumidium crystal", Vector3(54, 0, 52))
	var mist := await place(2, "Poison mist", Vector3(88, 0, 48))
	doc.find(mist).zones = [{"pos": [88, 0, 48], "size": [12, 4, 12]}]
	var valve := await place(2, "Button", Vector3(70, 0, 42), {"label": "Vent"})
	await rule("pressed", valve, [{"action": "disable", "target": mist}, {"action": "banner", "text": "The mist clears."}])
	var bridge := await place(2, "Bridge", Vector3(104, 0, 4), {"yaw": 90.0})
	await rule("combat_ended", ids.watch_post, [{"action": "extend", "target": bridge}])
	await place(2, "Moving platform", Vector3(128, 0, 0), {"points": [[124, 0, 0], [132, 0.5, 0]]})
	await place(2, "Supply box", Vector3(152, 0, -20), {"contents": "item"})
	await place(2, "Lumidium crystal", Vector3(148, 0, -18))
	await place(2, "Trap", Vector3(176, 0, 2))
	await place(2, "Lumidium depot", Vector3(220, 0, 8))
	await rule("combat_ended", ids.boss_arena, [{"action": "wake", "target": exit}, {"action": "banner", "text": "The way home is open."}])

	app.set_layer(3)
	await place(3, "Grub Hound", Vector3(104, 0, 30))
	await place(3, "Lumen Sprite", Vector3(100, 0, 34))
	await place(3, "Sentry Drone", Vector3(176, 0, -4))
	await place(3, "Sentry Drone", Vector3(176, 0, 4))
	await place(3, "Mutated Crawler", Vector3(208, 0, -4))
	await place(3, "Mutated Crawler", Vector3(216, 0, 4))
	await place(3, "Umbral Eye", Vector3(212, 0, 0), {}, 1)
	await place(3, "Caustic Ooze", Vector3(206, 0, 6), {}, 1)
	step("  " + problems_summary() + " before the compliance pass")

	# --- Compliance pass ------------------------------------------------------------------------
	step("Compliance pass")
	var removed := 0
	for p in doc.level.placements().duplicate():
		if doc.room_at(LevelData.vec3(p.pos)) == "":
			doc.remove(String(p.id))
			removed += 1
	doc.commit()
	await settle()
	step("  deleted %d enemies standing outside every room and corridor" % removed)
	for p in doc.level.placements().duplicate():
		doc.settle_enemy(String(p.id))
	doc.commit()
	step("  moved enemies into the waves of the rooms they stand in")
	var e := doc.find(bad_leash)
	e.chase_radius = 12.0
	doc.commit()
	step("  bad leash fixed: chase 12 m >= wander 8 m")
	for c in doc.level.map.rooms.duplicate():
		if String(c.get("kind", "")) == "corridor" and doc.room_at(LevelData.vec3(c.pos), true) != "":
			doc.remove(String(c.id))
	doc.commit()
	step("  removed the corridor dropped inside the start room")
	doc.level.map.start.pos = [0, 0, 0]
	doc.commit()
	await settle()

	var remaining := LevelCheck.run(doc)
	for p in remaining:
		print("  left: ", p.level, ": ", p.text)
	step("Result: " + problems_summary())
	var err := doc.save()
	log_lines.append("")
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT).path_join("BUILD_LOG.md"), FileAccess.WRITE)
	f.store_string("# How this example was built\n\nBuilt by `tools/build_starter_level.gd`, deliberately out of order.\n\n" + "\n".join(log_lines))
	f.close()
	print("saved: ", error_string(err), "  rooms: ", doc.level.room_count(), "  enemies: ", doc.level.placements().size())
	quit(1 if not LevelCheck.errors(remaining).is_empty() else 0)
