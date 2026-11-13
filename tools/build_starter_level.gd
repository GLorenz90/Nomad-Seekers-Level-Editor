extends SceneTree
## Builds examples/starter_large ("Mossy Ruins"): a 15-room Large level made
## only from basic shapes, room boundaries and the navmesh, put together in a
## deliberately scrambled order through the real editor window (every panel
## live), then made compliant. It doubles as a test that a level can be built
## in any order without breaking anything.
##
##   godot --headless --path . --script res://tools/build_starter_level.gd
##
## Scrambled order:
##   1. enemies first, before there's any floor (some out in the void, one with a bad leash)
##   2. every room boundary, still with nothing to cut
##   3. doors, a floor plate, the exit teleporter and a depot
##   4. room floors dropped on a pile in random order, then slid into place
##   5. a stray floor with two enemies: deleted, undone, redone
##   6. walls in random order, plus one dropped across a doorway by mistake
##   7. corridor floors last
##   8. rocks, lights, wiring, the rest of the enemies
## Compliance pass: enemies off the navmesh deleted, enemies moved into the
## waves of the rooms they stand in, the leash fixed, the stray wall removed,
## corridors marked, rooms named, pit halves joined.

const OUT := "res://examples/starter_large"
const FLOOR := [0.42, 0.45, 0.4]
const GRASS := [0.36, 0.5, 0.3]
const WALL := [0.5, 0.5, 0.56]
const ROCK := [0.42, 0.4, 0.36]
const WALL_H := 3.0
const T := 0.5  # wall thickness
const GAP := 4.0  # doorway width

## Rooms: centre, size, doorways per side (offsets along the side from its
## middle), and floor slabs (relative boxes [x0, x1, z0, z1]) when the floor
## isn't one piece (pits).
const ROOMS := {
	"start_room": {"c": [0, 0], "s": [16, 16], "doors": {"e": [0]}},
	"hound_den": {"c": [24, 0], "s": [16, 16], "doors": {"w": [0], "e": [0]}},
	"ruin_hall": {"c": [48, 0], "s": [16, 16], "doors": {"w": [0], "s": [0]}},
	"crawler_pit": {"c": [48, 24], "s": [16, 16], "doors": {"n": [0], "s": [0]}},
	"ooze_cellar": {"c": [48, 48], "s": [16, 16], "doors": {"n": [0], "e": [0]}},
	"plains_west": {"c": [72, 48], "s": [16, 16], "doors": {"w": [0]}, "open": ["e"], "color": GRASS},
	"plains_mid": {"c": [88, 48], "s": [16, 16], "doors": {}, "open": ["w", "e"], "color": GRASS},
	"plains_east": {"c": [104, 48], "s": [16, 16], "doors": {"n": [-4]}, "open": ["w"], "color": GRASS},
	"watch_post": {"c": [104, 32], "s": [16, 16], "doors": {"s": [-4], "n": [-4]}},
	"bridge_room": {"c": [104, 0], "s": [16, 16], "doors": {"s": [-4], "e": [0]}, "slabs": [[-8, -2, -8, 8], [2, 8, -8, 8]]},
	"lift_room": {"c": [128, 0], "s": [16, 16], "doors": {"w": [0], "e": [0]}, "slabs": [[-8, -4, -8, 8], [4, 8, -8, 8]]},
	"junction": {"c": [152, 0], "s": [16, 16], "doors": {"w": [0], "e": [0], "n": [0]}},
	"side_vault": {"c": [152, -16], "s": [16, 16], "doors": {"s": [0]}},
	"drone_hall": {"c": [176, 0], "s": [16, 16], "doors": {"w": [0], "e": [0]}},
	"boss_arena": {"c": [212, 0], "s": [24, 24], "doors": {"w": [0]}},
}
## Corridors: centre and size (x by z); boundaries go at both ends.
const HALLS := [[12, 0, 8, 4], [36, 0, 8, 4], [48, 12, 4, 8], [48, 36, 4, 8], [60, 48, 8, 4],
	[100, 16, 4, 16], [116, 0, 8, 4], [140, 0, 8, 4], [164, 0, 8, 4], [192, 0, 16, 4]]

var app: Control
var doc: EditorDoc
var log_lines: PackedStringArray = []
var rng := RandomNumberGenerator.new()


