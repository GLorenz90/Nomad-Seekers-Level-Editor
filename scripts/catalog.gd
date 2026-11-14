class_name Catalog
extends RefCounted
## What the editor can place and how it describes things: the palette for
## each layer, the fields the inspector shows for each kind of item, the
## enemy list and friendly names. Field names match docs/level_format.md.

const LAYER_NAMES := {1: "Map", 2: "Interaction", 3: "Combat"}
const LAYER_HELP := {
	1: "Layer 1: Map. Build the space from floors, walls and your own models. The navmesh shows where Seekers can walk; room boundaries split it into rooms.",
	2: "Layer 2: Interaction. Place doors, buttons, teleporters and more, then say what triggers what.",
	3: "Layer 3: Combat. Place enemies. Enemies inside a room join one of its waves.",
}

const OBJECT_NAMES := {"door": "Door", "teleporter": "Teleporter", "lumidium_depot": "Lumidium depot",
	"lumidium_node": "Lumidium crystal", "box": "Supply box", "trap": "Trap", "button": "Button",
	"hazard": "Room hazard", "trigger_zone": "Trigger zone", "platform": "Moving platform",
	"bridge": "Bridge", "person": "Person"}

const FLOOR_COLOR := [0.42, 0.45, 0.4]
const WALL_COLOR := [0.5, 0.5, 0.56]

const SURFACE_NAMES := {"floor": "Floor", "obstacle": "Obstacle", "intangible": "Intangible"}
const SURFACE_HELP := {
	"floor": "Floor: solid, and the navmesh is built on top of it. Seekers and enemies walk on it.",
	"obstacle": "Obstacle: solid, and blocks the navmesh. Nothing walks on top of it.",
	"intangible": "Intangible: no collision at all, and the navmesh ignores it. Good for grass, distant scenery, anything animated.",
}
const HITBOX_NAMES := {"concave": "Concave (follows every triangle)", "convex": "Convex (one wrapped hull, faster)"}

## Bundled enemy list, used until the game folder is set (then the game's own
## data/enemies folder is read, so new enemies show up by themselves).
const ENEMY_FILE := "res://catalog/enemies.json"

## The open level's quest steps ([[id, label]...]; empty outside a quest),
## for fields that name a step. Set by the app when a level opens.
static var quest_steps: Array = []

static var _enemies: Array = []
static var _enemies_from := "?"


# --- Palette ----------------------------------------------------------------------------------

## The Place list's categories on the Map layer, in order.
const GROUP_ORDER := ["Shapes", "Decorations", "Prefabs", "Materials", "Invisible", "Effects"]
const LIBRARY_GROUPS := {"decoration": "Decorations", "prefab": "Prefabs", "material": "Materials"}

