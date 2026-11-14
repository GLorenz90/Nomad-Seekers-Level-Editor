class_name ItemVisuals
extends RefCounted
## What each item looks like in the editor's 3D view. These are stand-ins
## drawn by the editor (the game draws its own), sized like the real thing
## so placement is accurate. Imported models are the real models.

const ELEMENT_COLORS := {"fire": Color(1.0, 0.4, 0.2), "ice": Color(0.5, 0.85, 1.0), "lightning": Color(1.0, 0.95, 0.3),
	"nature": Color(0.4, 0.9, 0.35), "light": Color(1.0, 1.0, 0.85), "dark": Color(0.55, 0.3, 0.8), "raw": Color(0.9, 0.9, 0.95)}


## The node for an item, already placed. `named` adds a floating name tag.
static func build(kind: String, d: Dictionary, doc: EditorDoc, named := false, _layer := 1) -> Node3D:
	var root := Node3D.new()
	root.transform = Items.xform(kind, d)
	var id := String(d.get("id", ""))
	var tag := ""
	var tag_y := 2.0
	match kind:
		"start":
			root.add_child(_at(_capsule(0.4, 1.8, Color(0.25, 0.9, 0.45)), Vector3(0, 0.9, 0)))
			root.add_child(_at(_box(Vector3(0.25, 0.25, 0.9), Color(0.25, 0.9, 0.45)), Vector3(0, 1.2, -0.6)))
			tag = "START"
			tag_y = 2.3
		"wall":
			# Invisible things get a faint box so they're easy to see and grab.
			var s := LevelData.vec3(d.get("size"), Vector3(4, 4, 0.4))
			var seekers := String(d.get("blocks", "all")) == "seekers"
			var c := Color(1.0, 0.6, 0.2) if seekers else Color(1.0, 0.35, 0.35)
			root.add_child(_at(_box(s, c, 0.14), Vector3(0, s.y * 0.5, 0)))
			root.add_child(lines(box_edges(AABB(Vector3(-s.x * 0.5, 0, -s.z * 0.5), s)), Color(c, 0.55)))
			tag = "Seekers only" if seekers else "Invisible wall"
			tag_y = s.y + 0.4
		"boundary":
			var dims: Array = d.get("size", [4, 4])
			var w := float(dims[0])
			var h := float(dims[1]) if dims.size() > 1 else 4.0
			var c := Color(0.85, 0.5, 1.0)
			root.add_child(_at(_box(Vector3(w, h, 0.04), c, 0.12), Vector3(0, h * 0.5, 0)))
			root.add_child(lines(box_edges(AABB(Vector3(-w * 0.5, 0, -0.05), Vector3(w, h, 0.1))), Color(c, 0.6)))
			tag_y = h + 0.4  # no name tag: the faint plane says enough
		"piece", "decoration":
			_build_model(root, kind, d, doc)
			if kind == "decoration":
				tag = Catalog.type_name(kind, d)
				tag_y = Items.local_aabb(kind, d, doc.level).end.y + 0.4
				named = false  # decorations stay quiet
		"object":
			tag = Catalog.label(kind, d, id)
			tag_y = _build_object(root, d, doc) + 0.5
		"enemy":
			var e := Catalog.enemy(String(d.get("enemy", "")))
			var s := LevelData.vec3(e.get("size"), Vector3(0.9, 1.8, 0.9))
			var c: Array = e.get("color", [0.9, 0.2, 0.9])
			var color := Color(float(c[0]), float(c[1]), float(c[2])) if not e.is_empty() else Color(1, 0, 1)
			var lift := s.y * 0.5 + float(e.get("hover", 0.0))
			var body: MeshInstance3D
			match int(e.get("shape", 0)):
				1:
					body = _box(s, color)
				2:
					body = _sphere(s.x * 0.5, s.y, color)
				_:
					body = _capsule(s.x * 0.5, maxf(s.y, s.x), color)
			root.add_child(_at(body, Vector3(0, lift, 0)))
			root.add_child(_at(_box(Vector3(s.x * 0.6, 0.12, 0.12), Color(0.05, 0.05, 0.08)), Vector3(0, lift + s.y * 0.2, -s.z * 0.5)))
			var slot := doc.enemy_slot(id)
			tag = Catalog.type_name(kind, d)
			if not slot.is_empty():
				tag += "\nwave %d" % (int(slot.wave) + 1) if int(slot.wave) >= 0 else "\nalways there"
			if LevelData.placement_problem(d) != "":
				tag += "\n! needs fixing"
			tag_y = lift + s.y * 0.5 + 0.5
	if named and tag != "":
		var warn := tag.contains("! needs fixing")
		root.add_child(_at(_label(tag, Color(1.0, 0.45, 0.4) if warn else Color.WHITE), Vector3(0, tag_y, 0)))
	return root


