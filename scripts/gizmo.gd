class_name TransformGizmo
extends Node3D
## Godot-style handles on the selected item, drawn on top of everything.
##
##   Move (W)     arrows along each axis, and squares that slide it across a
##                plane (XY, XZ, YZ). Global or local axes (T).
##   Rotate (E)   a ring around each axis (snaps to 15°). Global or local (T).
##   Resize (R)   two styles (press R again to switch):
##                  from centre: a handle per axis and a middle cube that
##                    resizes evenly
##                  by sides: the item is a box with sliding faces. A handle on
##                    each face pulls that face out or in (the opposite face
##                    stays put); a handle on each corner scales the box toward
##                    that corner (the opposite corner stays put).
##                Resizing always follows the item's own axes.
##
## Snapping follows the editor's snap setting; hold Alt to turn it off. The
## view hands it mouse events: hit() says whether a handle is under the mouse;
## start(), drag() and finish() do the work on the item's data.

enum Mode { SELECT, MOVE, ROTATE, SCALE }

const COLORS := [Color(0.96, 0.33, 0.35), Color(0.55, 0.88, 0.25), Color(0.3, 0.55, 1.0)]
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const PICK_PX := 10.0
## Handle length as a share of the camera distance.
const SIZE := 0.13
## Plane squares: [handle, axis a, axis b, axis of the normal].
const PLANES := [["yz", 1, 2, 0], ["xz", 0, 2, 1], ["xy", 0, 1, 2]]

var mode := Mode.MOVE
## Move and rotate along the item's own axes instead of the world's.
var local := false
## Resize by sliding faces (and corners) instead of from the centre.
var scale_sides := false
var camera: Camera3D
var doc: EditorDoc
var snap_step := 0.5

var _id := ""
var _kind := ""
var _handle := ""
var _hover := ""
var _start := {}
var _mat_cache := {}
## Side handles: [{"handle", "pos" (world), "node"}], sized every frame.
var _points := []
var _last_t := 0.0


func _ready() -> void:
	visible = false  # nothing selected yet


## Redraws the handles around the selected item (or hides them).
func refresh() -> void:
	for child in get_children():
		child.free()
	_points = []
	var it := doc.item(doc.selected) if doc else {}
	_id = String(it.get("id", ""))
	_kind = String(it.get("kind", ""))
	visible = false
	if it.is_empty() or mode == Mode.SELECT or not Items.movable(_kind):
		return
	if mode == Mode.ROTATE and not Items.has_yaw(_kind, it.data):
		return
	if mode == Mode.SCALE and not Items.resizable(_kind, it.data):
		return
	visible = true
	_fit()
	if sides_active():
		_draw_sides(it)
	else:
		_draw(it)


## Whether the by-sides handles are showing.
func sides_active() -> bool:
	if mode != Mode.SCALE or not scale_sides:
		return false
	var it := doc.item(_id)
	return not it.is_empty() and Items.sides_resizable(it.kind, it.data)


func _process(_delta: float) -> void:
	if visible:
		_fit()


## The axes the handles use: the item's own (local, and always for
## resizing) or the world's.
func frame() -> Basis:
	var it := doc.item(_id)
	if it.is_empty():
		return Basis()
	if local or mode == Mode.SCALE:
		return Items.xform(it.kind, it.data).basis.orthonormalized()
	return Basis()


## How big the handles are: the same size on screen at any distance.
func _screen_size(at: Vector3) -> float:
	if camera == null:
		return 1.0
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return camera.size * SIZE
	return camera.global_position.distance_to(at) * SIZE


## Places the handles at the item, turned to the frame, sized for the screen.
func _fit() -> void:
	if camera == null or doc == null or not is_inside_tree():
		return
	var it := doc.item(_id)
	if it.is_empty():
		return
	var origin := Items.get_pos(it.kind, it.data)
	transform = Transform3D(frame() * Basis.from_scale(Vector3.ONE * maxf(_screen_size(origin), 0.01)), origin)
	for p in _points:
		var node: Node3D = p.node
		node.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * maxf(_screen_size(p.pos), 0.01)), p.pos)


# --- Drawing ----------------------------------------------------------------------------------