func step(text: String) -> void:
	log_lines.append(text)
	print("- ", text)


func settle() -> void:
	await process_frame
	await process_frame


## Lets the navmesh catch up the way it does in the window.
func bake() -> void:
	app._nav_due = 1
	await settle()


func add(kind: String, d: Dictionary, wave := 0) -> String:
	var id := doc.add(kind, d, wave)
	doc.select(id)
	doc.commit()
	await settle()
	return id


func box(pos: Vector3, size: Vector3, color: Array, surface: String) -> Dictionary:
	return {"asset": "builtin:box", "pos": LevelData.arr3(pos), "size": LevelData.arr3(size), "color": color, "surface": surface}


func problems_summary() -> String:
	doc.update_nav()
	var p := LevelCheck.run(doc)
	return "%d to fix, %d to check, %d rooms + %d corridors so far" % [LevelCheck.errors(p).size(), LevelCheck.warnings(p).size(),
		doc.level.room_count(), doc.level.corridor_count()]


# --- Geometry -------------------------------------------------------------------------------------

## A room's floor slabs: [[centre, size], ...] (top at y = 0).
func floors_of(spec: Dictionary) -> Array:
	var c := Vector2(spec.c[0], spec.c[1])
	var s := Vector2(spec.s[0], spec.s[1])
	var slabs: Array = spec.get("slabs", [[-s.x / 2, s.x / 2, -s.y / 2, s.y / 2]])
	var out := []
	for sl in slabs:
		var w: float = sl[1] - sl[0]
		var d: float = sl[3] - sl[2]
		out.append([Vector3(c.x + (sl[0] + sl[1]) / 2.0, -0.5, c.y + (sl[2] + sl[3]) / 2.0), Vector3(w, 0.5, d)])
	return out


## A room's walls: one obstacle box per stretch between doorways.
func walls_of(spec: Dictionary) -> Array:
	var c := Vector2(spec.c[0], spec.c[1])
	var s := Vector2(spec.s[0], spec.s[1])
	var out := []
	for side in ["n", "s", "w", "e"]:
		if side in spec.get("open", []):
			continue
		var along_x: bool = side in ["n", "s"]
		var half := (s.x if along_x else s.y) / 2.0 + T
		var cuts := []
		for off in spec.doors.get(side, []):
			cuts.append([off - GAP / 2.0, off + GAP / 2.0])
		var start := -half
		var stops := []
		for cut in cuts:
			stops.append([start, cut[0]])
			start = cut[1]
		stops.append([start, half])
		for st in stops:
			var length: float = st[1] - st[0]
			if length < 0.05:
				continue
			var mid: float = (st[0] + st[1]) / 2.0
			var pos: Vector3
			var size: Vector3
			match side:
				"n":
					pos = Vector3(c.x + mid, 0, c.y - s.y / 2 - T / 2)
				"s":
					pos = Vector3(c.x + mid, 0, c.y + s.y / 2 + T / 2)
				"w":
					pos = Vector3(c.x - s.x / 2 - T / 2, 0, c.y + mid)
				"e":
					pos = Vector3(c.x + s.x / 2 + T / 2, 0, c.y + mid)
			size = Vector3(length, WALL_H, T) if along_x else Vector3(T, WALL_H, length)
			out.append([pos, size])
	return out


## Boundaries: across each corridor end, between touching rooms' doorways,
## and between the plains.
func boundaries() -> Array:
	var out := []
	for h in HALLS:
		if h[2] > h[3]:  # along x: ends at x = cx +- w/2, plane spans z
			for sx in [-1.0, 1.0]:
				out.append({"pos": [h[0] + sx * h[2] / 2.0, 0, h[1]], "rot": [0, 90, 0], "size": [GAP, WALL_H]})
		else:
			for sz in [-1.0, 1.0]:
				out.append({"pos": [h[0], 0, h[1] + sz * h[3] / 2.0], "size": [GAP, WALL_H]})
	out.append({"pos": [152, 0, -8], "size": [GAP, WALL_H]})  # junction | side vault
	out.append({"pos": [100, 0, 40], "size": [GAP, WALL_H]})  # watch post | plains east
	out.append({"pos": [80, 0, 48], "rot": [0, 90, 0], "size": [16, WALL_H]})  # the plains
	out.append({"pos": [96, 0, 48], "rot": [0, 90, 0], "size": [16, WALL_H]})
	return out


