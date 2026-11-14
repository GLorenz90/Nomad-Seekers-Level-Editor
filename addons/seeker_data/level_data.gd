class_name LevelData
extends RefCounted
## The Nomad's Seekers level format (version 2), shared by the game and the
## level editor. Full description: docs/level_format.md.
##
## A level is a folder of JSON files plus plain assets. It never holds code:
## Godot .tres / .tscn files can carry scripts that run when loaded, and
## levels will be shared on the Steam Workshop, so the game only builds
## levels out of its own whitelisted pieces (Grayson, 2026-11-12).
##
##   my_level/
##     level.json        meta: name, author, description, area (size comes from the room count)
##     map.json          Layer 1: pieces, invisible walls, room boundaries, areas,
##                       decorations, lighting
##     interaction.json  Layer 2: doors, buttons, hazards, platforms... + rules
##     combat.json       Layer 3: waves per room, corridor enemies
##     assets/           glb / gltf models, png, ogg
##
## This script only reads, writes and checks the data; it doesn't know the
## game's classes, so the editor can use it as-is (addons/seeker_data/).
##
## Version 2 (Grayson, 2026-11-13): levels are built from placed pieces only
## (no generated rooms). Every model is a floor (walkable), an obstacle
## (blocks the navmesh) or intangible (no collision). Rooms and corridors are
## areas of the navmesh, split by room boundaries; the editor saves each
## area's navmesh polygons so the game knows where rooms are.

const FORMAT := 2
const FILES := {
	"meta": "level.json",
	"map": "map.json",
	"interaction": "interaction.json",
	"combat": "combat.json",
}

## Level sizes (Grayson, 2026-11-12): rooms only; corridors never count.
## An Arena is one room and nothing else. Since format 2 the size isn't
## chosen: it follows from the room count (size_for).
const SIZES := {
	"arena": [1, 1],
	"small": [5, 9],
	"medium": [10, 14],
	"large": [15, 19],
	"huge": [20, 25],
}
const SIZE_NAMES := {"arena": "Arena", "small": "Small", "medium": "Medium",
	"large": "Large", "huge": "Huge"}

## The editor's default snap.
const GRID := 4.0

## What a piece is to Seekers and enemies (Grayson, 2026-11-13).
##   floor       solid, and the navmesh is built on top of it
##   obstacle    solid, and blocks the navmesh (nothing walks on top)
##   intangible  no collision; ignored by the navmesh
const SURFACES := ["floor", "obstacle", "intangible"]
## How a solid piece's collision is made from its mesh: concave follows
## every triangle (exact, static only); convex wraps it in one hull.
const HITBOXES := ["concave", "convex"]
const AREA_KINDS := ["room", "corridor"]
## The navmesh is sized for a Seeker (the player capsule: radius 0.4, 1.8 tall).
## The 0.2 m cell fits that radius and height exactly; steps up to 0.4 m count
## as walkable. The game sets its navigation map to the same cell size.
const NAV := {"radius": 0.4, "height": 1.8, "climb": 0.4, "slope": 45.0,
	"cell": 0.2, "cell_height": 0.2}
const WALL_BLOCKS := ["all", "seekers"]
## Decoration animation presets (no scripts in levels).
const ANIMATIONS := ["none", "sway", "bob", "spin", "pulse", "sweep"]
## Built-in shapes, so a level can be blocked out without importing anything.
## They're sized with "size"; imported models with "scale".
const BUILTIN_PIECES := ["builtin:box", "builtin:cylinder", "builtin:ramp", "builtin:curved_wall", "builtin:stairs"]
## Shape settings (Grayson, 2026-11-13): a curved wall's "bend" in degrees
## (its length runs along the curve), and the number of "steps" on stairs.
const BEND_MAX := 360.0
const STEPS_MAX := 64
## Where imported models sit in the editor's palette (the game ignores it).
const ASSET_CATEGORIES := ["decoration", "prefab"]
const MODEL_FILES := ["glb", "gltf"]
const TEXTURE_FILES := ["png", "jpg", "jpeg", "webp"]
## The image keys of a material (map.materials; see LevelMaterials).
const MATERIAL_IMAGES := ["albedo", "normal", "roughness_map", "metallic_map", "ao_map", "emission_map", "height_map"]
## Built-in effects (lights and particles), kept in map.decorations.
const BUILTIN_DECOR := ["builtin:fireflies", "builtin:light", "builtin:searchlight"]