## What can be placed on a layer: [{title, tip, kind, data, group}].
static func palette(layer: int, doc: EditorDoc) -> Array:
	var out := []
	match layer:
		1:
			out.append(_entry("Floor", "A flat slab to walk on (a floor). Build the ground out of these, or of your own models.", "piece",
				{"asset": "builtin:box", "size": [4, 0.5, 4], "color": FLOOR_COLOR, "surface": "floor", "pos_y": -0.5}, "Shapes"))
			out.append(_entry("Wall", "A wall section (an obstacle).", "piece",
				{"asset": "builtin:box", "size": [4, 4, 0.5], "color": WALL_COLOR, "surface": "obstacle"}, "Shapes"))
			out.append(_entry("Block", "A solid box (an obstacle). Change it to a floor in the inspector to make a step or ledge you can stand on.", "piece",
				{"asset": "builtin:box", "size": [2, 2, 2], "color": WALL_COLOR, "surface": "obstacle"}, "Shapes"))
			out.append(_entry("Ramp", "A slope that rises toward its front (a floor). Seekers and enemies walk up it.", "piece",
				{"asset": "builtin:ramp", "size": [4, 2, 4], "color": FLOOR_COLOR, "surface": "floor"}, "Shapes"))
			out.append(_entry("Stairs", "Solid steps rising toward the front (a floor). Change the number of steps in the inspector: if the navmesh doesn't run up them, each step is too tall (over 0.4 m), so add more.", "piece",
				{"asset": "builtin:stairs", "size": [4, 2, 6], "steps": 8, "color": FLOOR_COLOR, "surface": "floor"}, "Shapes"))
			out.append(_entry("Curved wall", "A wall bent along an arc (an obstacle). Set how far it bends in the inspector; its width is its length along the curve.", "piece",
				{"asset": "builtin:curved_wall", "size": [8, 3, 0.5], "bend": 90.0, "color": WALL_COLOR, "surface": "obstacle"}, "Shapes"))
			out.append(_entry("Pillar", "A solid cylinder (an obstacle).", "piece",
				{"asset": "builtin:cylinder", "size": [1.5, 4, 1.5], "color": WALL_COLOR, "surface": "obstacle"}, "Shapes"))
			# Your imported models and materials, each in its category and folder.
			for category in ["decoration", "prefab"]:
				for it in doc.library_items(category):
					var a: Dictionary = it.data
					var surface := String(a.get("surface", "obstacle"))
					var e := _entry(String(a.get("id", "")).capitalize(),
						"Your model (%s). %s" % [SURFACE_NAMES.get(surface, surface).to_lower(), SURFACE_HELP.get(surface, "")],
						"piece", {"asset": a.id}, LIBRARY_GROUPS[category])
					e.folder = it.folder
					e.library = category
					e.id = it.id
					out.append(e)
			for it in doc.library_items("material"):
				var m: Dictionary = it.data
				var e := _entry(String(m.get("name", it.id)), "Click, then click shapes or models to paint them with it. Right-click to edit it.",
					"material", {"material": it.id}, "Materials")
				e.folder = it.folder
				e.library = "material"
				e.id = it.id
				out.append(e)
			out.append(_entry("Room boundary", "An invisible plane that splits the navmesh: put one across each doorway or gap between two rooms (or a room and a corridor). Each piece of navmesh it makes is a room or corridor.",
				"boundary", {"size": [4, 4]}, "Invisible"))
			out.append(_entry("Invisible wall", "Blocks movement without being seen. Can block everyone, or only Seekers (enemies walk through).",
				"wall", {"size": [4, 4, 0.4], "blocks": "all"}, "Invisible"))
			out.append(_entry("Fireflies", "Drifting points of light.", "decoration",
				{"asset": "builtin:fireflies", "size": [6, 3, 6], "amount": 24}, "Effects"))
			out.append(_entry("Light", "A lamp. Brightness and reach are kept within sensible limits.", "decoration",
				{"asset": "builtin:light", "color": [1, 0.85, 0.6], "energy": 1.5, "range": 8, "pos_y": 3.0}, "Effects"))
			out.append(_entry("Searchlight", "A beam that sweeps left and right.", "decoration",
				{"asset": "builtin:searchlight", "pos_y": 3.5}, "Effects"))
		2:
			out.append(_entry("Door", "Blocks a doorway until something opens it: a button, the end of a room's fight, or any trigger.",
				"object", {"type": "door", "start": "closed", "label": "LOCKED"}, "Doors and travel"))
			out.append(_entry("Teleporter", "Takes Seekers somewhere else. Every level needs one with a destination as its exit.",
				"object", {"type": "teleporter", "destination": "hub", "label": "Back to Nomad-2"}, "Doors and travel"))
			out.append(_entry("Moving platform", "Travels between stops, carrying Seekers.", "object",
				{"type": "platform", "size": [4, 0.5, 4], "mode": "ping_pong", "speed": 2.0, "wait": 1.0, "running": true}, "Doors and travel"))
			out.append(_entry("Bridge", "Slides out across a gap when something tells it to. Enemies can cross once it's out.",
				"object", {"type": "bridge", "length": 8, "width": 4, "extended": false}, "Doors and travel"))
			out.append(_entry("Button", "A pedestal a Seeker presses with A.", "object",
				{"type": "button", "mode": "press"}, "Triggers"))
			out.append(_entry("Floor plate", "A plate a Seeker stands on. Group several so they must all be held.",
				"object", {"type": "button", "mode": "floor"}, "Triggers"))
			out.append(_entry("Trigger zone", "An invisible box that fires when a Seeker walks in: start a dialogue, a fight, anything.",
				"object", {"type": "trigger_zone", "size": [4, 3, 4], "once": true}, "Triggers"))
			out.append(_entry("Person", "Someone to talk to. Choose what they say (it can change with the quest's steps), when they're around, and a route to walk. Triggers can have them hand over or take items, or follow the party as an escort.",
				"object", {"type": "person", "name": "Someone", "look": {"color": [0.45, 0.55, 0.75], "height": 1.8}, "talk": []}, "People"))
			out.append(_entry("Supply box", "A breakable box that drops Oro or an item.", "object",
				{"type": "box", "contents": "random"}, "Resources"))
			out.append(_entry("Lumidium crystal", "A crystal deposit Seekers break for Lumidium.", "object",
				{"type": "lumidium_node", "color": "fire", "yield": 3}, "Resources"))
			out.append(_entry("Lumidium depot", "Where Seekers bank the Lumidium they carry. Put one near the start and the exit.",
				"object", {"type": "lumidium_depot"}, "Resources"))
			out.append(_entry("Trap", "A hidden floor trap. A Trap Scanner (or a Goluman) reveals it.", "object",
				{"type": "trap", "kind": "damage"}, "Dangers"))
			out.append(_entry("Poison mist", "Drains HP from everyone inside until something turns it off.", "object",
				{"type": "hazard", "kind": "poison_mist", "active": true}, "Dangers"))
			out.append(_entry("Darkness", "Limits how far Seekers can see until something turns it off.", "object",
				{"type": "hazard", "kind": "darkness", "active": true}, "Dangers"))
		3:
			for e in enemies():
				out.append(_entry(String(e.name), "Place a %s. Inside a room it joins the wave chosen above; anywhere else it's there from the start." % e.name,
					"enemy", {"enemy": e.id}, "Enemies"))
	return out


