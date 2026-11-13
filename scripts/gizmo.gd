class_name TransformGizmo
extends Node3D
## Godot-style handles on the selected item: move arrows (W), rotation rings
## (E) and resize handles (R). Drawn on top of everything at a constant size
## on screen. Snapping follows the editor's snap setting (rotation snaps to
## 15°); hold Alt to turn it off for a moment.
##
## The view hands it mouse events: hit() says whether a handle is under the
## mouse; start(), drag() and finish() do the work on the item's data.

enum Mode { SELECT, MOVE, ROTATE, SCALE }

const COLORS := [Color(0.96, 0.33, 0.35), Color(0.55, 0.88, 0.25), Color(0.3, 0.55, 1.0)]
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const PICK_PX := 10.0
## Handle length as a share of the camera distance.
const SIZE := 0.13

var mode := Mode.MOVE
var camera: Camera3D
var doc: EditorDoc
var snap_step := 0.5

var _id := ""
var _kind := ""
var _handle := ""  # "x", "y", "z", "xz", "rx", "ry", "rz", "sx", "sy", "sz", "s"
var _hover := ""
var _start := {}
var _mat_cache := {}


## Redraws the handles around the selected item (or hides them).
func refresh() -> void:
	for child in get_children():
		child.free()
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
	position = _origin(it)
	_fit()
	_draw(it)


func _process(_delta: float) -> void:
	if visible:
		_fit()


## Keeps the handles the same size on screen.
func _fit() -> void:
	if camera == null or not is_inside_tree():
		return
	var s := camera.global_position.distance_to(global_position) * SIZE
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		s = camera.size * SIZE
	scale = Vector3.ONE * maxf(s, 0.01)


## Where the handles sit: the item's middle for things that sit on the
## floor (so they're easy to grab), else its position.
func _origin(it: Dictionary) -> Vector3:
	return Items.get_pos(it.kind, it.data)


func _basis(it: Dictionary) -> Basis:
	return Items.xform(it.kind, it.data).basis.orthonormalized()


# --- Drawing ----------------------------------------------------------------------------------

func _draw(it: Dictionary) -> void:
	match mode:
		Mode.MOVE:
			for i in 3:
				_line(Vector3.ZERO, AXES[i], "xyz"[i], COLORS[i])
				_cube(AXES[i], 0.09, "xyz"[i], COLORS[i])
			var sq := PackedVector3Array([Vector3(0.18, 0, 0.18), Vector3(0.42, 0, 0.18), Vector3(0.42, 0, 0.18), Vector3(0.42, 0, 0.42),
				Vector3(0.42, 0, 0.42), Vector3(0.18, 0, 0.42), Vector3(0.18, 0, 0.42), Vector3(0.18, 0, 0.18)])
			_lines(sq, "xz", Color(1.0, 0.85, 0.3))
		Mode.ROTATE:
			var rings := [0, 1, 2] if Items.full_rot(_kind) else [1]
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
			var basis := _basis(it)
			for i in 3:
				var axis := basis * (AXES[i] as Vector3)
				_line(Vector3.ZERO, axis, "s" + "xyz"[i], COLORS[i])
				_cube(axis, 0.07, "s" + "xyz"[i], COLORS[i])
			_cube(Vector3.ZERO, 0.08, "s", Color(0.9, 0.9, 0.9))


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.render_priority = 10
		m.vertex_color_use_as_albedo = false
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_cache[key] = m
	return _mat_cache[key]


func _color_for(handle: String, color: Color) -> Color:
	return Color(1.0, 0.95, 0.4) if handle == _hover or handle == _handle else color


func _line(a: Vector3, b: Vector3, handle: String, color: Color) -> void:
	_lines(PackedVector3Array([a, b]), handle, color)


func _lines(pts: PackedVector3Array, handle: String, color: Color) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material(_color_for(handle, color)))
	for p in pts:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("handle", handle)
	add_child(mi)


func _cube(at: Vector3, half: float, handle: String, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * half * 2.0
	box.material = _material(_color_for(handle, color))
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --- Picking ------------------------------------------------------------------------------------

## The handle under the mouse ("" for none). Also lights it up.
func hit(at: Vector2) -> String:
	if not visible or camera == null:
		return ""
	var best := ""
	var best_d := PICK_PX
	var it := doc.item(_id)
	if it.is_empty():
		return ""
	for seg in _segments(it):
		var a := camera.unproject_position(global_transform * (seg[0] as Vector3))
		var b := camera.unproject_position(global_transform * (seg[1] as Vector3))
		var d := Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at)
		if d < best_d:
			best_d = d
			best = seg[2]
	if mode == Mode.SCALE:
		var c := camera.unproject_position(global_position)
		if c.distance_to(at) < PICK_PX * 1.4:
			best = "s"
	if best != _hover:
		_hover = best
		refresh()
	return best