## Lighting presets and how far each slider may go, so no level is too dark
## to see or annoyingly bright (Grayson). Dark rooms use the Darkness hazard.
const LIGHTING_PRESETS := ["day", "dusk", "overcast", "night", "cave", "interior"]
const LIGHT_LIMITS := {
	"sun_energy": [0.3, 1.6],
	"ambient_energy": [0.5, 1.5],
	"exposure": [0.8, 1.3],
	"fog_density": [0.0, 0.03],
}

## Layer 2 object types.
const OBJECT_TYPES := ["door", "teleporter", "lumidium_depot", "lumidium_node", "box",
	"trap", "button", "hazard", "trigger_zone", "platform", "bridge"]
const TRAP_KINDS := ["damage", "slow", "shock", "poison", "confuse", "freeze", "stun"]
const HAZARD_KINDS := ["poison_mist", "darkness"]
const LUMIDIUM_COLORS := ["fire", "ice", "lightning", "nature", "light", "dark", "raw"]
const PLATFORM_MODES := ["loop", "ping_pong", "step"]

## Wiring: when <event> from <source>, if <conditions>, do <actions>.
const EVENTS := ["level_started", "entered", "pressed", "combat_started", "wave_cleared",
	"combat_ended", "enemy_defeated", "health_below", "dialogue_ended", "box_broken",
	"node_broken", "timer_done", "flag_set", "party_present"]
const CONDITIONS := ["flag", "difficulty_at_least", "party_at_least", "quest_active"]
const ACTIONS := ["open", "close", "toggle", "enable", "disable", "start_combat",
	"start", "stop", "step", "extend", "retract", "wake", "start_dialogue", "set_flag",
	"start_timer", "give_item", "complete_objective", "banner", "wait"]
## Actions that need a target object.
const TARGETED := ["open", "close", "toggle", "enable", "disable", "start_combat",
	"start", "stop", "step", "extend", "retract", "wake", "start_dialogue"]
const DIFFICULTIES := ["normal", "hard", "very_hard", "ultimate"]

## Layer 3. Aggro range presets (scale the enemy's own aggro_range).
const AGGRO := {"short": 0.6, "normal": 1.0, "long": 1.5}
const ROOM_STARTS := ["enter", "event"]

var dir := ""
var meta := {}
var map := {}
var interaction := {}
var combat := {}


# --- Making, loading, saving -------------------------------------------------------------

## A new, empty level.
static func create(level_name: String, area := "") -> LevelData:
	var level := LevelData.new()
	level.meta = {"format": FORMAT, "name": level_name, "area": area,
		"author": "", "description": ""}
	level._fill_defaults()
	return level


## Loads a level folder. Null when it has no level.json.
static func load_dir(path: String) -> LevelData:
	var level := LevelData.new()
	level.dir = path
	level.meta = _read_json(path.path_join(FILES.meta))
	if level.meta.is_empty():
		return null
	level.map = _read_json(path.path_join(FILES.map))
	level.interaction = _read_json(path.path_join(FILES.interaction))
	level.combat = _read_json(path.path_join(FILES.combat))
	level._fill_defaults()
	return level


## True when a folder holds a level.
static func is_level_dir(path: String) -> bool:
	return FileAccess.file_exists(path.path_join(FILES.meta))