static func _entry(title: String, tip: String, kind: String, data: Dictionary, group: String) -> Dictionary:
	return {"title": title, "tip": tip, "kind": kind, "data": data, "group": group}


# --- Enemies ----------------------------------------------------------------------------------

static func enemies() -> Array:
	var from := AppSettings.game_dir()
	if _enemies_from != from:
		_enemies_from = from
		_enemies = []
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ENEMY_FILE))
		if parsed is Array:
			_enemies = parsed
		if AppSettings.has_game():
			_read_game_enemies(from.path_join("data/enemies"))
	return _enemies


static func enemy(id: String) -> Dictionary:
	for e in enemies():
		if String(e.id) == id:
			return e
	return {}


static func enemy_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for e in enemies():
		out.append(String(e.id))
	return out


## Enemies the game has that the bundled list doesn't (read from the .tres
## text; only the few fields the editor draws with).
static func _read_game_enemies(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	var listed := {}
	for e in _enemies:
		listed[String(e.id)] = true
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".tres") or listed.has(file.get_basename()):
			continue
		var text := FileAccess.get_file_as_string(folder.path_join(file))
		var e := {"id": file.get_basename(), "name": file.get_basename().capitalize(), "shape": 0,
			"color": [0.7, 0.3, 0.25], "size": [0.9, 1.8, 0.9], "hover": 0.0, "aggro": 14.0}
		for line in text.split("\n"):
			if line.begins_with("display_name = "):
				e.name = line.trim_prefix("display_name = ").strip_edges().trim_prefix("\"").trim_suffix("\"")
			elif line.begins_with("shape = "):
				e.shape = int(line.trim_prefix("shape = "))
			elif line.begins_with("hover_height = "):
				e.hover = float(line.trim_prefix("hover_height = "))
			elif line.begins_with("aggro_range = "):
				e.aggro = float(line.trim_prefix("aggro_range = "))
			elif line.begins_with("color = Color(") or line.begins_with("size = Vector3("):
				var nums := []
				for part in line.get_slice("(", 1).trim_suffix(")").split(","):
					nums.append(float(part))
				if nums.size() >= 3:
					e["color" if line.begins_with("color") else "size"] = nums.slice(0, 3)
		_enemies.append(e)


