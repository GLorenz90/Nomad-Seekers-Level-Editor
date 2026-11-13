class_name RoomBuilder
extends RefCounted
## Builds the floor and walls of rooms and corridors that ask for it
## ("auto_build"), and opens doorways wherever two of them touch. The
## result is ordinary pieces in map.json (tagged "generated_for"), so the
## game needs to know nothing about it.
##
## Walls sit centred on a room's edge, so two rooms that touch share one
## wall line. A doorway is as wide as the shared stretch of edge, up to
## DOOR_WIDTH (centred on it).

const THICK := 0.5
const DOOR_WIDTH := 4.0
const EPS := 0.01


## The four sides of a room's footprint: [{axis: "x"|"z", at, from, to}].
## An "x" side runs along X at z = at; a "z" side runs along Z at x = at.
static func sides(room: Dictionary) -> Array:
	var p := LevelData.vec3(room.get("pos"))
	var s := LevelData.vec3(room.get("size"), Vector3(16, 6, 16))
	return [
		{"axis": "x", "at": p.z - s.z * 0.5, "from": p.x - s.x * 0.5, "to": p.x + s.x * 0.5},
		{"axis": "x", "at": p.z + s.z * 0.5, "from": p.x - s.x * 0.5, "to": p.x + s.x * 0.5},
		{"axis": "z", "at": p.x - s.x * 0.5, "from": p.z - s.z * 0.5, "to": p.z + s.z * 0.5},
		{"axis": "z", "at": p.x + s.x * 0.5, "from": p.z - s.z * 0.5, "to": p.z + s.z * 0.5},
	]


## How two touching rooms meet: "wall" (no opening), "doorway" (up to
## DOOR_WIDTH) or "open" (the whole shared edge). The stricter choice wins.
static func join_mode(a: Dictionary, b: Dictionary) -> String:
	var modes := [String(a.get("joins", "doorway")), String(b.get("joins", "doorway"))]
	if "wall" in modes:
		return "wall"
	if "doorway" in modes:
		return "doorway"
	return "open"


## True when Seekers can walk from one room straight into the other.
static func joined(a: Dictionary, b: Dictionary) -> bool:
	if overlapping(a, b):
		return true
	return touching(a, b) and join_mode(a, b) != "wall" \
		and absf(LevelData.vec3(a.get("pos")).y - LevelData.vec3(b.get("pos")).y) <= 1.0


## Openings between rooms that touch: [{pos: Vector3, yaw: float, width, a, b, open}].
## "open" is true for a fully open edge (no door can go there).
static func doorways(level: LevelData) -> Array:
	var out := []
	var rooms: Array = level.map.rooms
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			var ya := float(LevelData.vec3(rooms[i].get("pos")).y)
			var yb := float(LevelData.vec3(rooms[j].get("pos")).y)
			if absf(ya - yb) > 1.0:
				continue
			var mode := join_mode(rooms[i], rooms[j])
			if mode == "wall":
				continue
			for sa in sides(rooms[i]):
				for sb in sides(rooms[j]):
					if sa.axis != sb.axis or absf(float(sa.at) - float(sb.at)) > EPS:
						continue
					var lo := maxf(float(sa.from), float(sb.from))
					var hi := minf(float(sa.to), float(sb.to))
					if hi - lo < 1.0:
						continue
					var width := hi - lo if mode == "open" else minf(hi - lo, DOOR_WIDTH)
					var mid := (lo + hi) * 0.5
					var pos := Vector3(mid, ya, float(sa.at)) if sa.axis == "x" else Vector3(float(sa.at), ya, mid)
					out.append({"pos": pos, "yaw": 0.0 if sa.axis == "x" else 90.0, "width": width,
						"axis": sa.axis, "at": float(sa.at), "from": mid - width * 0.5, "to": mid + width * 0.5,
						"a": String(rooms[i].get("id", "")), "b": String(rooms[j].get("id", "")), "open": mode == "open"})
	return out