## Writes the four layer files (each its own file, so layers can be worked on
## separately). Assets are copied by the editor, not here.
func save_dir(path: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		return err
	dir = path
	meta.format = FORMAT
	for key in FILES:
		var f := FileAccess.open(path.path_join(FILES[key]), FileAccess.WRITE)
		if f == null:
			return FileAccess.get_open_error()
		f.store_string(JSON.stringify(get(key), "\t"))
	return OK


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _fill_defaults() -> void:
	meta.merge({"format": FORMAT, "name": "Untitled", "area": "",
		"author": "", "description": ""})
	meta.erase("size")
	map.merge({"grid": GRID, "lighting": {}, "start": {"pos": [0, 0, 0], "yaw": 0},
		"assets": [], "materials": [], "folders": {}, "pieces": [], "walls": [], "boundaries": [],
		"areas": [], "decorations": []})
	map.lighting = clamp_lighting(map.lighting)
	interaction.merge({"objects": [], "button_groups": [], "dialogues": [], "flags": {},
		"rules": []})
	combat.merge({"rooms": [], "free": []})


# --- Reading helpers -----------------------------------------------------------------------

## The size a room count makes ("" when it fits none: 2-4 or over 25).
static func size_for(rooms: int) -> String:
	for key in SIZES:
		if rooms >= SIZES[key][0] and rooms <= SIZES[key][1]:
			return key
	return ""


## This level's size from its rooms ("" when the count fits no size).
func size() -> String:
	return size_for(room_count())


func size_name() -> String:
	var key := size()
	return SIZE_NAMES.get(key, "No size")


## Areas marked as rooms (corridors don't count toward the size).
func room_count() -> int:
	var n := 0
	for a in map.areas:
		if String(a.get("kind", "room")) == "room":
			n += 1
	return n


func corridor_count() -> int:
	return map.areas.size() - room_count()


func find_area(id: String) -> Dictionary:
	for a in map.areas:
		if String(a.get("id", "")) == id:
			return a
	return {}


## The area (room or corridor) a point stands in, "" for none. Uses the
## navmesh polygons the editor saved: inside one (seen from above) and no
## more than 1 m below or 3 m above it.
func area_at(point: Vector3) -> String:
	for a in map.areas:
		if area_contains(a, point):
			return String(a.get("id", ""))
	return ""


static func area_contains(area: Dictionary, point: Vector3) -> bool:
	for poly in area.get("polys", []):
		if poly_contains(poly, point):
			return true
	return false


## A navmesh polygon ([[x, y, z], ...], convex) holds a point seen from above,
## with the point between 1 m below and 3 m above the polygon.
static func poly_contains(poly: Array, point: Vector3) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	var lo := INF
	var hi := -INF
	var sign := 0.0
	for i in n:
		var a := vec3(poly[i])
		var b := vec3(poly[(i + 1) % n])
		lo = minf(lo, a.y)
		hi = maxf(hi, a.y)
		var cross := (b.x - a.x) * (point.z - a.z) - (b.z - a.z) * (point.x - a.x)
		if absf(cross) < 0.0001:
			continue
		if sign == 0.0:
			sign = signf(cross)
		elif signf(cross) != sign:
			return false
	return point.y >= lo - 1.0 and point.y <= hi + 3.0


## A piece's surface: its own override, else its model's, else obstacle.
func surface_of(piece: Dictionary) -> String:
	var s := String(piece.get("surface", ""))
	if s == "":
		s = String(find_asset(String(piece.get("asset", ""))).get("surface", ""))
	return s if SURFACES.has(s) else "obstacle"


## A piece's hitbox: its own override, else its model's, else concave.
func hitbox_of(piece: Dictionary) -> String:
	var h := String(piece.get("hitbox", ""))
	if h == "":
		h = String(find_asset(String(piece.get("asset", ""))).get("hitbox", ""))
	return h if HITBOXES.has(h) else "concave"


func find_material(id: String) -> Dictionary:
	for m in map.materials:
		if String(m.get("id", "")) == id:
			return m
	return {}


## A file a level may load: inside its folder, with an allowed extension.
static func safe_file(file: String, extensions: Array) -> bool:
	return file != "" and not file.contains("..") and not file.is_absolute_path() \
		and not file.begins_with("res:") and not file.begins_with("user:") \
		and extensions.has(file.get_extension().to_lower())


func find_asset(id: String) -> Dictionary:
	for a in map.assets:
		if String(a.get("id", "")) == id:
			return a
	return {}


func find_object(id: String) -> Dictionary:
	for o in interaction.objects:
		if String(o.get("id", "")) == id:
			return o
	return {}


func combat_room(id: String) -> Dictionary:
	for r in combat.rooms:
		if String(r.get("room", "")) == id:
			return r
	return {}


## Every id in the level and what it is ("room", "door", "enemy"...).
func ids() -> Dictionary:
	var out := {}
	for a in map.areas:
		out[String(a.get("id", ""))] = String(a.get("kind", "room"))
	for m in map.materials:
		out[String(m.get("id", ""))] = "material"
	for key in ["pieces", "walls", "boundaries", "decorations"]:
		for p in map[key]:
			out[String(p.get("id", ""))] = "boundary" if key == "boundaries" else key.trim_suffix("s")
	for o in interaction.objects:
		out[String(o.get("id", ""))] = String(o.get("type", ""))
	for g in interaction.button_groups:
		out[String(g.get("id", ""))] = "button_group"
	for d in interaction.dialogues:
		out[String(d.get("id", ""))] = "dialogue"
	for p in placements():
		out[String(p.get("id", ""))] = "enemy"
	return out


## Every enemy placement: wave enemies and corridor enemies.
func placements() -> Array:
	var out := []
	for room in combat.rooms:
		for wave in room.get("waves", []):
			out.append_array(wave.get("enemies", []))
	out.append_array(combat.free)
	return out


static func vec3(v, fallback := Vector3.ZERO) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and v.size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return fallback


static func arr3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## Lighting with every slider kept inside LIGHT_LIMITS.
static func clamp_lighting(lighting: Dictionary) -> Dictionary:
	var out := lighting.duplicate()
	if not LIGHTING_PRESETS.has(String(out.get("preset", ""))):
		out.preset = "day"
	for key in LIGHT_LIMITS:
		var lim: Array = LIGHT_LIMITS[key]
		var fallback := 0.0 if key == "fog_density" else 1.0
		out[key] = clampf(float(out.get(key, fallback)), lim[0], lim[1])
	return out


## Why an enemy placement is invalid ("" when it's fine). Wander and Limited
## chase are leashes from the spawn point; a chase leash shorter than the
## wander leash would have it give up on targets inside its own wander area
## (Grayson, 2026-11-12).
static func placement_problem(p: Dictionary) -> String:
	if String(p.get("enemy", "")) == "":
		return "no enemy chosen"
	if bool(p.get("wander", false)) and float(p.get("wander_radius", 0.0)) <= 0.0:
		return "wander radius must be above 0"
	if bool(p.get("limited_chase", false)) and float(p.get("chase_radius", 0.0)) <= 0.0:
		return "chase radius must be above 0"
	if bool(p.get("wander", false)) and bool(p.get("limited_chase", false)) \
			and float(p.chase_radius) < float(p.wander_radius):
		return "chase radius (%s m) is smaller than wander radius (%s m)" % [
			str(p.chase_radius), str(p.wander_radius)]
	if float(p.get("spawn_delay", 0.0)) < 0.0:
		return "spawn delay can't be negative"
	if p.has("aggro") and not AGGRO.has(String(p.aggro)):
		return "unknown aggro range \"%s\"" % p.aggro
	return ""


# --- The publish check --------------------------------------------------------------------

## Problems that stop a level from being published (empty = good to go).
## `known_enemies`: enemy ids the game has (EnemyData file names); empty
## skips that check. Reachability needs a navmesh, so the editor checks it.
func validate(known_enemies: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var out := PackedStringArray()
	if int(meta.get("format", FORMAT)) > FORMAT:
		out.append("Made with a newer version of the format (%d); this game reads %d." % [
			int(meta.format), FORMAT])
	if int(meta.get("format", FORMAT)) < FORMAT:
		out.append("Made with an older editor (format %d). Levels from before format 2 have to be rebuilt." % int(meta.format))
	var rooms := room_count()
	if size() == "":
		out.append("%d rooms fits no size: an Arena is 1 room, the others take 5-25." % rooms)
	elif size() == "arena" and corridor_count() > 0:
		out.append("An Arena is one room with no corridors.")
	for a in map.areas:
		if (a.get("polys", []) as Array).is_empty():
			out.append("%s has no navmesh saved with it. Open and save the level in the editor." % a.get("id", "?"))
	if not map.has("start") or not (map.start.get("pos") is Array):
		out.append("No start point.")

	# Ids: present and unique across every layer.
	var seen := {}
	var all_ids := []
	for key in ["areas", "pieces", "walls", "boundaries", "decorations"]:
		all_ids.append_array(map[key])
	all_ids.append_array(interaction.objects)
	all_ids.append_array(interaction.button_groups)
	all_ids.append_array(interaction.dialogues)
	all_ids.append_array(placements())
	for item in all_ids:
		var id := String(item.get("id", ""))
		if id == "":
			out.append("Something has no id.")
		elif seen.has(id):
			out.append("Two things share the id \"%s\"." % id)
		seen[id] = true
	var known := ids()

	# Layer 1.
	for a in map.areas:
		if not AREA_KINDS.has(String(a.get("kind", "room"))):
			out.append("Area %s: kind must be room or corridor." % a.get("id", "?"))
	var asset_ids := {}
	for a in map.assets:
		asset_ids[String(a.get("id", ""))] = true
		if a.has("surface") and not SURFACES.has(String(a.surface)):
			out.append("Asset %s: unknown surface." % a.get("id", "?"))
		if not safe_file(String(a.get("file", "")), MODEL_FILES):
			out.append("Asset %s: its file must be a .glb or .gltf inside the level folder." % a.get("id", "?"))
	for m in map.materials:
		var mid := String(m.get("id", "?"))
		for key in MATERIAL_IMAGES:
			if String(m.get(key, "")) != "" and not safe_file(String(m[key]), TEXTURE_FILES):
				out.append("Material %s: its %s image must be a .png, .jpg or .webp inside the level folder." % [mid, key])
		if not LevelMaterials.MAPPINGS.has(String(m.get("mapping", "world"))):
			out.append("Material %s: mapping must be world or uv." % mid)
		if not LevelMaterials.TRANSPARENCY.has(String(m.get("transparency", "none"))):
			out.append("Material %s: transparency must be none, alpha or cutout." % mid)
		for key in ["roughness_channel", "metallic_channel", "ao_channel"]:
			if m.has(key) and not LevelMaterials.CHANNELS.has(String(m[key])):
				out.append("Material %s: %s must be red, green, blue, alpha or gray." % [mid, key])
	for p in map.pieces:
		var asset := String(p.get("asset", ""))
		if asset.begins_with("builtin:"):
			if not BUILTIN_PIECES.has(asset):
				out.append("%s: unknown built-in shape %s." % [p.get("id", "?"), asset])
		elif not asset_ids.has(asset):
			out.append("%s uses an asset that isn't imported (%s)." % [p.get("id", "?"), asset])
		if p.has("surface") and not SURFACES.has(String(p.surface)):
			out.append("%s: unknown surface." % p.get("id", "?"))
		if p.has("hitbox") and not HITBOXES.has(String(p.hitbox)):
			out.append("%s: unknown hitbox." % p.get("id", "?"))
		if String(p.get("material", "")) != "" and find_material(String(p.material)).is_empty():
			out.append("%s uses a material that isn't in the level (%s)." % [p.get("id", "?"), p.material])
		if p.has("steps") and (int(p.steps) < 1 or int(p.steps) > STEPS_MAX):
			out.append("%s: stairs need 1-%d steps." % [p.get("id", "?"), STEPS_MAX])
		if p.has("bend") and absf(float(p.bend)) > BEND_MAX:
			out.append("%s: a curved wall bends at most %d degrees." % [p.get("id", "?"), int(BEND_MAX)])
		if p.has("animation"):
			if not ANIMATIONS.has(String(p.animation.get("preset", "none"))):
				out.append("%s: unknown animation." % p.get("id", "?"))
			elif surface_of(p) != "intangible" and String(p.animation.get("preset", "none")) != "none":
				out.append("%s is animated but solid. Only intangible pieces can move." % p.get("id", "?"))
	for d in map.decorations:
		if not BUILTIN_DECOR.has(String(d.get("asset", ""))):
			out.append("Decoration %s: unknown effect." % d.get("id", "?"))
	for w in map.walls:
		if not WALL_BLOCKS.has(String(w.get("blocks", "all"))):
			out.append("Wall %s: blocks must be all or seekers." % w.get("id", "?"))

	# Layer 2.
	var exits := 0
	for o in interaction.objects:
		var id := String(o.get("id", "?"))
		var type := String(o.get("type", ""))
		if not OBJECT_TYPES.has(type):
			out.append("%s: unknown object type \"%s\"." % [id, type])
			continue
		match type:
			"teleporter":
				if String(o.get("destination", "")) != "":
					exits += 1
			"door":
				for key in ["open_when_cleared", "shut_during_combat"]:
					var room := String(o.get(key, ""))
					if room != "" and combat_room(room).is_empty():
						out.append("Door %s waits on %s, which has no combat." % [id, room])
			"trap":
				if not TRAP_KINDS.has(String(o.get("kind", "damage"))):
					out.append("Trap %s: unknown kind." % id)
			"hazard":
				if not HAZARD_KINDS.has(String(o.get("kind", ""))):
					out.append("Hazard %s: unknown kind." % id)
			"platform":
				if (o.get("points", []) as Array).size() < 2:
					out.append("Platform %s needs at least 2 points." % id)
	if exits == 0:
		out.append("No exit: add a teleporter with a destination.")
	for g in interaction.button_groups:
		for b in g.get("buttons", []):
			if known.get(String(b), "") != "button":
				out.append("Button group %s lists %s, which isn't a button." % [g.get("id", "?"), b])
	for rule in interaction.rules:
		var rid := String(rule.get("id", "?"))
		var when: Dictionary = rule.get("when", {})
		if not EVENTS.has(String(when.get("event", ""))):
			out.append("Rule %s: unknown event." % rid)
		var source := String(when.get("source", ""))
		if source != "" and not known.has(source) and String(when.event) not in ["timer_done", "flag_set"]:
			out.append("Rule %s listens to %s, which doesn't exist." % [rid, source])
		for c in rule.get("if", []):
			if not CONDITIONS.has(String(c.get("check", ""))):
				out.append("Rule %s: unknown condition." % rid)
		for a in rule.get("do", []):
			var action := String(a.get("action", ""))
			if not ACTIONS.has(action):
				out.append("Rule %s: unknown action \"%s\"." % [rid, action])
			elif TARGETED.has(action) and not known.has(String(a.get("target", ""))):
				out.append("Rule %s: %s points at %s, which doesn't exist." % [rid, action,
					a.get("target", "nothing")])

	# Layer 3.
	for room in combat.rooms:
		var rid := String(room.get("room", ""))
		if find_area(rid).is_empty():
			out.append("Combat is set for %s, which isn't a room or corridor." % rid)
		if (room.get("waves", []) as Array).is_empty():
			out.append("%s has combat but no waves." % rid)
		for i in (room.get("waves", []) as Array).size():
			if (room.waves[i].get("enemies", []) as Array).is_empty():
				out.append("%s wave %d is empty." % [rid, i + 1])
		if not ROOM_STARTS.has(String(room.get("start", "enter"))):
			out.append("%s: combat starts on \"enter\" or \"event\"." % rid)
	for p in placements():
		var why := placement_problem(p)
		if why != "":
			out.append("Enemy %s is invalid: %s." % [p.get("id", "?"), why])
		var enemy := String(p.get("enemy", ""))
		if not known_enemies.is_empty() and enemy != "" and not known_enemies.has(enemy):
			out.append("Enemy %s: the game has no \"%s\"." % [p.get("id", "?"), enemy])
	return out