static func _build_model(root: Node3D, _kind: String, d: Dictionary, doc: EditorDoc) -> void:
	var asset := String(d.get("asset", "builtin:box"))
	var size := LevelData.vec3(d.get("size"), Vector3(4, 1, 4))
	var color := _color(d.get("color"), Color(0.55, 0.57, 0.6))
	var painted: Material = LevelMaterials.build(doc.level, String(d.get("material", ""))) if doc else null
	match asset:
		"builtin:box", "builtin:cylinder", "builtin:ramp", "builtin:curved_wall", "builtin:stairs":
			# The same shapes the game and the navmesh use, in its material or color.
			var mat: Material = painted if painted else material(color)
			for m in LevelNav.builtin_meshes(asset, size, LevelNav.shape_params(d)):
				var mi := MeshInstance3D.new()
				mi.mesh = m[0]
				mi.material_override = mat
				mi.transform = m[1]
				root.add_child(mi)
		"builtin:fireflies":
			var glow := _color(d.get("color"), Color(1.0, 0.95, 0.5))
			root.add_child(_at(_box(size, glow, 0.06), Vector3(0, size.y * 0.5, 0)))
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(String(d.get("id", "")))
			for i in mini(int(d.get("amount", 24)), 40):
				var dot := _sphere(0.05, 0.1, glow, true)
				root.add_child(_at(dot, Vector3(rng.randf_range(-0.5, 0.5) * size.x, rng.randf() * size.y, rng.randf_range(-0.5, 0.5) * size.z)))
		"builtin:light":
			var glow := _color(d.get("color"), Color(1.0, 0.85, 0.6))
			root.add_child(_sphere(0.25, 0.5, glow, true))
			var light := OmniLight3D.new()
			light.light_color = glow
			light.light_energy = clampf(float(d.get("energy", 1.0)), 0.0, 3.0)
			light.omni_range = clampf(float(d.get("range", 6.0)), 1.0, 20.0)
			root.add_child(light)
		"builtin:searchlight":
			var glow := _color(d.get("color"), Color(1.0, 0.95, 0.8))
			root.add_child(_box(Vector3(0.6, 0.6, 0.8), Color(0.3, 0.3, 0.35)))
			var spot := SpotLight3D.new()
			spot.light_color = glow
			spot.light_energy = clampf(float(d.get("energy", 2.0)), 0.0, 4.0)
			spot.spot_range = clampf(float(d.get("range", 18.0)), 2.0, 30.0)
			spot.spot_angle = 18.0
			spot.rotation_degrees.x = -25.0
			root.add_child(spot)
		_:
			var model := Models.instance(doc.level, asset)
			if model:
				if painted:
					for mi in model.find_children("*", "MeshInstance3D", true, false):
						(mi as MeshInstance3D).material_override = painted
				root.add_child(model)
			else:
				root.add_child(_at(_box(Vector3.ONE, Color(1, 0, 1)), Vector3(0, 0.5, 0)))
				root.add_child(_at(_label("missing model\n" + asset, Color(1, 0.5, 1)), Vector3(0, 1.6, 0)))


