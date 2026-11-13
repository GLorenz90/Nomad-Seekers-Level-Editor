class_name LevelNav
extends RefCounted
## The navmesh of a level (format 2), shared by the game and the level
## editor so both see exactly the same walkable space.
##
##   floor pieces      baked: the navmesh is built on top of them
##   obstacle pieces   baked as geometry (so a wall with an arch keeps its
##                     arch), then anything left standing on top of one is
##                     dropped: nothing walks on an obstacle
##   intangible        ignored
##   invisible walls   that block everyone count as obstacles
##
## The navmesh is sized for a Seeker (LevelData.NAV). Rooms and corridors are
## found by baking a second time with every room boundary cut into it: each
## separate piece of that navmesh is one area (assign_areas).
##
## Models come through a loader Callable(asset_id: String) -> Node3D, so the
## editor and the game can each load glTF their own way.

## Pieces of navmesh smaller than this (m²) are crumbs, not rooms.
const MIN_AREA := 2.0
## How far a room boundary cuts on each side of its plane (metres).
const CUT := 0.15


## A navmesh resource set up for a Seeker.
static func new_navmesh() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.agent_radius = LevelData.NAV.radius
	nm.agent_height = LevelData.NAV.height
	nm.agent_max_climb = LevelData.NAV.climb
	nm.agent_max_slope = LevelData.NAV.slope
	nm.cell_size = LevelData.NAV.cell
	nm.cell_height = LevelData.NAV.cell_height
	return nm


# --- Shapes and transforms ----------------------------------------------------------------------

## A built-in shape's meshes: [[Mesh, Transform3D], ...], pivot at the bottom
## centre. Ramps rise toward -Z.
static func builtin_meshes(asset: String, size: Vector3) -> Array:
	size = Vector3(maxf(size.x, 0.05), maxf(size.y, 0.05), maxf(size.z, 0.05))
	var up := Transform3D(Basis(), Vector3(0, size.y * 0.5, 0))
	match asset:
		"builtin:cylinder":
			var cm := CylinderMesh.new()
			cm.top_radius = size.x * 0.5
			cm.bottom_radius = size.x * 0.5
			cm.height = size.y
			if not is_equal_approx(size.x, size.z):
				return [[cm, Transform3D(Basis().scaled(Vector3(1, 1, size.z / size.x)), up.origin)]]
			return [[cm, up]]
		"builtin:ramp":
			var pm := PrismMesh.new()
			pm.left_to_right = 0.0
			pm.size = Vector3(size.z, size.y, size.x)
			return [[pm, Transform3D(Basis(Vector3.UP, PI * 0.5), up.origin)]]
		_:
			var bm := BoxMesh.new()
			bm.size = size
			return [[bm, up]]


## Where a piece (or wall, boundary, decoration) sits: pos, rot (degrees, the
## same order as a Node3D's rotation_degrees) and, for imported models, scale.
static func transform_of(spec: Dictionary) -> Transform3D:
	var rot := LevelData.vec3(spec.get("rot"), Vector3(0, float(spec.get("yaw", 0.0)), 0))
	var basis := Basis.from_euler(rot * (PI / 180.0))
	if spec.get("scale") is Array:
		var s := LevelData.vec3(spec.scale, Vector3.ONE)
		basis = basis.scaled_local(Vector3(clampf(s.x, 0.01, 100.0), clampf(s.y, 0.01, 100.0), clampf(s.z, 0.01, 100.0)))
	return Transform3D(basis, LevelData.vec3(spec.get("pos")))


## Every mesh under a model node, with its transform relative to `root`.
static func node_meshes(root: Node3D) -> Array:
	var out := []
	_walk(root, Transform3D.IDENTITY, out)
	return out


static func _walk(node: Node, xform: Transform3D, out: Array) -> void:
	for child in node.get_children():
		var t := xform
		if child is Node3D:
			t = xform * (child as Node3D).transform
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			out.append([(child as MeshInstance3D).mesh, t])
		_walk(child, t, out)