## Area folders the game already has (for suggestions).
static func game_areas() -> PackedStringArray:
	var out := PackedStringArray()
	var root := AppSettings.game_dir().path_join("levels")
	if AppSettings.has_game() and DirAccess.dir_exists_absolute(root):
		out = DirAccess.get_directories_at(root)
		out.sort()
	return out


# --- Names ------------------------------------------------------------------------------------

## "Door", "Grub Hound", "Room"... for an item.
static func type_name(kind: String, d: Dictionary) -> String:
	match kind:
		"start":
			return "Start point"
		"area":
			return "Corridor" if String(d.get("kind", "room")) == "corridor" else "Room"
		"wall":
			return "Invisible wall"
		"boundary":
			return "Room boundary"
		"piece", "decoration":
			var asset := String(d.get("asset", ""))
			match asset:
				"builtin:box":
					var size := LevelData.vec3(d.get("size"), Vector3.ONE)
					if size.y <= 0.75 and String(d.get("surface", "")) == "floor":
						return "Floor"
					if size.z <= 0.75 or size.x <= 0.75:
						return "Wall"
					return "Block"
				"builtin:ramp":
					return "Ramp"
				"builtin:stairs":
					return "Stairs"
				"builtin:curved_wall":
					return "Curved wall"
				"builtin:cylinder":
					return "Pillar"
				"builtin:fireflies":
					return "Fireflies"
				"builtin:light":
					return "Light"
				"builtin:searchlight":
					return "Searchlight"
			return asset.capitalize()
		"object":
			var type := String(d.get("type", ""))
			if type == "button":
				return "Floor plate" if String(d.get("mode", "press")) == "floor" else "Button"
			if type == "hazard":
				return "Darkness" if String(d.get("kind", "")) == "darkness" else "Poison mist"
			if type == "person" and String(d.get("name", "")) != "":
				return String(d.name)
			return OBJECT_NAMES.get(type, type.capitalize())
		"enemy":
			var e := enemy(String(d.get("enemy", "")))
			return String(e.get("name", String(d.get("enemy", "Enemy")).capitalize()))
		"dialogue":
			return "Dialogue"
		"group":
			return "Button group"
	return kind.capitalize()


## How an item is shown in lists and sentences: its name, else type + id.
static func label(kind: String, d: Dictionary, id: String) -> String:
	if kind == "start":
		return "Start point"
	if kind == "area" and String(d.get("name", "")) != "":
		return "%s (%s)" % [String(d.name), id]
	return "%s (%s)" % [type_name(kind, d), id]


## The id prefix for a new item.
static func id_prefix(kind: String, d: Dictionary) -> String:
	match kind:
		"area":
			return "hall" if String(d.get("kind", "room")) == "corridor" else "room"
		"boundary":
			return "boundary"
		"object":
			var type := String(d.get("type", "object"))
			if type == "button" and String(d.get("mode", "")) == "floor":
				return "plate"
			if type == "hazard":
				return "darkness" if String(d.get("kind", "")) == "darkness" else "mist"
			if type == "person" and String(d.get("name", "")) != "" and String(d.name) != "Someone":
				var first := EditorDoc.slug(String(d.name).get_slice(" ", 0))
				return first if first != "level" else "person"
			return {"lumidium_depot": "depot", "lumidium_node": "crystal", "trigger_zone": "zone"}.get(type, type)
		"enemy":
			var parts := String(d.get("enemy", "enemy")).split("_")
			return parts[parts.size() - 1]
		"decoration":
			return String(d.get("asset", "decor")).trim_prefix("builtin:")
		"piece":
			var asset := String(d.get("asset", ""))
			if asset == "builtin:box":
				return type_name(kind, d).to_lower()
			return {"builtin:ramp": "ramp", "builtin:cylinder": "pillar", "builtin:stairs": "stairs",
				"builtin:curved_wall": "curve"}.get(asset, asset)
	return kind


# --- Inspector fields -------------------------------------------------------------------------