## Screen-pickable pieces of every handle: [[from, to, handle], ...] (local).
func _segments(it: Dictionary) -> Array:
	var out := []
	match mode:
		Mode.MOVE:
			for i in 3:
				out.append([Vector3.ZERO + AXES[i] * 0.15, AXES[i] * 1.05, "xyz"[i]])
			var c := [Vector3(0.18, 0, 0.18), Vector3(0.42, 0, 0.18), Vector3(0.42, 0, 0.42), Vector3(0.18, 0, 0.42)]
			for k in 4:
				out.append([c[k], c[(k + 1) % 4], "xz"])
			out.append([c[0], c[2], "xz"])
			out.append([c[1], c[3], "xz"])
		Mode.ROTATE:
			var rings := [0, 1, 2] if Items.full_rot(_kind) else [1]
			for i in rings:
				var a := AXES[(i + 1) % 3] as Vector3
				var b := AXES[(i + 2) % 3] as Vector3
				for k in 32:
					var t0 := TAU * k / 32.0
					var t1 := TAU * (k + 1) / 32.0
					out.append([(a * cos(t0) + b * sin(t0)) * 0.9, (a * cos(t1) + b * sin(t1)) * 0.9, "r" + "xyz"[i]])
		Mode.SCALE:
			var basis := _basis(it)
			for i in 3:
				out.append([basis * (AXES[i] as Vector3) * 0.2, basis * (AXES[i] as Vector3) * 1.05, "s" + "xyz"[i]])
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
	_start = {"pos": Items.get_pos(_kind, d), "rot": Items.get_rot(_kind, d), "basis": _basis(it),
		"size": Items.get_size(_kind, d, doc.level), "mouse": at, "origin": global_position,
		"grab": _grab(handle, at, global_position)}


func drag(at: Vector2, no_snap: bool) -> void:
	if _handle == "":
		return
	var d := doc.find(_id)
	if d.is_empty():
		return
	var origin: Vector3 = _start.origin
	match _handle:
		"x", "y", "z":
			var axis: Vector3 = AXES["xyz".find(_handle)]
			var t := _axis_t(axis, origin, at)
			var delta := t - float(_start.grab)
			if not no_snap and snap_step > 0.0:
				delta = snappedf(delta, snap_step)
			Items.set_pos(_kind, d, _start.pos + axis * delta)
		"xz":
			var hit := _plane_hit(Vector3.UP, origin, at)
			if hit == Vector3.INF:
				return
			var delta: Vector3 = hit - (_start.grab as Vector3)
			if not no_snap and snap_step > 0.0:
				delta = Vector3(snappedf(delta.x, snap_step), 0, snappedf(delta.z, snap_step))
			Items.set_pos(_kind, d, _start.pos + Vector3(delta.x, 0, delta.z))
		"rx", "ry", "rz":
			var axis: Vector3 = AXES["xyz".find(_handle[1])]
			var hit := _plane_hit(axis, origin, at)
			if hit == Vector3.INF or _start.grab == Vector3.INF:
				return
			var v0: Vector3 = ((_start.grab as Vector3) - origin)
			var v1: Vector3 = hit - origin
			var angle := v0.signed_angle_to(v1, axis)
			if not no_snap:
				angle = snappedf(angle, deg_to_rad(15.0))
			var basis: Basis = Basis(axis, angle) * (_start.basis as Basis)
			if Items.full_rot(_kind):
				Items.set_rot(_kind, d, basis.get_euler() * (180.0 / PI))
			else:
				Items.set_rot(_kind, d, Vector3(0, (_start.rot as Vector3).y + rad_to_deg(angle), 0))
		"sx", "sy", "sz":
			var i := "xyz".find(_handle[1])
			var axis: Vector3 = (_start.basis as Basis) * (AXES[i] as Vector3)
			var t := _axis_t(axis, origin, at)
			var g := float(_start.grab)
			if absf(g) < 0.001:
				return
			var size: Vector3 = _start.size
			var v := maxf(size[i] * t / g, 0.05)
			if not no_snap and snap_step > 0.0:
				v = maxf(snappedf(v, snap_step), snap_step)
			size[i] = v
			Items.set_size(_kind, d, doc.level, size)
		"s":
			var dy: float = (_start.mouse as Vector2).y - at.y
			var f := clampf(1.0 + dy / 150.0, 0.05, 20.0)
			Items.set_size(_kind, d, doc.level, (_start.size as Vector3) * f)


## Ends the drag; true if anything changed.
func finish() -> bool:
	var was := _handle != ""
	_handle = ""
	_start = {}
	return was


## Where the drag began, in the handle's own terms.
func _grab(handle: String, at: Vector2, origin: Vector3) -> Variant:
	match handle:
		"x", "y", "z":
			return _axis_t(AXES["xyz".find(handle)], origin, at)
		"xz":
			return _plane_hit(Vector3.UP, origin, at)
		"rx", "ry", "rz":
			return _plane_hit(AXES["xyz".find(handle[1])], origin, at)
		"sx", "sy", "sz":
			var it := doc.item(_id)
			return _axis_t(_basis(it) * (AXES["xyz".find(handle[1])] as Vector3), origin, at)
	return 0.0


## How far along an axis line (through origin) the mouse ray passes closest.
func _axis_t(axis: Vector3, origin: Vector3, at: Vector2) -> float:
	var ro := camera.project_ray_origin(at)
	var rd := camera.project_ray_normal(at)
	var w := origin - ro
	var b := axis.dot(rd)
	var denom := 1.0 - b * b
	if absf(denom) < 0.0001:
		return 0.0
	var d := axis.dot(w)
	var e := rd.dot(w)
	return (b * e - d) / denom


func _plane_hit(normal: Vector3, origin: Vector3, at: Vector2) -> Vector3:
	var hit = Plane(normal, origin).intersects_ray(camera.project_ray_origin(at), camera.project_ray_normal(at))
	return hit if hit != null else Vector3.INF