## The meshes of one piece in world space: [[Mesh, Transform3D], ...].
static func piece_meshes(piece: Dictionary, loader: Callable) -> Array:
	var asset := String(piece.get("asset", "builtin:box"))
	var local: Array
	if asset.begins_with("builtin:"):
		local = builtin_meshes(asset, LevelData.vec3(piece.get("size"), Vector3(4, 0.5, 4)))
	else:
		var model = loader.call(asset) if loader.is_valid() else null
		if model == null:
			return []
		local = node_meshes(model)
		if not (model as Node).is_inside_tree():
			(model as Node).free()
	var root := transform_of(piece)
	var out := []
	for m in local:
		out.append([m[0], root * (m[1] as Transform3D)])
	return out


## Floors and obstacles in world space: {"floors": [...], "obstacles": [...]}.
static func collect(level: LevelData, loader: Callable) -> Dictionary:
	var floors := []
	var obstacles := []
	for p in level.map.pieces:
		match level.surface_of(p):
			"floor":
				floors.append_array(piece_meshes(p, loader))
			"obstacle":
				obstacles.append_array(piece_meshes(p, loader))
	for w in level.map.walls:
		if String(w.get("blocks", "all")) == "all":
			var spec: Dictionary = (w as Dictionary).duplicate()
			spec.erase("scale")
			var box := builtin_meshes("builtin:box", LevelData.vec3(w.get("size"), Vector3(4, 4, 0.4)))
			obstacles.append([box[0][0], transform_of(spec) * (box[0][1] as Transform3D)])
	return {"floors": floors, "obstacles": obstacles}


# --- Hitboxes -----------------------------------------------------------------------------------

## A piece's collision, made from its own meshes with Godot's shape tools:
## {"xform": where the body goes (no scale), "shapes": [[Shape3D, Transform3D], ...]}.
## Scale is baked into the shapes (physics doesn't like scaled bodies), so a
## stretched model still collides where it's drawn. Empty shapes for
## intangible pieces. The game builds exactly what the editor previews.
static func hitbox(piece: Dictionary, level: LevelData, loader: Callable) -> Dictionary:
	var pose := transform_of(piece)
	var scale_v := pose.basis.get_scale()
	var body := Transform3D(pose.basis.orthonormalized(), pose.origin)
	var out := {"xform": body, "shapes": []}
	if level.surface_of(piece) == "intangible":
		return out
	var asset := String(piece.get("asset", "builtin:box"))
	var local: Array
	if asset.begins_with("builtin:"):
		local = builtin_meshes(asset, LevelData.vec3(piece.get("size"), Vector3(4, 0.5, 4)))
	else:
		var model = loader.call(asset) if loader.is_valid() else null
		if model == null:
			return out
		local = node_meshes(model)
		if not (model as Node).is_inside_tree():
			(model as Node).free()
	out.shapes = shapes_for(local, scale_v, level.hitbox_of(piece) == "convex")
	return out


## Collision shapes for meshes ([[Mesh, Transform3D], ...]), with `scale_v`
## baked in: [[Shape3D, Transform3D], ...].
static func shapes_for(local: Array, scale_v: Vector3, convex: bool) -> Array:
	var out := {"shapes": []}
	var stretch := Transform3D(Basis.from_scale(scale_v), Vector3.ZERO)
	for m in local:
		var mesh: Mesh = m[0]
		var t: Transform3D = stretch * (m[1] as Transform3D)
		var exact := t.basis.orthonormalized().is_equal_approx(t.basis)
		if mesh is BoxMesh and exact:
			var box := BoxShape3D.new()
			box.size = (mesh as BoxMesh).size
			out.shapes.append([box, t])
		elif mesh is CylinderMesh and exact:
			var cyl := CylinderShape3D.new()
			cyl.radius = (mesh as CylinderMesh).top_radius
			cyl.height = (mesh as CylinderMesh).height
			out.shapes.append([cyl, t])
		elif convex:
			var hull := mesh.create_convex_shape(true, false) as ConvexPolygonShape3D
			if hull:
				var pts := PackedVector3Array()
				for v in hull.points:
					pts.append(t * v)
				var shape := ConvexPolygonShape3D.new()
				shape.points = pts
				out.shapes.append([shape, Transform3D.IDENTITY])
		else:
			var faces := faces_of(mesh)
			if faces.is_empty():
				continue
			var world := PackedVector3Array()
			world.resize(faces.size())
			for i in faces.size():
				world[i] = t * faces[i]
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(world)
			out.shapes.append([shape, Transform3D.IDENTITY])
	return out.shapes