## Returns the height of the object's top (for its name tag).
static func _build_object(root: Node3D, d: Dictionary, doc: EditorDoc) -> float:
	match String(d.get("type", "")):
		"door":
			var s := LevelData.vec3(d.get("size"), Vector3(4.2, 4.0, 0.6))
			var open := String(d.get("start", "closed")) == "open"
			root.add_child(_at(_box(s, Color(0.25, 0.55, 1.0), 0.25 if open else 0.7), Vector3(0, s.y * 0.5, 0)))
			return s.y
		"teleporter":
			var asleep := bool(d.get("dormant", false))
			var color := Color(0.3, 0.35, 0.4) if asleep else (Color(0.55, 1.0, 0.55) if String(d.get("destination", "")) != "" else Color(0.3, 0.9, 1.0))
			var mesh := CylinderMesh.new()
			mesh.top_radius = 1.4
			mesh.bottom_radius = 1.5
			mesh.height = 0.12
			root.add_child(_at(_mesh(mesh, color, 1.0, true), Vector3(0, 0.06, 0)))
			return 1.6
		"lumidium_depot":
			root.add_child(_at(_prism(Vector3(0.8, 1.2, 0.8), Color(0.65, 0.5, 1.0)), Vector3(0, 0.9, 0)))
			root.add_child(_at(_box(Vector3(1.0, 0.3, 1.0), Color(0.3, 0.3, 0.4)), Vector3(0, 0.15, 0)))
			return 1.6
		"lumidium_node":
			root.add_child(_at(_prism(Vector3(1.0, 1.5, 1.0), ELEMENT_COLORS.get(String(d.get("color", "fire")), Color.WHITE)), Vector3(0, 0.75, 0)))
			return 1.5
		"box":
			root.add_child(_at(_box(Vector3(0.95, 0.95, 0.95), Color(0.75, 0.6, 0.3)), Vector3(0, 0.5, 0)))
			return 1.0
		"trap":
			var mesh := CylinderMesh.new()
			mesh.top_radius = 1.2
			mesh.bottom_radius = 1.2
			mesh.height = 0.06
			root.add_child(_at(_mesh(mesh, Color(1.0, 0.25, 0.2), 0.55), Vector3(0, 0.03, 0)))
			root.add_child(_at(_box(Vector3(0.3, 0.3, 0.3), Color(0.9, 0.2, 0.2)), Vector3(0, 0.15, 0)))
			return 0.8
		"button":
			if String(d.get("mode", "press")) == "floor":
				root.add_child(_at(_box(Vector3(1.3, 0.08, 1.3), Color(1.0, 0.35, 0.25)), Vector3(0, 0.04, 0)))
				return 0.5
			root.add_child(_at(_box(Vector3(0.5, 1.0, 0.5), Color(1.0, 0.35, 0.25)), Vector3(0, 0.5, 0)))
			return 1.2
		"trigger_zone":
			var s := LevelData.vec3(d.get("size"), Vector3(4, 3, 4))
			root.add_child(_at(_box(s, Color(1.0, 0.9, 0.2), 0.18), Vector3(0, s.y * 0.5, 0)))
			root.add_child(_outline(s, Color(1.0, 0.9, 0.2)))
			return s.y
		"hazard":
			var origin := Items.get_pos("object", d)
			var dark := String(d.get("kind", "")) == "darkness"
			var top := 1.0
			for z in d.get("zones", []):
				var s := LevelData.vec3(z.get("size"), Vector3(16, 6, 16))
				var at := LevelData.vec3(z.get("pos")) - origin
				root.add_child(_at(_box(s, Color(0.05, 0.05, 0.1) if dark else Color(0.45, 0.85, 0.25), 0.35 if dark else 0.2), at + Vector3(0, s.y * 0.5, 0)))
				top = maxf(top, s.y)
			return top
		"platform":
			var s := LevelData.vec3(d.get("size"), Vector3(4, 0.5, 4))
			var color := _color(d.get("color"), Color(0.45, 0.5, 0.6))
			root.add_child(_at(_box(s, color), Vector3(0, -s.y * 0.5, 0)))
			var pts: Array = d.get("points", [])
			var origin := Items.get_pos("object", d)
			var line := PackedVector3Array()
			for i in pts.size():
				var p := LevelData.vec3(pts[i]) - origin
				if i > 0:
					line.append(LevelData.vec3(pts[i - 1]) - origin + Vector3(0, 0.1, 0))
					line.append(p + Vector3(0, 0.1, 0))
					root.add_child(_at(_box(s, color, 0.25), p + Vector3(0, -s.y * 0.5, 0)))
				root.add_child(_at(_label("stop %d" % (i + 1), Color(0.8, 0.9, 1.0), 20), p + Vector3(0, 0.6, 0)))
			if not line.is_empty():
				root.add_child(lines(line, Color(0.6, 0.85, 1.0)))
			return 1.0
		"person":
			var look: Dictionary = d.get("look", {}) if d.get("look") is Dictionary else {}
			var height := clampf(float(look.get("height", 1.8)), 0.5, 4.0)
			var model_id := String(look.get("model", ""))
			var model: Node3D = doc.model_loader().call(model_id) if model_id != "" else null
			if model:
				root.add_child(model)
			else:
				root.add_child(_at(_capsule(0.32, height * 0.78, _color(look.get("color"), Color(0.45, 0.55, 0.75))), Vector3(0, height * 0.39, 0)))
				root.add_child(_at(_sphere(height * 0.11, height * 0.22, Color(0.86, 0.72, 0.6)), Vector3(0, height * 0.88, 0)))
			root.add_child(_at(_box(Vector3(0.12, 0.12, 0.4), Color(1, 1, 1, 0.8)), Vector3(0, height * 0.88, -0.3)))
			var route: Dictionary = d.get("route", {}) if d.get("route") is Dictionary else {}
			var pts: Array = route.get("points", [])
			if pts.size() >= 2:
				var inv := root.transform.affine_inverse()
				var line := PackedVector3Array()
				for i in pts.size():
					var p := inv * (LevelData.vec3(pts[i]) + Vector3(0, 0.15, 0))
					var q := inv * (LevelData.vec3(pts[(i + 1) % pts.size()]) + Vector3(0, 0.15, 0))
					if i < pts.size() - 1 or String(route.get("mode", "loop")) == "loop":
						line.append(p)
						line.append(q)
					root.add_child(_at(_label("walk %d" % (i + 1), Color(0.9, 0.85, 0.6), 18), p + Vector3(0, 0.4, 0)))
				root.add_child(lines(line, Color(0.95, 0.8, 0.4)))
			return height
		"bridge":
			var w := float(d.get("width", 4.0))
			var l := float(d.get("length", 8.0))
			root.add_child(_at(_box(Vector3(w, 0.4, l), Color(0.55, 0.45, 0.35), 1.0 if bool(d.get("extended", false)) else 0.4), Vector3(0, -0.2, -l * 0.5)))
			root.add_child(_at(_box(Vector3(w, 0.5, 0.3), Color(0.4, 0.3, 0.25)), Vector3(0, -0.2, 0)))
			return 0.8
	root.add_child(_at(_box(Vector3.ONE, Color(1, 0, 1)), Vector3(0, 0.5, 0)))
	return 1.0