static func _animation_fields(f: Array, d: Dictionary, fallback: String) -> void:
	f.append({"k": "animation.preset", "l": "Animation", "t": "enum", "def": fallback, "rebuild": true,
		"o": [["none", "None"], ["sway", "Sway (plants)"], ["bob", "Bob up and down"], ["spin", "Spin"], ["pulse", "Pulse"], ["sweep", "Sweep left and right"]],
		"tip": "Only intangible things move, so the navmesh and collision stay put."})
	if String(_path(d, "animation.preset", fallback)) != "none":
		f.append({"k": "animation.amount", "l": "Animation amount", "t": "float", "min": 0, "max": 2, "step": 0.1, "def": 1.0})
		f.append({"k": "animation.speed", "l": "Animation speed", "t": "float", "min": 0.1, "max": 4, "step": 0.1, "def": 1.0})


## The fields shown for an item: [{k: key, l: label, t: type, ...}].
## Types: text, multiline, float, int, bool, enum (o: [[value, label]...]),
## vec3, color, combat_room, dest. `tip` is the tooltip; `rebuild` redraws
## the inspector after a change (the field decides which others show).
static func fields(kind: String, d: Dictionary, level: LevelData = null) -> Array:
	var f := []
	match kind:
		"start":
			f.append({"k": "pos", "l": "Position", "t": "vec3", "step": 0.5})
			f.append({"k": "yaw", "l": "Facing (degrees)", "t": "float", "min": -360, "max": 360, "step": 15})
		"area":
			f.append({"k": "name", "l": "Name", "t": "text", "tip": "Shown to players when a fight starts here (\"Arena: Wave 1 / 2\")."})
			f.append({"k": "kind", "l": "Counts as", "t": "enum", "o": [["room", "Room (counts toward size)"], ["corridor", "Corridor (doesn't count)"]],
				"tip": "Only rooms count toward the level's size. Enemies in corridors aren't part of waves."})
			f.append({"k": "color", "l": "Navmesh color", "t": "color", "def": [0.4, 0.6, 0.95]})
		"piece":
			var asset := String(d.get("asset", ""))
			var builtin := asset.begins_with("builtin:")
			f.append({"k": "pos", "l": "Position", "t": "vec3", "step": 0.5})
			f.append({"k": "rot", "l": "Rotation (degrees)", "t": "vec3", "step": 15})
			if builtin:
				var size_label := "Size (length along the curve, tall, thick)" if asset == "builtin:curved_wall" else "Size (wide, tall, deep)"
				f.append({"k": "size", "l": size_label, "t": "vec3", "step": 0.5, "min": 0.05})
			else:
				f.append({"k": "scale", "l": "Scale", "t": "vec3", "step": 0.1, "min": 0.01, "def": [1, 1, 1]})
			if asset == "builtin:curved_wall":
				f.append({"k": "bend", "l": "Bend (degrees)", "t": "float", "min": -LevelData.BEND_MAX, "max": LevelData.BEND_MAX, "step": 5, "def": 90.0,
					"tip": "How far the wall turns along its length: 90 is a quarter circle, 180 a half, 360 a full ring. Negative bends the other way; 0 is straight."})
			if asset == "builtin:stairs":
				f.append({"k": "steps", "l": "Steps", "t": "int", "min": 1, "max": LevelData.STEPS_MAX, "def": 8,
					"tip": "How many steps. Each step is its height divided by this; a step taller than 0.4 m is too tall to walk, and the navmesh stops at it."})
			var mats := [["", "None (plain color)"]]
			if level:
				for m in level.map.materials:
					var folder := String(m.get("folder", ""))
					mats.append([String(m.id), (folder + " / " if folder != "" else "") + String(m.get("name", m.id))])
			f.append({"k": "material", "l": "Material", "t": "enum", "o": mats, "def": "", "unset_empty": true, "rebuild": true,
				"tip": "Paint it with one of the level's materials (Materials in the Place list). Tip: click a material there, then click pieces to paint them."})
			if builtin and String(d.get("material", "")) == "":
				f.append({"k": "color", "l": "Color", "t": "color", "def": WALL_COLOR})
			var surface_options := []
			var hitbox_options := []
			if not builtin:
				var model: Dictionary = level.find_asset(asset) if level else {}
				var ms := String(model.get("surface", "obstacle"))
				var mh := String(model.get("hitbox", "concave"))
				surface_options.append(["", "Same as the model (%s)" % SURFACE_NAMES.get(ms, ms)])
				hitbox_options.append(["", "Same as the model (%s)" % String(HITBOX_NAMES.get(mh, mh)).get_slice(" (", 0)])
			for key in LevelData.SURFACES:
				surface_options.append([key, SURFACE_NAMES[key]])
			for key in LevelData.HITBOXES:
				hitbox_options.append([key, HITBOX_NAMES[key]])
			f.append({"k": "surface", "l": "Acts as", "t": "enum", "o": surface_options, "def": "" if not builtin else "obstacle",
				"unset_empty": true, "rebuild": true, "tip": "\n".join(SURFACE_HELP.values())})
			var effective := level.surface_of(d) if level else String(d.get("surface", "obstacle"))
			if effective != "intangible":
				f.append({"k": "hitbox", "l": "Hitbox", "t": "enum", "o": hitbox_options, "def": "" if not builtin else "concave",
					"unset_empty": true, "tip": "How its collision is made from its shape. Concave follows every triangle (exact). Convex wraps it in one hull: faster, but fills in arches and hollows."})
			else:
				_animation_fields(f, d, "none")
		"decoration":
			var asset := String(d.get("asset", ""))
			f.append({"k": "pos", "l": "Position", "t": "vec3", "step": 0.5})
			if asset == "builtin:searchlight":
				f.append({"k": "rot", "l": "Rotation (degrees)", "t": "vec3", "step": 15})
			match asset:
				"builtin:fireflies":
					f.append({"k": "size", "l": "Area (wide, tall, deep)", "t": "vec3", "step": 1, "min": 1})
					f.append({"k": "amount", "l": "How many", "t": "int", "min": 1, "max": 200, "def": 24})
					f.append({"k": "color", "l": "Color", "t": "color", "def": [1.0, 0.95, 0.5]})
				"builtin:light":
					f.append({"k": "color", "l": "Color", "t": "color", "def": [1.0, 0.85, 0.6]})
					f.append({"k": "energy", "l": "Brightness", "t": "float", "min": 0, "max": 3, "step": 0.1, "def": 1.0})
					f.append({"k": "range", "l": "Reach (m)", "t": "float", "min": 1, "max": 20, "step": 0.5, "def": 6.0})
				"builtin:searchlight":
					f.append({"k": "color", "l": "Color", "t": "color", "def": [1.0, 0.95, 0.8]})
					f.append({"k": "energy", "l": "Brightness", "t": "float", "min": 0, "max": 4, "step": 0.1, "def": 2.0})
					f.append({"k": "range", "l": "Reach (m)", "t": "float", "min": 2, "max": 30, "step": 1, "def": 18.0})
					_animation_fields(f, d, "sweep")
		"wall":
			f.append({"k": "pos", "l": "Position", "t": "vec3", "step": 0.5})
			f.append({"k": "rot", "l": "Rotation (degrees)", "t": "vec3", "step": 15})
			f.append({"k": "size", "l": "Size (wide, tall, thick)", "t": "vec3", "step": 0.5, "min": 0.1})
			f.append({"k": "blocks", "l": "Blocks", "t": "enum", "o": [["all", "Everyone"], ["seekers", "Seekers only (enemies pass)"]],
				"tip": "\"Seekers only\" keeps players in or out while enemies walk through (and doesn't change the navmesh)."})
		"boundary":
			f.append({"k": "pos", "l": "Position", "t": "vec3", "step": 0.5, "tip": "The middle of its bottom edge."})
			f.append({"k": "rot", "l": "Rotation (degrees)", "t": "vec3", "step": 15})
			f.append({"k": "size", "l": "Size (wide, tall)", "t": "vec2", "step": 0.5, "min": 0.5})
		"object":
			f.append_array(_object_fields(d, level))
		"enemy":
			var options := []
			for e in enemies():
				options.append([e.id, e.name])
			f.append({"k": "enemy", "l": "Enemy", "t": "enum", "o": options, "rebuild": true})
			f.append({"k": "pos", "l": "Position", "t": "vec3", "step": 0.5})
			f.append({"k": "yaw", "l": "Facing (degrees)", "t": "float", "min": -360, "max": 360, "step": 15})
			f.append({"k": "spawn_delay", "l": "Spawn delay (seconds)", "t": "float", "min": 0, "max": 600, "step": 0.25, "def": 0.0,
				"tip": "How long after its wave starts before it appears. Decimals are fine."})
			f.append({"k": "wander", "l": "Wanders", "t": "bool", "rebuild": true,
				"tip": "On: it strolls around its starting spot until it notices someone. Off: it stands still."})
			if bool(d.get("wander", false)):
				f.append({"k": "wander_radius", "l": "Wander radius (m)", "t": "float", "min": 0.5, "max": 100, "step": 0.5,
					"tip": "How far from its starting spot it wanders (the green ring)."})
			f.append({"k": "limited_chase", "l": "Limited chase", "t": "bool", "rebuild": true,
				"tip": "On: it gives up when its target gets too far from its starting spot, and walks home."})
			if bool(d.get("limited_chase", false)):
				f.append({"k": "chase_radius", "l": "Chase radius (m)", "t": "float", "min": 0.5, "max": 200, "step": 0.5,
					"tip": "How far from its starting spot it will chase (the red ring). Must not be smaller than the wander radius."})
			f.append({"k": "aggro", "l": "Notices Seekers from", "t": "enum", "def": "normal",
				"o": [["short", "Close up"], ["normal", "Normal distance"], ["long", "Far away"]]})
	return f