# --- Baking -------------------------------------------------------------------------------------

## A mesh's triangles, read once per mesh (reading them can be slow).
static var _faces := {}

static func faces_of(mesh: Mesh) -> PackedVector3Array:
	var key := mesh.get_instance_id()
	if not _faces.has(key):
		if _faces.size() > 512:
			_faces.clear()
		_faces[key] = mesh.get_faces()
	return _faces[key]


## The walkable navmesh. With `boundaries`, every room boundary also cuts it
## (only used to find rooms; the game walks the uncut one).
static func bake(level: LevelData, loader: Callable, boundaries := false, parts := {}) -> NavigationMesh:
	if parts.is_empty():
		parts = collect(level, loader)
	var src := NavigationMeshSourceGeometryData3D.new()
	for m in parts.floors + parts.obstacles:
		src.add_faces(faces_of(m[0]), m[1])
	if boundaries:
		for b in level.map.boundaries:
			_add_cut(src, b)
	var nm := new_navmesh()
	if not src.has_data():
		return nm
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	_drop_obstacle_tops(nm, parts)
	return nm


## A room boundary: a plane (local X wide, Y tall) whose footprint is cut out
## of the navmesh, CUT either side, over its own height.
static func _add_cut(src: NavigationMeshSourceGeometryData3D, b: Dictionary) -> void:
	var dims: Array = b.get("size", [8, 4]) if b.get("size") is Array else [8, 4]
	var size := Vector3(float(dims[0]), float(dims[1]) if dims.size() > 1 else 4.0, 0)
	var t := transform_of(b)
	var hw := size.x * 0.5
	var corners := [t * Vector3(-hw, 0, -CUT), t * Vector3(hw, 0, -CUT), t * Vector3(hw, size.y, -CUT), t * Vector3(-hw, size.y, -CUT),
		t * Vector3(-hw, 0, CUT), t * Vector3(hw, 0, CUT), t * Vector3(hw, size.y, CUT), t * Vector3(-hw, size.y, CUT)]
	var flat := PackedVector2Array()
	var lo := INF
	var hi := -INF
	for c in corners:
		flat.append(Vector2(c.x, c.z))
		lo = minf(lo, c.y)
		hi = maxf(hi, c.y)
	var hull := Geometry2D.convex_hull(flat)
	var verts := PackedVector3Array()
	for i in hull.size() - 1:  # convex_hull repeats the first point at the end
		verts.append(Vector3(hull[i].x, 0, hull[i].y))
	if verts.size() >= 3:
		src.add_projected_obstruction(verts, lo - 0.5, maxf(hi - lo, 0.5) + 0.5, true)


## Removes every polygon standing on an obstacle rather than a floor, or
## inside one (the hollow inside of a closed crate looks walkable to the baker).
static func _drop_obstacle_tops(nm: NavigationMesh, parts: Dictionary) -> void:
	if parts.obstacles.is_empty() or nm.get_polygon_count() == 0:
		return
	var floor_tris := _triangles(parts.floors)
	var obstacle_tris := _triangles(parts.obstacles)
	var verts := nm.get_vertices()
	var keep: Array[PackedInt32Array] = []
	for i in nm.get_polygon_count():
		var poly := nm.get_polygon(i)
		var c := Vector3.ZERO
		for idx in poly:
			c += verts[idx]
		c /= poly.size()
		var floor_y := _highest_below(floor_tris, c)
		var obstacle_y := _highest_below(obstacle_tris, c)
		if obstacle_y > floor_y + 0.05 or _inside_any(obstacle_tris, c + Vector3(0, 0.1, 0)):
			continue
		keep.append(poly)
	if keep.size() == nm.get_polygon_count():
		return
	nm.clear_polygons()
	for poly in keep:
		nm.add_polygon(poly)