# --- The build ----------------------------------------------------------------------------------

func _init() -> void:
	rng.seed = 2026
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await settle()
	var dir := ProjectSettings.globalize_path(OUT)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.make_dir_recursive_absolute(dir)
	app.set_doc(EditorDoc.create("Starter: Mossy Ruins", "forest", dir))
	doc = app.doc
	doc.level.map.lighting = {"preset": "dusk", "sun_energy": 1.1, "ambient_energy": 1.1}
	doc.level.map.start = {"pos": [-4, 0, 4], "yaw": 0}
	await settle()

	# 1. Enemies before there's any floor.
	app.set_layer(3)
	step("Enemies placed before there's any floor")
	var bad_leash := ""
	for p in [Vector3(20, 0, -4), Vector3(28, 0, 4), Vector3(24, 0, 0)]:
		await add("enemy", {"enemy": "grub_hound", "pos": LevelData.arr3(p)})
	await add("enemy", {"enemy": "mutated_crawler", "pos": [44, 0, 20]})
	await add("enemy", {"enemy": "grub_hound", "pos": [52, 0, 28]})
	await add("enemy", {"enemy": "caustic_ooze", "pos": [48, 0, 52], "wander": true, "wander_radius": 5.0})
	bad_leash = await add("enemy", {"enemy": "grub_hound", "pos": [86, 0, 44], "wander": true, "wander_radius": 8.0, "limited_chase": true, "chase_radius": 4.0})
	step("  a Grub Hound with chase 4 m < wander 8 m (fixed later)")
	for p in [Vector3(-60, 0, 90), Vector3(300, 0, -80), Vector3(130, 0, 70)]:
		await add("enemy", {"enemy": "umbral_eye", "pos": LevelData.arr3(p)})
	step("  three Umbral Eyes out in the void")
	await add("enemy", {"enemy": "sentry_drone", "pos": [109, 0, 0], "wander": true, "wander_radius": 3.0, "limited_chase": true, "chase_radius": 12.0})

	# 2. Every boundary, with nothing yet to cut.
	app.set_layer(1)
	step("Every room boundary placed before any floor")
	for b in boundaries():
		await add("boundary", b)
	await bake()
	step("  " + problems_summary())

	# 3. Doors and the rest of the interaction pieces.
	app.set_layer(2)
	step("Doors, a floor plate, the exit teleporter and a depot, still with no floor")
	var door_1 := await add("object", {"type": "door", "start": "closed", "label": "LOCKED", "pos": [8, 0, 0], "yaw": 90})
	var plate := await add("object", {"type": "button", "mode": "floor", "pos": [2, 0, 4]})
	var exit := await add("object", {"type": "teleporter", "destination": "hub", "label": "Back to Nomad-2", "dormant": true, "pos": [212, 0, 6]})
	await add("object", {"type": "lumidium_depot", "pos": [-5, 0, -5]})

	# 4. Room floors dropped on a pile, then slid into place.
	app.set_layer(1)
	step("Room floors dropped on a pile in random order, then slid into place")
	var order := ROOMS.keys()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	var placed := []
	for name in order:
		var spec: Dictionary = ROOMS[name]
		for slab in floors_of(spec):
			var pile := Vector3(-40 + rng.randi_range(0, 6) * 4, -0.5, -60 + rng.randi_range(0, 3) * 4)
			var id := await add("piece", box(pile, slab[1], spec.get("color", FLOOR), "floor"))
			placed.append([id, slab[0]])
	await bake()
	step("  piled up: " + problems_summary())
	for pair in placed:
		var d := doc.find(pair[0])
		var from := LevelData.vec3(d.pos)
		var to: Vector3 = pair[1]
		for k in range(1, 4):
			Items.set_pos("piece", d, from.lerp(to, k / 3.0))
			doc.commit()
			if k < 3:
				await bake()
	await bake()
	step("  slid into place: " + problems_summary())

	# 5. A stray floor with enemies on it: delete, undo, redo.
	step("A stray floor with two enemies: deleted, undone, redone")
	var stray := await add("piece", box(Vector3(0, -0.5, 80), Vector3(8, 0.5, 8), FLOOR, "floor"))
	await bake()
	app.set_layer(3)
	await add("enemy", {"enemy": "lumen_sprite", "pos": [0, 0, 80]})
	await add("enemy", {"enemy": "lumen_sprite", "pos": [2, 0, 82]})
	app.set_layer(1)
	doc.select(stray)
	doc.remove(stray)
	doc.commit()
	await bake()
	doc.undo()
	await bake()
	doc.redo()
	await bake()
	step("  the sprites it held are now off the navmesh: " + problems_summary())

	# 6. Walls in random order, plus one across a doorway by mistake.
	step("Walls in random order, plus one dropped across a doorway by mistake")
	var walls := []
	for name in ROOMS:
		walls.append_array(walls_of(ROOMS[name]))
	for h in HALLS:  # corridor side walls
		if h[2] > h[3]:
			for sz in [-1.0, 1.0]:
				walls.append([Vector3(h[0], 0, h[1] + sz * (h[3] / 2.0 + T / 2)), Vector3(h[2], WALL_H, T)])
		else:
			for sx in [-1.0, 1.0]:
				walls.append([Vector3(h[0] + sx * (h[2] / 2.0 + T / 2), 0, h[1]), Vector3(T, WALL_H, h[3])])
	for i in range(walls.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = walls[i]
		walls[i] = walls[j]
		walls[j] = t
	for w in walls:
		doc.add("piece", box(w[0], w[1], WALL, "obstacle"))
	doc.commit()
	var mistake := await add("piece", box(Vector3(40, 0, 0), Vector3(T, WALL_H, 6), WALL, "obstacle"))
	await bake()
	step("  %d wall pieces: %s" % [walls.size() + 1, problems_summary()])

	# 7. Corridor floors last.
	step("Corridor floors last")
	for h in HALLS:
		doc.add("piece", box(Vector3(h[0], -0.5, h[1]), Vector3(h[2], 0.5, h[3]), FLOOR, "floor"))
	doc.commit()
	await bake()
	step("  " + problems_summary())

	# 8. Rocks, lights and the rest.
	step("Rocks on the plains, lights, fireflies, wiring and the rest of the enemies")
	for p in [Vector3(80, 0, 42), Vector3(80, 0, 54), Vector3(96, 0, 44), Vector3(96, 0, 52), Vector3(88, 0, 48), Vector3(76, 0, 46)]:
		doc.add("piece", {"asset": "builtin:cylinder", "pos": LevelData.arr3(p), "size": [2.5, 3, 2.5], "color": ROCK, "surface": "obstacle"})
	doc.add("piece", {"asset": "builtin:cylinder", "pos": [92, 0, 41], "size": [0.6, 2.5, 0.6], "color": [0.3, 0.55, 0.3],
		"surface": "intangible", "animation": {"preset": "sway", "amount": 1.0}})
	for p in [Vector3(72, 0, 48), Vector3(104, 0, 48)]:
		doc.add("decoration", {"asset": "builtin:fireflies", "size": [6, 3, 6], "amount": 24, "pos": LevelData.arr3(p)})
	for p in [Vector3(0, 3, 0), Vector3(48, 3, 0), Vector3(152, 3, 0), Vector3(212, 3, 0)]:
		doc.add("decoration", {"asset": "builtin:light", "color": [1, 0.85, 0.6], "energy": 1.5, "range": 12, "pos": LevelData.arr3(p)})
	doc.commit()
	await bake()

	# 9. The new shapes and a material: a stone dais up 5 stairs in the start
	# room, a curved planter wall, and the start room's floor painted.
	step("A dais up a flight of stairs, a curved planter, and a stone material")
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.12
	for y in 64:
		for x in 64:
			var v := 0.55 + 0.25 * noise.get_noise_2d(x, y) - (0.15 if (x % 32 == 0 or y % 16 == 0) else 0.0)
			img.set_pixel(x, y, Color(v, v * 0.97, v * 0.9))
	DirAccess.make_dir_recursive_absolute(dir.path_join("assets"))
	img.save_png(dir.path_join("assets/flagstone.png"))
	doc.level.map.materials.append({"id": "flagstone", "name": "Flagstone", "folder": "Stone", "albedo": "assets/flagstone.png",
		"color": [1, 1, 1], "tile": 4.0, "roughness": 0.9, "license": "CC0", "author": "Nomad's Seekers"})
	doc.add("piece", box(Vector3(4, 0, -6.5), Vector3(6, 1, 3), ROCK, "floor"))
	doc.add("piece", {"asset": "builtin:stairs", "pos": [4, 0, -3.5], "size": [4, 1, 3], "steps": 5, "color": ROCK,
		"surface": "floor", "material": "flagstone"})
	doc.add("piece", {"asset": "builtin:curved_wall", "pos": [-3, 0, -4], "size": [6, 0.8, 0.4], "bend": 90.0, "color": ROCK,
		"surface": "obstacle", "material": "flagstone"})
	for d in doc.level.map.pieces:
		var at := Items.get_pos("piece", d)
		if d.get("surface") == "floor" and d.get("asset") == "builtin:box" and at.y < 0 and absf(at.x) <= 8 and absf(at.z) <= 8:
			d.material = "flagstone"
	doc.commit()
	await bake()
	step("  " + problems_summary())

	# --- Compliance pass ------------------------------------------------------------------------
	step("Compliance pass")
	doc.remove(mistake)
	doc.commit()
	await bake()
	step("  removed the wall dropped across the hound den's doorway")
	# Name the rooms after what's in them, and mark the corridors.
	var renamed := {}
	for name in ROOMS:
		var spec: Dictionary = ROOMS[name]
		var slabs := floors_of(spec)
		var id := _area_on(slabs[0][0])
		if id == "":
			push_error("no area under " + name)
			continue
		for k in range(1, slabs.size()):  # pit rooms: join the far side in
			var other := _area_on(slabs[k][0])
			if other != "" and other != id:
				doc.join_areas(id, other)
		doc.commit()
		await bake()
		var err := doc.rename(id, name)
		if err != "":
			push_error("rename %s -> %s: %s" % [id, name, err])
		doc.level.find_area(name).name = String(name).capitalize()
		renamed[name] = true
		doc.commit()
	var n := 1
	for h in HALLS:
		var id := doc.room_at(Vector3(h[0], 0, h[1]))
		if id != "" and not renamed.has(id):
			doc.level.find_area(id).kind = "corridor"
			doc.rename(id, "hall_%d" % n)
			n += 1
	doc.commit()
	await bake()
	step("  rooms named after their spaces, the bridge and lift rooms' two sides joined, %d corridors marked" % (n - 1))
	var removed := 0
	for p in doc.level.placements().duplicate():
		if doc.room_at(LevelData.vec3(p.pos)) == "":
			doc.remove(String(p.id))
			removed += 1
	doc.commit()
	step("  deleted %d enemies standing off the navmesh" % removed)
	for p in doc.level.placements().duplicate():
		doc.settle_enemy(String(p.id))
	doc.find(bad_leash).chase_radius = 12.0
	doc.commit()
	step("  moved enemies into the waves of the rooms they stand in; fixed the leash (chase 12 m >= wander 8 m)")
	await bake()

	# Wiring (needs the rooms' final names).
	app.set_layer(2)
	await rule("pressed", plate, [{"action": "open", "target": door_1}])
	await add("object", {"type": "door", "start": "closed", "label": "LOCKED", "pos": [40, 0, 0], "yaw": 90, "open_when_cleared": "hound_den"})
	await add("object", {"type": "door", "start": "closed", "label": "LOCKED", "pos": [48, 0, 8], "open_when_cleared": "ruin_hall"})
	await add("object", {"type": "door", "start": "closed", "label": "LOCKED", "pos": [56, 0, 48], "yaw": 90, "open_when_cleared": "ooze_cellar"})
	var zone := await add("object", {"type": "trigger_zone", "size": [8, 3, 4], "once": true, "pos": [44, 0, 0]})
	doc.level.interaction.dialogues.append({"id": "ruin_warning", "lines": [
		{"speaker": "Nomad-2", "text": "Movement in the ruins. Something has been nesting here."},
		{"speaker": "Nomad-2", "text": "Clear it out and the way south opens."}]})
	doc.commit()
	await rule("entered", zone, [{"action": "start_dialogue", "target": "ruin_warning"}])
	await rule("dialogue_ended", "ruin_warning", [{"action": "start_combat", "target": "ruin_hall"}])
	app.set_layer(3)
	await add("enemy", {"enemy": "mutated_crawler", "pos": [46, 0, -3]})
	await add("enemy", {"enemy": "mutated_crawler", "pos": [50, 0, 3]})
	doc.level.combat_room("ruin_hall").start = "event"
	doc.commit()
	app.set_layer(2)
	await add("object", {"type": "box", "contents": "random", "pos": [42, 0, 28]})
	await add("object", {"type": "lumidium_node", "color": "nature", "yield": 3, "pos": [54, 0, 52]})
	var mist := await add("object", {"type": "hazard", "kind": "poison_mist", "active": true, "zones": [{"pos": [88, -0.5, 48], "size": [12, 4, 12]}]})
	var vent := await add("object", {"type": "button", "mode": "press", "label": "Vent", "pos": [68, 0, 42]})
	await rule("pressed", vent, [{"action": "disable", "target": mist}, {"action": "banner", "text": "The mist clears."}])
	var bridge := await add("object", {"type": "bridge", "length": 4, "width": 4, "extended": false, "pos": [106, 0, 0], "yaw": 90})
	await rule("combat_ended", "watch_post", [{"action": "extend", "target": bridge}])
	await add("object", {"type": "platform", "size": [4, 0.5, 4], "mode": "ping_pong", "speed": 2.0, "wait": 1.0, "running": true,
		"points": [[126, 0, 0], [130, 0, 0]]})
	await add("object", {"type": "box", "contents": "item", "pos": [152, 0, -20]})
	await add("object", {"type": "lumidium_node", "color": "fire", "yield": 3, "pos": [148, 0, -18]})
	await add("object", {"type": "trap", "kind": "damage", "pos": [176, 0, 2]})
	await add("object", {"type": "lumidium_depot", "pos": [220, 0, 8]})
	await rule("combat_ended", "boss_arena", [{"action": "wake", "target": exit}, {"action": "banner", "text": "The way home is open."}])
	app.set_layer(3)
	await add("enemy", {"enemy": "grub_hound", "pos": [104, 0, 30]})
	await add("enemy", {"enemy": "lumen_sprite", "pos": [100, 0, 34]})
	await add("enemy", {"enemy": "sentry_drone", "pos": [176, 0, -4]})
	await add("enemy", {"enemy": "sentry_drone", "pos": [176, 0, 4]})
	await add("enemy", {"enemy": "mutated_crawler", "pos": [208, 0, -4]})
	await add("enemy", {"enemy": "mutated_crawler", "pos": [216, 0, 4]})
	await add("enemy", {"enemy": "umbral_eye", "pos": [212, 0, 0]}, 1)
	await add("enemy", {"enemy": "caustic_ooze", "pos": [206, 0, 6]}, 1)
	await bake()

	var remaining := LevelCheck.run(doc)
	for p in remaining:
		print("  left: ", p.level, ": ", p.text)
	step("Result: " + problems_summary())
	var err := doc.save()
	var f := FileAccess.open(dir.path_join("BUILD_LOG.md"), FileAccess.WRITE)
	f.store_string("# How this example was built\n\nBuilt by `tools/build_starter_level.gd` from basic shapes, room boundaries and the navmesh, deliberately out of order.\n\n" + "\n".join(log_lines) + "\n")
	f.close()
	print("saved: ", error_string(err), "  rooms: ", doc.level.room_count(), "  corridors: ", doc.level.corridor_count(),
		"  pieces: ", doc.level.map.pieces.size(), "  enemies: ", doc.level.placements().size())
	quit(1 if not LevelCheck.errors(remaining).is_empty() else 0)


## The room under a floor slab (tries a few spots, in case one is under a rock).
func _area_on(slab_centre: Vector3) -> String:
	for off in [Vector3.ZERO, Vector3(-3, 0, -3), Vector3(3, 0, 3), Vector3(-3, 0, 3), Vector3(3, 0, -3)]:
		var id := doc.room_at(slab_centre + off + Vector3(0, 0.5, 0))
		if id != "":
			return id
	return ""


func rule(event: String, source: String, actions: Array) -> void:
	doc.put_rule({"id": doc.new_rule_id(), "when": {"event": event, "source": source}, "if": [], "do": actions, "once": true})
	doc.commit()
	await settle()
