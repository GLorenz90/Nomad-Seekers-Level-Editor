class_name Catalog
extends RefCounted
## What the editor can place and how it describes things: the palette for
## each layer, the fields the inspector shows for each kind of item, the
## enemy list and friendly names. Field names match docs/level_format.md.

const LAYER_NAMES := {1: "Map", 2: "Interaction", 3: "Combat"}
const LAYER_HELP := {
	1: "Layer 1: Map. Build the space: rooms, corridors, floors, walls, ramps and decorations.",
	2: "Layer 2: Interaction. Place doors, buttons, teleporters and more, then say what triggers what.",
	3: "Layer 3: Combat. Place enemies. Enemies inside a room join one of its waves.",
}

const OBJECT_NAMES := {"door": "Door", "teleporter": "Teleporter", "lumidium_depot": "Lumidium depot",
	"lumidium_node": "Lumidium crystal", "box": "Supply box", "trap": "Trap", "button": "Button",
	"hazard": "Room hazard", "trigger_zone": "Trigger zone", "platform": "Moving platform",
	"bridge": "Bridge"}

const FLOOR_COLOR := [0.42, 0.45, 0.4]
const WALL_COLOR := [0.5, 0.5, 0.56]

## Bundled enemy list, used until the game folder is set (then the game's own
## data/enemies folder is read, so new enemies show up by themselves).
const ENEMY_FILE := "res://catalog/enemies.json"

static var _enemies: Array = []
static var _enemies_from := "?"


# --- Palette ----------------------------------------------------------------------------------