## World triangles grouped per mesh with their bounds: [[AABB, PackedVector3Array], ...].
static func _triangles(meshes: Array) -> Array:
	var out := []
	for m in meshes:
		var faces := faces_of(m[0])
		var xform: Transform3D = m[1]
		var world := PackedVector3Array()
		world.resize(faces.size())
		var box := AABB()
		for i in faces.size():
			world[i] = xform * faces[i]
			box = AABB(world[i], Vector3.ZERO) if i == 0 else box.expand(world[i])
		if not world.is_empty():
			out.append([box.grow(0.01), world])
	return out


## True when a point is inside one of the meshes: a ray straight up crosses
## that mesh an odd number of times (an arch's passage is crossed twice).
static func _inside_any(groups: Array, p: Vector3) -> bool:
	for g in groups:
		var box: AABB = g[0]
		if not box.has_point(p):
			continue
		var tris: PackedVector3Array = g[1]
		var crossings := 0
		for i in range(0, tris.size() - 2, 3):
			if Geometry3D.ray_intersects_triangle(p, Vector3.UP, tris[i], tris[i + 1], tris[i + 2]) != null:
				crossings += 1
		if crossings % 2 == 1:
			return true
	return false


## The height of the highest triangle under a point (searching from 0.6 m
## above it down to 2 m below), -INF when there's none.
static func _highest_below(groups: Array, p: Vector3) -> float:
	var best := -INF
	var from := p + Vector3(0, 0.6, 0)
	for g in groups:
		var box: AABB = g[0]
		if p.x < box.position.x or p.x > box.end.x or p.z < box.position.z or p.z > box.end.z:
			continue
		if box.position.y > from.y or box.end.y < p.y - 2.0:
			continue
		var tris: PackedVector3Array = g[1]
		for i in range(0, tris.size() - 2, 3):
			var hit = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, tris[i], tris[i + 1], tris[i + 2])
			if hit != null and (hit as Vector3).y > best and (hit as Vector3).y >= p.y - 2.0:
				best = (hit as Vector3).y
	return best


# --- Pieces of navmesh ---------------------------------------------------------------------------

## The separate pieces of a navmesh (polygons joined by a shared edge), biggest
## first: [{"polys": [PackedVector3Array, ...], "size": m², "center": Vector3}].
static func islands(nm: NavigationMesh) -> Array:
	var verts := nm.get_vertices()
	var count := nm.get_polygon_count()
	var parent := range(count)
	var edges := {}
	for i in count:
		var poly := nm.get_polygon(i)
		for k in poly.size():
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if edges.has(key):
				_union(parent, i, edges[key])
			else:
				edges[key] = i
	var groups := {}
	for i in count:
		var r := _find(parent, i)
		if not groups.has(r):
			groups[r] = []
		groups[r].append(i)
	var out := []
	for r in groups:
		var polys := []
		var total := 0.0
		var biggest := -1.0
		var center := Vector3.ZERO
		for i in groups[r]:
			var idx := nm.get_polygon(i)
			var pts := PackedVector3Array()
			for v in idx:
				pts.append(verts[v])
			polys.append(pts)
			var a := _poly_area(pts)
			total += a
			if a > biggest:
				biggest = a
				center = _centroid(pts)
		out.append({"polys": polys, "size": total, "center": center})
	out.sort_custom(func(x, y): return x.size > y.size)
	return out