func _draw(it: Dictionary) -> void:
	match mode:
		Mode.MOVE:
			for i in 3:
				var axis: Vector3 = AXES[i]
				_line(axis * 0.12, axis * 0.8, "xyz"[i], COLORS[i])
				_arrow_tip(axis, "xyz"[i], COLORS[i])
			for pl in PLANES:
				_quad(_plane_corners(pl), pl[0], COLORS[pl[3]])
		Mode.ROTATE:
			var rings := [0, 1, 2] if Items.full_rot(it.kind) else [1]
			for i in rings:
				var pts := PackedVector3Array()
				var a := AXES[(i + 1) % 3] as Vector3
				var b := AXES[(i + 2) % 3] as Vector3
				for k in 64:
					var t0 := TAU * k / 64.0
					var t1 := TAU * (k + 1) / 64.0
					pts.append((a * cos(t0) + b * sin(t0)) * 0.9)
					pts.append((a * cos(t1) + b * sin(t1)) * 0.9)
				_lines(pts, "r" + "xyz"[i], COLORS[i])
		Mode.SCALE:
			for i in 3:
				_line(Vector3.ZERO, AXES[i], "s" + "xyz"[i], COLORS[i])
				_cube(AXES[i], 0.07, "s" + "xyz"[i], COLORS[i])
			_cube(Vector3.ZERO, 0.08, "s", Color(0.9, 0.9, 0.9))


func _plane_corners(pl: Array) -> Array:
	var a: Vector3 = AXES[pl[1]]
	var b: Vector3 = AXES[pl[2]]
	return [a * 0.2 + b * 0.2, a * 0.42 + b * 0.2, a * 0.42 + b * 0.42, a * 0.2 + b * 0.42]


## The box outline plus a handle on every face and corner (world space).
func _draw_sides(it: Dictionary) -> void:
	var xf := _box_xform(it)
	var box := Items.sized_box(it.kind, it.data, doc.level)
	var outline := PackedVector3Array()
	for p in ItemVisuals.box_edges(box):
		outline.append(xf * p)
	_world_lines(outline, Color(1.0, 0.85, 0.3, 0.7))
	for h in side_handles(box, Items.resize_axes(it.kind, it.data)):
		var face := String(h.handle).begins_with("f")
		var color: Color = COLORS["xyz".find(String(h.handle)[2])] if face else Color(0.92, 0.92, 0.92)
		var mi := _make_cube(0.05 if face else 0.04, _color_for(h.handle, color))
		mi.top_level = true
		add_child(mi)
		_points.append({"handle": h.handle, "pos": xf * (h.local as Vector3), "node": mi})
	_fit()


## Face and corner handles of a box: [{"handle", "local"}]. Faces are
## "f+x", "f-x"...; corners "c+-+" (a sign per axis). An axis that can't be
## resized (a boundary's thickness) gets no faces, and corners mark it "0".
static func side_handles(box: AABB, axes: Array) -> Array:
	var out := []
	var c := box.get_center()
	for i in 3:
		if axes[i]:
			for sgn in [1, -1]:
				var p := c
				p[i] = box.end[i] if sgn > 0 else box.position[i]
				out.append({"handle": "f%s%s" % ["+" if sgn > 0 else "-", "xyz"[i]], "local": p})
	var signs_per_axis := []
	for i in 3:
		signs_per_axis.append([1, -1] if axes[i] else [0])
	for sx in signs_per_axis[0]:
		for sy in signs_per_axis[1]:
			for sz in signs_per_axis[2]:
				var signs := [sx, sy, sz]
				var p := c
				var name := "c"
				for i in 3:
					if signs[i] != 0:
						p[i] = box.end[i] if signs[i] > 0 else box.position[i]
					name += "+" if signs[i] > 0 else ("-" if signs[i] < 0 else "0")
				out.append({"handle": name, "local": p})
	return out


## The item's own frame in metres: where it is and how it's turned, no scale.
func _box_xform(it: Dictionary) -> Transform3D:
	var xf := Items.xform(it.kind, it.data)
	return Transform3D(xf.basis.orthonormalized(), xf.origin)


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.render_priority = 10
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_cache[key] = m
	return _mat_cache[key]


func _color_for(handle: String, color: Color) -> Color:
	return Color(1.0, 0.95, 0.4) if handle == _hover or handle == _handle else color


func _line(a: Vector3, b: Vector3, handle: String, color: Color) -> void:
	_lines(PackedVector3Array([a, b]), handle, color)


func _lines(pts: PackedVector3Array, handle: String, color: Color) -> void:
	add_child(_line_mesh(pts, _color_for(handle, color)))


func _world_lines(pts: PackedVector3Array, color: Color) -> void:
	var mi := _line_mesh(pts, color)
	mi.top_level = true
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY


func _line_mesh(pts: PackedVector3Array, color: Color) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material(color))
	for p in pts:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A cone pointing along an axis, at the end of a move arrow.