# --- Small builders ---------------------------------------------------------------------------

static func _color(v: Variant, fallback: Color) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return fallback


static func material(color: Color, alpha := 1.0, glow := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.8
	return mat


## Unshaded, see-through, colored per vertex (the navmesh overlay).
static func nav_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat


static func _mesh(mesh: PrimitiveMesh, color: Color, alpha := 1.0, glow := false) -> MeshInstance3D:
	mesh.material = material(color, alpha, glow)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if alpha < 1.0:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _box(size: Vector3, color: Color, alpha := 1.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(mesh, color, alpha)


static func _capsule(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	return _mesh(mesh, color)


static func _sphere(radius: float, height: float, color: Color, glow := false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	return _mesh(mesh, color, 1.0, glow)


static func _prism(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = size
	return _mesh(mesh, color, 1.0, true)


static func _at(node: Node3D, pos: Vector3) -> Node3D:
	node.position = pos
	return node


static func _label(text: String, color := Color.WHITE, font_size := 26) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = font_size
	label.outline_size = 8
	label.modulate = color
	label.render_priority = 10
	return label


## A line mesh from pairs of points.
static func lines(points: PackedVector3Array, color: Color, on_top := false) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = on_top
	if on_top:
		mat.render_priority = 5
	if points.size() >= 2:
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		for p in points:
			mesh.surface_add_vertex(p)
		mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The 12 edges of a box, as line pairs.
static func box_edges(box: AABB) -> PackedVector3Array:
	var p := box.position
	var e := box.end
	var c := [Vector3(p.x, p.y, p.z), Vector3(e.x, p.y, p.z), Vector3(e.x, p.y, e.z), Vector3(p.x, p.y, e.z),
		Vector3(p.x, e.y, p.z), Vector3(e.x, e.y, p.z), Vector3(e.x, e.y, e.z), Vector3(p.x, e.y, e.z)]
	var out := PackedVector3Array()
	for pair in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		out.append(c[pair[0]])
		out.append(c[pair[1]])
	return out


## A footprint rectangle on the floor.
static func _outline(size: Vector3, color: Color) -> MeshInstance3D:
	var h := Vector3(size.x * 0.5, 0.03, size.z * 0.5)
	var c := [Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	return lines(PackedVector3Array([c[0], c[1], c[1], c[2], c[2], c[3], c[3], c[0]]), color)


## A flat circle of the given radius (for wander and chase rings).
static func ring(radius: float, color: Color) -> MeshInstance3D:
	var pts := PackedVector3Array()
	var steps := 64
	for i in steps:
		var a := TAU * i / steps
		var b := TAU * (i + 1) / steps
		pts.append(Vector3(cos(a), 0, sin(a)) * radius)
		pts.append(Vector3(cos(b), 0, sin(b)) * radius)
	return lines(pts, color, true)