static func _find(parent: Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _union(parent: Array, a: int, b: int) -> void:
	parent[_find(parent, a)] = _find(parent, b)


static func _poly_area(pts: PackedVector3Array) -> float:
	var a := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		a += p.x * q.z - q.x * p.z
	return absf(a) * 0.5


static func _centroid(pts: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in pts:
		c += p
	return c / maxf(pts.size(), 1)


static func _island_has(island: Dictionary, p: Vector3) -> bool:
	for poly in island.polys:
		if LevelData.poly_contains(Array(poly), p):
			return true
	return false


## The unclaimed piece (big enough to be an area) a point stands in, or -1.
static func _island_for(list: Array, claimed: Dictionary, p: Vector3) -> int:
	for i in list.size():
		if list[i].size >= MIN_AREA and not claimed.has(i) and _island_has(list[i], p):
			return i
	return -1


## How far a point is from a piece of navmesh: 0 inside it (seen from above),
## else the distance to its nearest edge, plus any height difference.
static func _island_distance(island: Dictionary, p: Vector3) -> float:
	var best := INF
	var flat := Vector2(p.x, p.z)
	for poly in island.polys:
		if LevelData.poly_contains(Array(poly), p):
			return absf(_centroid(poly).y - p.y) if absf(_centroid(poly).y - p.y) > 3.0 else 0.0
		for k in poly.size():
			var a: Vector3 = poly[k]
			var b: Vector3 = poly[(k + 1) % poly.size()]
			var q := Geometry2D.get_closest_point_to_segment(flat, Vector2(a.x, a.z), Vector2(b.x, b.z))
			best = minf(best, q.distance_to(flat) + absf((a.y + b.y) * 0.5 - p.y))
	return best


## A soft color for the nth area: the first is blue, then well spread out.
static func area_color(n: int) -> Array:
	var c := Color.from_hsv(fmod(0.6 + n * 0.618034, 1.0), 0.55, 0.95)
	return [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001)]


## Matches the pieces of the boundary-cut navmesh to the level's areas, and
## updates map.areas: an area keeps the piece its seed point stands in (or the
## nearest free piece within 3 m), plus the pieces under its extra seeds
## ("also", for a room split by a pit); a piece nobody claims becomes a new room
## with a new color; an area whose seed lost its piece (or shares one with an
## older area, after a boundary was removed) goes. Saves each area's polygons.
## Returns {"islands": [...with "area" ("" for crumbs)], "added": [ids], "removed": [ids]}.
static func assign_areas(level: LevelData, cut: NavigationMesh) -> Dictionary:
	var list := islands(cut)
	var claimed := {}
	var kept := []
	var removed := []
	for a in level.map.areas:
		var id := String(a.get("id", ""))
		var seed := LevelData.vec3(a.get("seed"))
		var picks := []
		var pick := _island_for(list, claimed, seed)
		if pick < 0:
			var best := 3.0
			for i in list.size():
				if list[i].size >= MIN_AREA and not claimed.has(i):
					var d := _island_distance(list[i], seed)
					if d < best:
						best = d
						pick = i
		if pick < 0:
			removed.append(id)
			continue
		picks.append(pick)
		if not _island_has(list[pick], seed):
			a.seed = _arr(list[pick].center)
		# Extra seeds join more pieces into this area (a room split by a pit).
		var also := []
		for extra in a.get("also", []):
			var more := _island_for(list, claimed, LevelData.vec3(extra))
			if more >= 0 and not picks.has(more):
				picks.append(more)
				also.append(extra)
		if also.is_empty():
			a.erase("also")
		else:
			a.also = also
		for i in picks:
			claimed[i] = id
		kept.append(a)
	var added := []
	var taken := level.ids()
	var made: int = level.map.areas.size() + removed.size()
	for i in list.size():
		if claimed.has(i) or list[i].size < MIN_AREA:
			continue
		var n := 1
		while taken.has("room_%d" % n):
			n += 1
		var id := "room_%d" % n
		taken[id] = "room"
		kept.append({"id": id, "kind": "room", "name": "", "seed": _arr(list[i].center), "color": area_color(made)})
		made += 1
		claimed[i] = id
		added.append(id)
	for a in kept:
		var polys := []
		for i in list.size():
			if claimed.get(i, "") == String(a.id):
				for poly in list[i].polys:
					var pts := []
					for v in poly:
						pts.append(_arr(v))
					polys.append(pts)
		a.polys = polys
	level.map.areas = kept
	for i in list.size():
		list[i].area = claimed.get(i, "")
	return {"islands": list, "added": added, "removed": removed}


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