func _arrow_tip(axis: Vector3, handle: String, color: Color) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.065
	cone.height = 0.24
	cone.radial_segments = 16
	cone.rings = 1
	cone.material = _material(_color_for(handle, color))
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A cylinder points up (+Y); turn it to the axis.
	var b := Basis()
	if axis == Vector3.RIGHT:
		b = Basis(Vector3.BACK, -PI * 0.5)
	elif axis == Vector3.BACK:
		b = Basis(Vector3.RIGHT, PI * 0.5)
	mi.transform = Transform3D(b, axis * 0.92)
	add_child(mi)


## A see-through square with an outline (a plane handle).
func _quad(corners: Array, handle: String, color: Color) -> void:
	var c := _color_for(handle, color)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color(c, 0.6 if handle == _hover or handle == _handle else 0.3)))
	for idx in [0, 1, 2, 0, 2, 3]:
		mesh.surface_add_vertex(corners[idx])
	mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var edge := PackedVector3Array()
	for k in 4:
		edge.append(corners[k])
		edge.append(corners[(k + 1) % 4])
	_lines(edge, handle, color)


func _make_cube(half: float, color: Color) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * half * 2.0
	box.material = _material(color)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _cube(at: Vector3, half: float, handle: String, color: Color) -> void:
	var mi := _make_cube(half, _color_for(handle, color))
	mi.position = at
	add_child(mi)


# --- Picking ------------------------------------------------------------------------------------

## The handle under the mouse ("" for none). Also lights it up.
func hit(at: Vector2) -> String:
	if not visible or camera == null or doc.item(_id).is_empty():
		return ""
	var best := _pick(at)
	if best != _hover:
		_hover = best
		refresh()
	return best


## Where a handle is on screen (for tests and tooltips); Vector2.INF if none.
func handle_screen_pos(handle: String) -> Vector2:
	for p in _points:
		if p.handle == handle:
			return camera.unproject_position(p.pos)
	return Vector2.INF


func _pick(at: Vector2) -> String:
	if sides_active():
		var best := ""
		var best_d := PICK_PX * 1.3
		for p in _points:
			if camera.is_position_behind(p.pos):
				continue
			var d := camera.unproject_position(p.pos).distance_to(at)
			if d < best_d:
				best_d = d
				best = p.handle
		return best
	var best := ""
	var best_d := PICK_PX
	for seg in _segments():
		var a := camera.unproject_position(global_transform * (seg[0] as Vector3))
		var b := camera.unproject_position(global_transform * (seg[1] as Vector3))
		var d := Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at)
		if d < best_d:
			best_d = d
			best = seg[2]
	if best != "":
		return best
	if mode == Mode.MOVE:
		for pl in PLANES:
			var poly := PackedVector2Array()
			for corner in _plane_corners(pl):
				poly.append(camera.unproject_position(global_transform * (corner as Vector3)))
			if Geometry2D.is_point_in_polygon(at, poly):
				return pl[0]
	if mode == Mode.SCALE and camera.unproject_position(global_position).distance_to(at) < PICK_PX * 1.4:
		return "s"
	return ""


## Screen-pickable lines of every handle: [[from, to, handle], ...] (local).
func _segments() -> Array:
	var out := []
	match mode:
		Mode.MOVE:
			for i in 3:
				out.append([AXES[i] * 0.15, AXES[i] * 1.05, "xyz"[i]])
		Mode.ROTATE:
			var it := doc.item(_id)
			var rings := [0, 1, 2] if Items.full_rot(it.kind) else [1]
			for i in rings:
				var a := AXES[(i + 1) % 3] as Vector3
				var b := AXES[(i + 2) % 3] as Vector3
				for k in 32:
					var t0 := TAU * k / 32.0
					var t1 := TAU * (k + 1) / 32.0
					out.append([(a * cos(t0) + b * sin(t0)) * 0.9, (a * cos(t1) + b * sin(t1)) * 0.9, "r" + "xyz"[i]])
		Mode.SCALE:
			for i in 3:
				out.append([AXES[i] * 0.2, AXES[i] * 1.05, "s" + "xyz"[i]])
	return out


# --- Dragging -----------------------------------------------------------------------------------

func is_dragging() -> bool:
	return _handle != ""


