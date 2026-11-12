class_name Items
extends RefCounted
## Where an item is and how big it is, whatever kind it is. Most items keep
## "pos" and "yaw"; platforms are placed by their stops, hazards by their
## zones, and rooms turn by swapping width and depth (room areas are never
## rotated in the game).


static func get_pos(kind: String, d: Dictionary) -> Vector3:
	if kind == "object":
		if String(d.get("type", "")) == "platform":
			var pts: Array = d.get("points", [])
			return LevelData.vec3(pts[0]) if not pts.is_empty() else Vector3.ZERO
		if String(d.get("type", "")) == "hazard":
			var zones: Array = d.get("zones", [])
			return LevelData.vec3(zones[0].get("pos")) if not zones.is_empty() else Vector3.ZERO
	return LevelData.vec3(d.get("pos"))


static func set_pos(kind: String, d: Dictionary, p: Vector3) -> void:
	var delta := p - get_pos(kind, d)
	if kind == "object" and String(d.get("type", "")) == "platform":
		var pts := []
		for pt in d.get("points", []):
			pts.append(LevelData.arr3(LevelData.vec3(pt) + delta))
		d.points = pts
	elif kind == "object" and String(d.get("type", "")) == "hazard":
		for z in d.get("zones", []):
			z.pos = LevelData.arr3(LevelData.vec3(z.get("pos")) + delta)
	else:
		d.pos = LevelData.arr3(p)


static func has_yaw(kind: String, d: Dictionary) -> bool:
	if kind == "room":
		return false
	if kind == "object" and String(d.get("type", "")) in ["platform", "hazard"]:
		return false
	return true


static func get_yaw(kind: String, d: Dictionary) -> float:
	return float(d.get("yaw", 0.0)) if has_yaw(kind, d) else 0.0


## Turns an item a quarter turn (or by `degrees`).
static func rotate(kind: String, d: Dictionary, degrees: float) -> void:
	if kind == "room":
		var s := LevelData.vec3(d.get("size"), Vector3(16, 6, 16))
		d.size = [s.z, s.y, s.x]
	elif has_yaw(kind, d):
		d.yaw = fposmod(float(d.get("yaw", 0.0)) + degrees, 360.0)


static func xform(kind: String, d: Dictionary) -> Transform3D:
	var basis := Basis(Vector3.UP, deg_to_rad(get_yaw(kind, d)))
	if d.get("scale") is Array and kind in ["piece", "decoration"]:
		basis = basis.scaled(LevelData.vec3(d.scale, Vector3.ONE))
	return Transform3D(basis, get_pos(kind, d))


## The item's box in its own space (see xform). `pick`: the part you click.
static func local_aabb(kind: String, d: Dictionary, level: LevelData, pick := false) -> AABB:
	match kind:
		"start":
			return _base(Vector3(1.0, 1.8, 1.0))
		"room":
			var s := LevelData.vec3(d.get("size"), Vector3(16, 6, 16))
			return _base(Vector3(s.x, 0.15 if pick else s.y, s.z))
		"wall":
			return _base(LevelData.vec3(d.get("size"), Vector3(4, 4, 0.4)))
		"piece", "decoration":
			var asset := String(d.get("asset", ""))
			match asset:
				"builtin:box", "builtin:ramp", "builtin:cylinder", "builtin:fireflies":
					return _base(LevelData.vec3(d.get("size"), Vector3(4, 1, 4)))
				"builtin:light":
					return AABB(Vector3(-0.4, -0.4, -0.4), Vector3(0.8, 0.8, 0.8))
				"builtin:searchlight":
					return AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1))
			return Models.aabb(level, asset)
		"object":
			match String(d.get("type", "")):
				"door":
					return _base(LevelData.vec3(d.get("size"), Vector3(4.2, 4.0, 0.6)))
				"teleporter":
					return _base(Vector3(2.9, 0.5, 2.9))
				"lumidium_depot":
					return _base(Vector3(1.0, 1.6, 1.0))
				"lumidium_node":
					return _base(Vector3(1.2, 1.5, 1.2))
				"box":
					return _base(Vector3(1.0, 1.0, 1.0))
				"trap":
					return _base(Vector3(2.4, 0.3, 2.4))
				"button":
					return _base(Vector3(1.3, 0.2, 1.3) if String(d.get("mode", "press")) == "floor" else Vector3(0.6, 1.0, 0.6))
				"trigger_zone":
					return _base(LevelData.vec3(d.get("size"), Vector3(4, 3, 4)))
				"platform":
					var s := LevelData.vec3(d.get("size"), Vector3(4, 0.5, 4))
					return AABB(Vector3(-s.x * 0.5, -s.y, -s.z * 0.5), s)
				"bridge":
					var w := float(d.get("width", 4.0))
					var l := float(d.get("length", 8.0))
					return AABB(Vector3(-w * 0.5, -0.4, -l), Vector3(w, 0.4, l))
				"hazard":
					var origin := get_pos(kind, d)
					var box := AABB()
					var first := true
					for z in d.get("zones", []):
						var zs := LevelData.vec3(z.get("size"), Vector3(16, 6, 16))
						var zp := LevelData.vec3(z.get("pos")) - origin
						var zb := AABB(zp - Vector3(zs.x * 0.5, 0, zs.z * 0.5), zs)
						box = zb if first else box.merge(zb)
						first = false
					return box if not first else _base(Vector3(4, 3, 4))
		"enemy":
			var e := Catalog.enemy(String(d.get("enemy", "")))
			var s := LevelData.vec3(e.get("size"), Vector3(0.9, 1.8, 0.9))
			var box := _base(Vector3(maxf(s.x, 0.8), s.y, maxf(s.z, 0.8)))
			box.position.y += float(e.get("hover", 0.0))
			return box
	return _base(Vector3.ONE)


static func _base(size: Vector3) -> AABB:
	return AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)