static func _object_fields(d: Dictionary, level: LevelData = null) -> Array:
	var f := []
	var type := String(d.get("type", ""))
	if type != "platform" and type != "hazard":
		f.append({"k": "pos", "l": "Position", "t": "vec3", "step": 0.5})
		f.append({"k": "yaw", "l": "Turn (degrees)", "t": "float", "min": -360, "max": 360, "step": 15})
	match type:
		"door":
			f.append({"k": "start", "l": "Starts", "t": "enum", "def": "closed", "o": [["closed", "Closed"], ["open", "Open"]]})
			f.append({"k": "label", "l": "Sign while closed", "t": "text", "def": "LOCKED"})
			f.append({"k": "size", "l": "Size (wide, tall, thick)", "t": "vec3", "step": 0.1, "min": 0.2, "def": [4.2, 4.0, 0.6]})
		"teleporter":
			f.append({"k": "destination", "l": "Goes to", "t": "dest", "tip": "Nomad-2, an area (the game picks one of its levels each session), or nowhere."})
			f.append({"k": "label", "l": "Sign", "t": "text"})
			f.append({"k": "dormant", "l": "Asleep until something wakes it", "t": "bool",
				"tip": "On: the pad does nothing until a trigger wakes it (for example, when the boss room is cleared)."})
			f.append({"k": "requires_clear", "l": "Needs every fight cleared", "t": "bool",
				"tip": "On: the pad stays dark until every room with a fight has been cleared."})
		"lumidium_node":
			f.append({"k": "color", "l": "Color", "t": "enum", "o": [["fire", "Fire"], ["ice", "Ice"], ["lightning", "Lightning"],
				["nature", "Nature"], ["light", "Light"], ["dark", "Dark"], ["raw", "Raw (rare)"]]})
			f.append({"k": "yield", "l": "Lumidium inside", "t": "int", "min": 1, "max": 10, "def": 3})
		"box":
			f.append({"k": "contents", "l": "Contains", "t": "enum", "def": "random", "o": [["random", "Random"], ["oro", "Oro"],
				["hp_gel", "HP Gel"], ["lp_cell", "LP Cell"], ["cure_salt", "Cure Salt"], ["trap_scanner", "Trap Scanner"]]})
		"trap":
			f.append({"k": "kind", "l": "Kind", "t": "enum", "def": "damage", "o": [["damage", "Damage"], ["slow", "Slow"], ["shock", "Shock"],
				["poison", "Poison"], ["confuse", "Confuse"], ["freeze", "Freeze"], ["stun", "Stun"]]})
		"button":
			f.append({"k": "mode", "l": "Kind", "t": "enum", "rebuild": true, "o": [["press", "Button (press A)"], ["floor", "Floor plate (stand on it)"]]})
		"hazard":
			f.append({"k": "kind", "l": "Kind", "t": "enum", "o": [["poison_mist", "Poison mist"], ["darkness", "Darkness"]]})
			f.append({"k": "active", "l": "On at the start", "t": "bool", "def": true})
		"trigger_zone":
			f.append({"k": "size", "l": "Size (wide, tall, deep)", "t": "vec3", "step": 0.5, "min": 0.5})
			f.append({"k": "whole_party", "l": "Wait for the whole party", "t": "bool",
				"tip": "On: fires only once every Seeker on the map is inside (like PSO's boss doors)."})
			f.append({"k": "once", "l": "Only the first time", "t": "bool", "def": true})
			f.append({"k": "enabled", "l": "On at the start", "t": "bool", "def": true})
		"platform":
			f.append({"k": "size", "l": "Size (wide, thick, deep)", "t": "vec3", "step": 0.5, "min": 0.5})
			f.append({"k": "mode", "l": "Moves", "t": "enum", "o": [["ping_pong", "Back and forth"], ["loop", "In a loop"], ["step", "One stop per trigger"]]})
			f.append({"k": "speed", "l": "Speed (m/s)", "t": "float", "min": 0.5, "max": 8, "step": 0.5, "def": 2.0})
			f.append({"k": "wait", "l": "Wait at each stop (s)", "t": "float", "min": 0, "max": 30, "step": 0.5, "def": 1.0})
			f.append({"k": "running", "l": "Moving at the start", "t": "bool", "def": true})
			f.append({"k": "color", "l": "Color", "t": "color", "def": [0.45, 0.5, 0.6]})
		"person":
			f.append({"k": "name", "l": "Name", "t": "text", "tip": "Shown over their head, and in their talk prompt (\"Talk to ...\")."})
			f.append({"k": "look.color", "l": "Color", "t": "color", "def": [0.45, 0.55, 0.75], "tip": "Their stand-in's colour (until they have a model)."})
			f.append({"k": "look.height", "l": "Height (m)", "t": "float", "min": 0.5, "max": 4, "step": 0.1, "def": 1.8})
			var models := [["", "None (a plain figure)"]]
			if level:
				for a in level.map.assets:
					models.append([String(a.id), String(a.id).capitalize()])
			f.append({"k": "look.model", "l": "Model", "t": "enum", "o": models, "def": "", "unset_empty": true,
				"tip": "One of your imported models (Decorations or Prefabs) to stand in for them."})
			if not quest_steps.is_empty():
				var steps := [["", "The start of the quest"]]
				for st in quest_steps:
					steps.append([st[0], "Step " + String(st[1])])
				var until := [["", "The end of the quest"]]
				for st in quest_steps:
					until.append([st[0], "Step " + String(st[1])])
				f.append({"k": "show_from", "l": "Around from", "t": "enum", "o": steps, "def": "", "unset_empty": true,
					"tip": "They appear once this step is done (or from the start)."})
				f.append({"k": "show_until", "l": "Gone after", "t": "enum", "o": until, "def": "", "unset_empty": true,
					"tip": "They leave once this step is done (or stay to the end)."})
			f.append({"k": "walking", "l": "Walks their route from the start", "t": "bool",
				"tip": "Off: they stand still until a trigger tells them to walk. Set the route below."})
		"bridge":
			f.append({"k": "length", "l": "Length (m)", "t": "float", "min": 1, "max": 64, "step": 1})
			f.append({"k": "width", "l": "Width (m)", "t": "float", "min": 1, "max": 16, "step": 0.5})
			f.append({"k": "extended", "l": "Out at the start", "t": "bool"})
			f.append({"k": "speed", "l": "Speed (m/s)", "t": "float", "min": 0.5, "max": 12, "step": 0.5, "def": 4.0})
	return f


static func _path(d: Dictionary, key: String, fallback: Variant) -> Variant:
	var at: Variant = d
	for part in key.split("."):
		if not (at is Dictionary) or not (at as Dictionary).has(part):
			return fallback
		at = at[part]
	return at