func start(handle: String, at: Vector2) -> void:
	var it := doc.item(_id)
	if it.is_empty():
		return
	_handle = handle
	var d: Dictionary = it.data
	_start = {"pos": Items.get_pos(_kind, d), "rot": Items.get_rot(_kind, d), "frame": frame(),
		"basis": Items.xform(_kind, d).basis.orthonormalized(), "size": Items.get_size(_kind, d, doc.level),
		"box": Items.sized_box(_kind, d, doc.level), "mouse": at, "origin": Items.get_pos(_kind, d)}
	_start.grab = _grab(handle, at)


func drag(at: Vector2, no_snap: bool) -> void:
	if _handle == "":
		return
	var d := doc.find(_id)
	if d.is_empty():
		return
	var origin: Vector3 = _start.origin
	var f: Basis = _start.frame
	var snap := snap_step > 0.0 and not no_snap
	if _handle in ["x", "y", "z"]:
		var axis := f * (AXES["xyz".find(_handle)] as Vector3)
		var delta := _axis_t(axis, origin, at) - float(_start.grab)
		if snap:
			delta = snappedf(delta, snap_step)
		Items.set_pos(_kind, d, _start.pos + axis * delta)
	elif _handle in ["xy", "xz", "yz"]:
		var pl: Array = _plane(_handle)
		var hit := _plane_hit(f * (AXES[pl[3]] as Vector3), origin, at)
		if hit == Vector3.INF or _start.grab == Vector3.INF:
			return
		var local_delta: Vector3 = f.inverse() * (hit - (_start.grab as Vector3))
		local_delta[pl[3]] = 0.0
		if snap:
			local_delta = local_delta.snapped(Vector3.ONE * snap_step)
		Items.set_pos(_kind, d, _start.pos + f * local_delta)
	elif _handle in ["rx", "ry", "rz"]:
		var axis := f * (AXES["xyz".find(_handle[1])] as Vector3)
		var hit := _plane_hit(axis, origin, at)
		if hit == Vector3.INF or _start.grab == Vector3.INF:
			return
		var angle := ((_start.grab as Vector3) - origin).signed_angle_to(hit - origin, axis)
		if not no_snap:
			angle = snappedf(angle, deg_to_rad(15.0))
		var basis: Basis = Basis(axis.normalized(), angle) * (_start.basis as Basis)
		if Items.full_rot(_kind):
			Items.set_rot(_kind, d, basis.get_euler() * (180.0 / PI))
		else:
			Items.set_rot(_kind, d, Vector3(0, (_start.rot as Vector3).y + rad_to_deg(angle), 0))
	elif _handle in ["sx", "sy", "sz"]:
		var i := "xyz".find(_handle[1])
		var g := float(_start.grab)
		if absf(g) < 0.001:
			return
		var size: Vector3 = _start.size
		var v := maxf(size[i] * _axis_t(f * (AXES[i] as Vector3), origin, at) / g, 0.05)
		if snap:
			v = maxf(snappedf(v, snap_step), snap_step)
		size[i] = v
		Items.set_size(_kind, d, doc.level, size)
	elif _handle == "s":
		var dy: float = (_start.mouse as Vector2).y - at.y
		Items.set_size(_kind, d, doc.level, (_start.size as Vector3) * clampf(1.0 + dy / 150.0, 0.05, 20.0))
	elif _handle.begins_with("f"):
		_drag_face(d, at, snap)
	elif _handle.begins_with("c"):
		_drag_corner(d, at, snap)


func _plane(handle: String) -> Array:
	for pl in PLANES:
		if pl[0] == handle:
			return pl
	return PLANES[1]


## A face slides along its axis; the opposite face stays put.
func _drag_face(d: Dictionary, at: Vector2, snap: bool) -> void:
	var i := "xyz".find(_handle[2])
	var sgn := 1.0 if _handle[1] == "+" else -1.0
	var box: AABB = _start.box
	var delta := _face_t(_handle, at) - float(_start.grab)
	if snap:
		delta = snappedf(delta, snap_step)
	var lo := box.position
	var hi := box.end
	if sgn > 0:
		hi[i] = maxf(hi[i] + delta, lo[i] + 0.05)
	else:
		lo[i] = minf(lo[i] - delta, hi[i] - 0.05)
	_apply_box(d, AABB(lo, hi - lo))