## What can be placed on a layer: [{title, tip, kind, data, group}].
static func palette(layer: int, doc: EditorDoc) -> Array:
	var out := []
	match layer:
		1:
			out.append(_entry("Room", "A room: counts toward the level's size. Floor and walls are built for you, and doorways open where rooms and corridors touch.",
				"room", {"kind": "room", "size": [16, 6, 16], "auto_build": true}, "Spaces"))
			out.append(_entry("Corridor", "A corridor: joins rooms and doesn't count toward the size. Put it against a room and a doorway opens.",
				"room", {"kind": "corridor", "size": [4, 6, 8], "auto_build": true}, "Spaces"))
			out.append(_entry("Floor / block", "A solid box: extra floor, a step, a pillar, a ledge.", "piece",
				{"asset": "builtin:box", "size": [4, 1, 4], "color": FLOOR_COLOR, "collision": "box"}, "Solid shapes"))
			out.append(_entry("Wall", "A solid wall section.", "piece",
				{"asset": "builtin:box", "size": [4, 4, 0.5], "color": WALL_COLOR, "collision": "box"}, "Solid shapes"))
			out.append(_entry("Ramp", "A slope that rises toward its front. Seekers and enemies walk up it.", "piece",
				{"asset": "builtin:ramp", "size": [4, 2, 4], "color": FLOOR_COLOR, "collision": "mesh"}, "Solid shapes"))
			out.append(_entry("Pillar", "A solid cylinder.", "piece",
				{"asset": "builtin:cylinder", "size": [1.5, 4, 1.5], "color": WALL_COLOR, "collision": "box"}, "Solid shapes"))
			out.append(_entry("Invisible wall", "Blocks movement without being seen. Can block everyone, or only Seekers (enemies walk through).",
				"wall", {"size": [4, 4, 0.4], "blocks": "all"}, "Solid shapes"))
			out.append(_entry("Fireflies", "Drifting points of light. Decoration only.", "decoration",
				{"asset": "builtin:fireflies", "size": [6, 3, 6], "amount": 24}, "Decorations"))
			out.append(_entry("Light", "A lamp. Brightness and reach are kept within sensible limits.", "decoration",
				{"asset": "builtin:light", "color": [1, 0.85, 0.6], "energy": 1.5, "range": 8, "pos_y": 3.0}, "Decorations"))
			out.append(_entry("Searchlight", "A beam that sweeps left and right.", "decoration",
				{"asset": "builtin:searchlight", "pos_y": 3.5}, "Decorations"))
			for a in doc.level.map.assets:
				var title := String(a.get("id", "")).capitalize()
				out.append(_entry(title + " (solid)", "Imported model, placed as part of the map: Seekers and enemies collide with it.",
					"piece", {"asset": a.id, "collision": "mesh"}, "Imported models"))
				out.append(_entry(title + " (decoration)", "Imported model, placed as decoration: nothing collides with it unless you turn collision on.",
					"decoration", {"asset": a.id, "collision": "none"}, "Imported models"))
		2:
			out.append(_entry("Door", "Blocks a doorway until something opens it: a button, the end of a room's fight, or any trigger. Snaps to doorways.",
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
		"room":
			return "Corridor" if String(d.get("kind", "room")) == "corridor" else "Room"
		"wall":
			return "Invisible wall"
		"piece", "decoration":
			var asset := String(d.get("asset", ""))
			match asset:
				"builtin:box":
					return "Block" if kind == "piece" else "Box"
				"builtin:ramp":
					return "Ramp"
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
	if kind == "room" and String(d.get("name", "")) != "":
		return String(d.name)
	return "%s (%s)" % [type_name(kind, d), id]


## The id prefix for a new item.
static func id_prefix(kind: String, d: Dictionary) -> String:
	match kind:
		"room":
			return "hall" if String(d.get("kind", "room")) == "corridor" else "room"
		"object":
			var type := String(d.get("type", "object"))
			if type == "button" and String(d.get("mode", "")) == "floor":
				return "plate"
			if type == "hazard":
				return "darkness" if String(d.get("kind", "")) == "darkness" else "mist"
			return {"lumidium_depot": "depot", "lumidium_node": "crystal", "trigger_zone": "zone"}.get(type, type)
		"enemy":
			var parts := String(d.get("enemy", "enemy")).split("_")
			return parts[parts.size() - 1]
		"decoration":
			return String(d.get("asset", "decor")).trim_prefix("builtin:")
		"piece":
			return {"builtin:box": "block", "builtin:ramp": "ramp", "builtin:cylinder": "pillar"}.get(
				String(d.get("asset", "")), String(d.get("asset", "piece")))
	return kind


# --- Inspector fields -------------------------------------------------------------------------

## The fields shown for an item: [{k: key, l: label, t: type, ...}].
## Types: text, multiline, float, int, bool, enum (o: [[value, label]...]),
## vec3, color, combat_room, dest. `tip` is the tooltip; `rebuild` redraws
## the inspector after a change (the field decides which others show).
static func fields(kind: String, d: Dictionary) -> Array:
	var f := []
	match kind:
		"start":
			f.append({"k": "pos", "l": "Position", "t": "vec3", "step": 0.5})
			f.append({"k": "yaw", "l": "Facing (degrees)", "t": "float", "min": -360, "max": 360, "step": 15})
		"room":
			f.append({"k": "name", "l": "Name", "t": "text", "tip": "Shown to players when a fight starts here (\"Arena: Wave 1 / 2\")."})
			f.append({"k": "kind", "l": "Counts as", "t": "enum", "o": [["room", "Room (counts toward size)"], ["corridor", "Corridor (doesn't count)"]],
				"tip": "Only rooms count toward the level's size. Enemies in corridors aren't part of waves."})
			f.append({"k": "pos", "l": "Position", "t": "vec3", "step": 4, "tip": "The middle of the floor. Rooms snap to the 4 m grid."})
			f.append({"k": "size", "l": "Size (wide, tall, deep)", "t": "vec3", "step": 4, "min": 4, "ystep": 1, "ymin": 3})
			f.append({"k": "auto_build", "l": "Build floor and walls for me", "t": "bool", "rebuild": true,
				"tip": "On: the editor makes this room's floor and walls, with doorways where other rooms and corridors touch it."})
			if bool(d.get("auto_build", false)):
				f.append({"k": "floor", "l": "Floor", "t": "bool", "def": true, "tip": "Turn off for a pit you'll bridge or build over yourself."})
				f.append({"k": "walls", "l": "Walls", "t": "bool", "def": true})
				f.append({"k": "wall_height", "l": "Wall height", "t": "float", "min": 1, "max": 12, "step": 0.5, "def": 4.0})
				f.append({"k": "floor_color", "l": "Floor color", "t": "color", "def": FLOOR_COLOR})
				f.append({"k": "wall_color", "l": "Wall color", "t": "color", "def": WALL_COLOR})
		"piece", "decoration":
			var asset := String(d.get("asset", ""))
			f.append({"k": "pos", "l": "Position", "t": "vec3", "step": 0.5})
			if asset != "builtin:fireflies" and asset != "builtin:light":
				f.append({"k": "yaw", "l": "Turn (degrees)", "t": "float", "min": -360, "max": 360, "step": 15})
			match asset:
				"builtin:box", "builtin:ramp", "builtin:cylinder":
					f.append({"k": "size", "l": "Size (wide, tall, deep)", "t": "vec3", "step": 0.5, "min": 0.1})
					f.append({"k": "color", "l": "Color", "t": "color", "def": WALL_COLOR})
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
				_:
					f.append({"k": "scale", "l": "Scale", "t": "scale", "min": 0.05, "max": 50, "step": 0.05})
			if not asset in ["builtin:fireflies", "builtin:light", "builtin:searchlight"]:
				var fallback := "none" if kind == "decoration" else ("mesh" if asset == "builtin:ramp" or not asset.begins_with("builtin:") else "box")
				f.append({"k": "collision", "l": "Collision", "t": "enum", "def": fallback,
					"o": [["none", "None (walk through it)"], ["box", "Box (fast, rough)"], ["mesh", "Exact shape"]],
					"tip": "Anything with collision blocks movement and shapes where enemies can walk."})
			if kind == "decoration" and asset != "builtin:fireflies":
				f.append({"k": "animation.preset", "l": "Animation", "t": "enum", "def": "sweep" if asset == "builtin:searchlight" else "none", "rebuild": true,
					"o": [["none", "None"], ["sway", "Sway (plants)"], ["bob", "Bob up and down"], ["spin", "Spin"], ["pulse", "Pulse"], ["sweep", "Sweep left and right"]]})
				if String(_path(d, "animation.preset", "none")) != "none":
					f.append({"k": "animation.amount", "l": "Animation amount", "t": "float", "min": 0, "max": 2, "step": 0.1, "def": 1.0})
					f.append({"k": "animation.speed", "l": "Animation speed", "t": "float", "min": 0.1, "max": 4, "step": 0.1, "def": 1.0})
		"wall":
			f.append({"k": "pos", "l": "Position", "t": "vec3", "step": 0.5})
			f.append({"k": "yaw", "l": "Turn (degrees)", "t": "float", "min": -360, "max": 360, "step": 15})
			f.append({"k": "size", "l": "Size (wide, tall, thick)", "t": "vec3", "step": 0.5, "min": 0.1})
			f.append({"k": "blocks", "l": "Blocks", "t": "enum", "o": [["all", "Everyone"], ["seekers", "Seekers only (enemies pass)"]],
				"tip": "\"Seekers only\" keeps players in or out while enemies walk through."})
		"object":
			f.append_array(_object_fields(d))
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


static func _object_fields(d: Dictionary) -> Array:
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