## Throws away every generated piece and builds them again.
static func rebuild(level: LevelData) -> void:
	var kept := []
	for p in level.map.pieces:
		if not p.has("generated_for"):
			kept.append(p)
	level.map.pieces = kept
	var doors := doorways(level)
	var built := []  # wall stretches already made: {axis, at, y, from, to}
	for room in level.map.rooms:
		if not bool(room.get("auto_build", false)):
			continue
		var id := String(room.get("id", ""))
		var p := LevelData.vec3(room.get("pos"))
		var s := LevelData.vec3(room.get("size"), Vector3(16, 6, 16))
		var n := 0
		if bool(room.get("floor", true)):
			n += 1
			level.map.pieces.append({"id": "auto_%s_%d" % [id, n], "generated_for": id, "asset": "builtin:box",
				"pos": [p.x, p.y - 1.0, p.z], "size": [s.x, 1.0, s.z],
				"color": room.get("floor_color", Catalog.FLOOR_COLOR), "collision": "box"})
		if not bool(room.get("walls", true)):
			continue
		var height := clampf(float(room.get("wall_height", 4.0)), 1.0, 12.0)
		for side in sides(room):
			# Start with the whole edge (plus the corners), cut out the doorways,
			# then cut out anything a neighbour already built on the same line.
			var spans := [[float(side.from) - THICK * 0.5, float(side.to) + THICK * 0.5]]
			for d in doors:
				if (d.a == id or d.b == id) and d.axis == side.axis and absf(float(d.at) - float(side.at)) < EPS:
					spans = _cut(spans, float(d.from), float(d.to))
			for b in built:
				if b.axis == side.axis and absf(float(b.at) - float(side.at)) < EPS and absf(float(b.y) - p.y) < EPS:
					spans = _cut(spans, float(b.from), float(b.to))
			for span in spans:
				var length: float = span[1] - span[0]
				if length < 0.05:
					continue
				var mid: float = (span[0] + span[1]) * 0.5
				n += 1
				var along_x: bool = side.axis == "x"
				level.map.pieces.append({"id": "auto_%s_%d" % [id, n], "generated_for": id, "asset": "builtin:box",
					"pos": [mid, p.y, float(side.at)] if along_x else [float(side.at), p.y, mid],
					"size": [length, height, THICK] if along_x else [THICK, height, length],
					"color": room.get("wall_color", Catalog.WALL_COLOR), "collision": "box"})
				built.append({"axis": side.axis, "at": float(side.at), "y": p.y, "from": span[0], "to": span[1]})


## Removes [from, to] from a list of [a, b] spans.
static func _cut(spans: Array, from: float, to: float) -> Array:
	var out := []
	for span in spans:
		var a: float = span[0]
		var b: float = span[1]
		if to <= a + EPS or from >= b - EPS:
			out.append(span)
			continue
		if from > a + EPS:
			out.append([a, from])
		if to < b - EPS:
			out.append([to, b])
	return out


## Rooms and corridors that touch or overlap (for "can every room be reached").
static func touching(a: Dictionary, b: Dictionary) -> bool:
	var pa := LevelData.vec3(a.get("pos"))
	var sa := LevelData.vec3(a.get("size"), Vector3(16, 6, 16))
	var pb := LevelData.vec3(b.get("pos"))
	var sb := LevelData.vec3(b.get("size"), Vector3(16, 6, 16))
	var gap_x := absf(pa.x - pb.x) - (sa.x + sb.x) * 0.5
	var gap_z := absf(pa.z - pb.z) - (sa.z + sb.z) * 0.5
	if gap_x > EPS or gap_z > EPS:
		return false
	# Touching only at a corner doesn't count.
	return not (absf(gap_x) <= EPS and absf(gap_z) <= EPS)


static func overlapping(a: Dictionary, b: Dictionary) -> bool:
	var pa := LevelData.vec3(a.get("pos"))
	var sa := LevelData.vec3(a.get("size"), Vector3(16, 6, 16))
	var pb := LevelData.vec3(b.get("pos"))
	var sb := LevelData.vec3(b.get("size"), Vector3(16, 6, 16))
	return absf(pa.x - pb.x) < (sa.x + sb.x) * 0.5 - EPS and absf(pa.z - pb.z) < (sa.z + sb.z) * 0.5 - EPS \
		and absf(pa.y - pb.y) < 1.0