## A corner scales the box toward it; the opposite corner stays put.
func _drag_corner(d: Dictionary, at: Vector2, snap: bool) -> void:
	var box: AABB = _start.box
	var ends := _corner_ends(_handle, box)
	var fixed: Vector3 = ends[0]
	var moving: Vector3 = ends[1]
	var factor := maxf(_corner_t(_handle, at) / maxf(float(_start.grab), 0.001), 0.02)
	if snap:
		# Snap the biggest side; the others follow, keeping the proportions.
		var span := (moving - fixed).abs()
		var big := 0 if span.x >= span.y and span.x >= span.z else (1 if span.y >= span.z else 2)
		factor = maxf(snappedf(span[big] * factor, snap_step), snap_step) / maxf(span[big], 0.001)
	var target := fixed + (moving - fixed) * factor
	var lo := box.position
	var hi := box.end
	for i in 3:
		if _handle[1 + i] != "0":
			lo[i] = minf(fixed[i], target[i])
			hi[i] = maxf(fixed[i], target[i])
	_apply_box(d, AABB(lo, (hi - lo).max(Vector3.ONE * 0.05)))


## A corner's opposite (fixed) corner and itself, in the item's frame.
## Axes marked "0" don't move.
static func _corner_ends(handle: String, box: AABB) -> Array:
	var fixed := box.get_center()
	var moving := box.get_center()
	for i in 3:
		match handle[1 + i]:
			"+":
				fixed[i] = box.position[i]
				moving[i] = box.end[i]
			"-":
				fixed[i] = box.end[i]
				moving[i] = box.position[i]
	return [fixed, moving]


## How far the mouse is along a face's outward axis (from the box's middle).
func _face_t(handle: String, at: Vector2) -> float:
	var i := "xyz".find(handle[2])
	var sgn := 1.0 if handle[1] == "+" else -1.0
	var box: AABB = _start.box
	var xf := Transform3D(_start.basis, _start.pos)
	var axis: Vector3 = (_start.basis as Basis) * (AXES[i] as Vector3) * sgn
	return _axis_t(axis, xf * box.get_center(), at)


## How far the mouse is along a corner's diagonal, from the fixed corner.
func _corner_t(handle: String, at: Vector2) -> float:
	var ends := _corner_ends(handle, _start.box)
	var xf := Transform3D(_start.basis, _start.pos)
	var dir := (_start.basis as Basis) * ((ends[1] as Vector3) - (ends[0] as Vector3))
	if dir.length() < 0.001:
		return 0.0
	return _axis_t(dir.normalized(), xf * (ends[0] as Vector3), at) / dir.length()


## Resizes the item to fill `box` (in its own frame, relative to where it
## started), moving it so the box lands where it was pulled to.
func _apply_box(d: Dictionary, box: AABB) -> void:
	Items.set_size(_kind, d, doc.level, box.size)
	var fresh := Items.sized_box(_kind, d, doc.level)
	var pivot := box.position - fresh.position
	Items.set_pos(_kind, d, (_start.pos as Vector3) + (_start.basis as Basis) * pivot)


## Ends the drag; true if anything changed.
func finish() -> bool:
	var was := _handle != ""
	_handle = ""
	_start = {}
	return was


## Where the drag began, in the handle's own terms.
func _grab(handle: String, at: Vector2) -> Variant:
	var origin: Vector3 = _start.origin
	var f: Basis = _start.frame
	if handle in ["x", "y", "z"]:
		return _axis_t(f * (AXES["xyz".find(handle)] as Vector3), origin, at)
	if handle in ["xy", "xz", "yz"]:
		return _plane_hit(f * (AXES[_plane(handle)[3]] as Vector3), origin, at)
	if handle in ["rx", "ry", "rz"]:
		return _plane_hit(f * (AXES["xyz".find(handle[1])] as Vector3), origin, at)
	if handle in ["sx", "sy", "sz"]:
		return _axis_t(f * (AXES["xyz".find(handle[1])] as Vector3), origin, at)
	if handle.begins_with("f"):
		return _face_t(handle, at)
	if handle.begins_with("c"):
		return _corner_t(handle, at)
	return 0.0


## How far along an axis line (through origin) the mouse ray passes closest.
func _axis_t(axis: Vector3, origin: Vector3, at: Vector2) -> float:
	var ro := camera.project_ray_origin(at)
	var rd := camera.project_ray_normal(at)
	var w := origin - ro
	var b := axis.dot(rd)
	var denom := 1.0 - b * b
	if absf(denom) < 0.02:
		# Looking straight down the axis: there's nothing sensible to read.
		return _last_t
	_last_t = clampf((b * rd.dot(w) - axis.dot(w)) / denom, -2000.0, 2000.0)
	return _last_t


func _plane_hit(normal: Vector3, origin: Vector3, at: Vector2) -> Vector3:
	var hit = Plane(normal.normalized(), origin).intersects_ray(camera.project_ray_origin(at), camera.project_ray_normal(at))
	return hit if hit != null else Vector3.INF
