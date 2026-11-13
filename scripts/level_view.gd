class_name LevelView
extends SubViewportContainer
## The 3D view: shows the level, and lets you look around, pick things,
## drag them and place new ones.
##
## Mouse:  left click = select (or place, while placing); left drag = move;
##         right drag = look around; middle drag (or Shift + right drag) = pan;
##         wheel = zoom.
## Only the active layer's items can be picked, so walls never get in the
## way of the door you're trying to click.

signal hint(text: String)
signal placed(id: String)

const SKY := {
	"day": [Color(0.32, 0.5, 0.82), Color(0.72, 0.78, 0.85), Color(1.0, 0.97, 0.9), 1.0, 1.0],
	"dusk": [Color(0.28, 0.25, 0.45), Color(0.95, 0.55, 0.35), Color(1.0, 0.7, 0.45), 0.8, 0.85],
	"overcast": [Color(0.5, 0.53, 0.58), Color(0.68, 0.7, 0.72), Color(0.9, 0.92, 0.95), 0.45, 1.15],
	"night": [Color(0.04, 0.06, 0.14), Color(0.12, 0.16, 0.28), Color(0.6, 0.7, 1.0), 0.35, 0.75],
	"cave": [Color(0.08, 0.08, 0.1), Color(0.16, 0.15, 0.16), Color(0.85, 0.75, 0.6), 0.3, 0.8],
	"interior": [Color(0.3, 0.32, 0.36), Color(0.45, 0.45, 0.48), Color(1.0, 0.95, 0.88), 0.4, 1.1],
}

var app: Node
var doc: EditorDoc
## Show the other layers' items too (dimmed by having no name tags).
var show_all_layers := true
var show_wires := true

var _vp: SubViewport
var _camera: Camera3D
var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _items: Node3D
var _overlay: Node3D
var _ghost: Node3D
var _nodes := {}

var _target := Vector3(0, 0, 0)
var _yaw := deg_to_rad(35.0)
var _pitch := deg_to_rad(-50.0)
var _dist := 40.0
var _top := false

var _orbiting := false
var _panning := false
var _drag := {}
var _placing := {}
var _ghost_pos := Vector3.INF
var _press_at := Vector2.ZERO


func _init() -> void:
	stretch = true
	focus_mode = Control.FOCUS_CLICK
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)
	_camera = Camera3D.new()
	_camera.far = 2000.0
	_vp.add_child(_camera)
	_env = WorldEnvironment.new()
	_env.environment = Environment.new()
	_vp.add_child(_env)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_vp.add_child(_sun)
	_vp.add_child(_grid())
	_items = Node3D.new()
	_vp.add_child(_items)
	_overlay = Node3D.new()
	_vp.add_child(_overlay)
	_update_camera()


func set_doc(d: EditorDoc) -> void:
	doc = d
	cancel_place()
	_target = LevelData.vec3(doc.level.map.start.get("pos"))
	rebuild()


# --- Drawing ----------------------------------------------------------------------------------

func rebuild() -> void:
	for child in _items.get_children():
		child.free()
	_nodes.clear()
	if doc == null:
		return
	_apply_lighting()
	var layer: int = app.layer
	for p in doc.level.map.pieces:
		if p.has("generated_for"):
			_items.add_child(ItemVisuals.build("piece", p, doc))
	for it in doc.items():
		var its_layer: int = EditorDoc.KIND_LAYER[it.kind]
		var mine: bool = its_layer == layer
		if not mine and its_layer != 1 and not show_all_layers:
			continue
		var node := ItemVisuals.build(it.kind, it.data, doc, mine, layer)
		_items.add_child(node)
		_nodes[it.id] = node
	refresh_overlay()


## The selection box, enemy rings and trigger lines.
func refresh_overlay() -> void:
	for child in _overlay.get_children():
		child.free()
	if doc == null:
		return
	var layer: int = app.layer
	if show_wires and layer >= 2:
		var about := doc.rules_about(doc.selected) if doc.selected != "" else {"from": [], "onto": []}
		for rule in doc.level.interaction.rules:
			var color := Color(0.5, 0.6, 0.75, 0.6)
			if about.from.has(rule):
				color = Color(0.4, 1.0, 0.5)
			elif about.onto.has(rule):
				color = Color(1.0, 0.7, 0.3)
			var from := doc.position_of(String(rule.get("when", {}).get("source", "")))
			for a in rule.get("do", []):
				_wire(from, doc.position_of(String(a.get("target", ""))), color)
		for o in doc.level.interaction.objects:
			for key in ["open_when_cleared", "shut_during_combat"]:
				if String(o.get(key, "")) != "":
					_wire(doc.position_of(String(o[key])), Items.get_pos("object", o),
						Color(1.0, 0.7, 0.3) if doc.selected == String(o.id) else Color(0.5, 0.6, 0.75, 0.6))
	var it := doc.item(doc.selected)
	if it.is_empty():
		return
	var box := Items.local_aabb(it.kind, it.data, doc.level).grow(0.05)
	var outline := ItemVisuals.lines(ItemVisuals.box_edges(box), Color(1.0, 0.9, 0.2), true)
	outline.transform = Items.xform(it.kind, it.data)
	_overlay.add_child(outline)
	if it.kind == "enemy":
		var at := Items.get_pos(it.kind, it.data) + Vector3(0, 0.08, 0)
		var bad := LevelData.placement_problem(it.data) != ""
		if bool(it.data.get("wander", false)) and float(it.data.get("wander_radius", 0.0)) > 0.0:
			_ring(at, float(it.data.wander_radius), Color(0.35, 1.0, 0.45))
		if bool(it.data.get("limited_chase", false)) and float(it.data.get("chase_radius", 0.0)) > 0.0:
			_ring(at, float(it.data.chase_radius), Color(1.0, 0.2, 0.2) if bad else Color(1.0, 0.55, 0.3))
		var e := Catalog.enemy(String(it.data.get("enemy", "")))
		var aggro := float(e.get("aggro", 14.0)) * float(LevelData.AGGRO.get(String(it.data.get("aggro", "normal")), 1.0))
		_ring(at, aggro, Color(0.6, 0.75, 1.0, 0.5))


func _ring(at: Vector3, radius: float, color: Color) -> void:
	var r := ItemVisuals.ring(radius, color)
	r.position = at
	_overlay.add_child(r)


func _wire(from: Vector3, to: Vector3, color: Color) -> void:
	if from == Vector3.INF or to == Vector3.INF or from.distance_to(to) < 0.1:
		return
	var up := Vector3(0, 1.4, 0)
	var dir := (to - from).normalized()
	var side := dir.cross(Vector3.UP).normalized() * 0.4
	var tip := to + up
	var pts := PackedVector3Array([from + up, tip, tip, tip - dir * 0.9 + side, tip, tip - dir * 0.9 - side])
	_overlay.add_child(ItemVisuals.lines(pts, color, true))


func _apply_lighting() -> void:
	var l := LevelData.clamp_lighting(doc.level.map.lighting)
	var p: Array = SKY[l.preset]
	var e := _env.environment
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = p[0]
	sky_mat.sky_horizon_color = p[1]
	sky_mat.ground_horizon_color = p[1]
	sky_mat.ground_bottom_color = (p[1] as Color).darkened(0.5)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = float(p[4]) * float(l.ambient_energy)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = float(l.exposure)
	e.fog_enabled = float(l.fog_density) > 0.0
	e.fog_density = float(l.fog_density)
	e.fog_light_color = p[1]
	_sun.light_color = p[2]
	_sun.light_energy = float(p[3]) * float(l.sun_energy)
	_sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)


func _grid() -> MeshInstance3D:
	var pts := PackedVector3Array()
	var half := 120.0
	var x := -half
	while x <= half:
		pts.append(Vector3(x, 0.01, -half))
		pts.append(Vector3(x, 0.01, half))
		pts.append(Vector3(-half, 0.01, x))
		pts.append(Vector3(half, 0.01, x))
		x += LevelData.GRID
	return ItemVisuals.lines(pts, Color(0.55, 0.6, 0.7, 0.1))


# --- Camera -----------------------------------------------------------------------------------

func _update_camera() -> void:
	var pitch := deg_to_rad(-89.9) if _top else _pitch
	var basis := Basis.from_euler(Vector3(pitch, _yaw, 0.0))
	_camera.transform = Transform3D(basis, _target + basis.z * _dist)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL if _top else Camera3D.PROJECTION_PERSPECTIVE
	_camera.size = _dist


func set_top_view(on: bool) -> void:
	_top = on
	_update_camera()


func is_top_view() -> bool:
	return _top


## Centres the view on an item (or the whole level with "").
func focus(id := "") -> void:
	if doc == null:
		return
	var it := doc.item(id)
	if it.is_empty():
		var box := AABB()
		var first := true
		for r in doc.level.map.rooms:
			var b := AABB(LevelData.vec3(r.get("pos")) - LevelData.vec3(r.get("size")) * Vector3(0.5, 0, 0.5), LevelData.vec3(r.get("size")))
			box = b if first else box.merge(b)
			first = false
		if first:
			_target = LevelData.vec3(doc.level.map.start.get("pos"))
			_dist = 40.0
		else:
			_target = box.get_center()
			_target.y = box.position.y
			_dist = clampf(maxf(box.size.x, box.size.z) * 0.7 + 14.0, 24.0, 400.0)
	else:
		var box := Items.local_aabb(it.kind, it.data, doc.level)
		_target = Items.get_pos(it.kind, it.data)
		_dist = clampf(maxf(box.size.x, box.size.z) * 2.5, 8.0, 120.0)
	_update_camera()


func _process(delta: float) -> void:
	if not has_focus() or Input.is_key_pressed(KEY_CTRL):
		return
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		move.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		move.y += 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		move.y -= 1.0
	if move != Vector2.ZERO:
		_pan(move * _dist * delta * 0.9)


func _pan(by: Vector2) -> void:
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	_target += right * by.x + forward * by.y
	_update_camera()


# --- Rays and picking -------------------------------------------------------------------------

func _ray(at: Vector2) -> Array:
	return [_camera.project_ray_origin(at), _camera.project_ray_normal(at)]


## Where the mouse ray meets the horizontal plane at height y (INF if it doesn't).
func ground_point(at: Vector2, y := 0.0) -> Vector3:
	var ray := _ray(at)
	var hit = Plane(Vector3.UP, y).intersects_ray(ray[0], ray[1])
	return hit if hit != null else Vector3.INF


## The id under the mouse among the active layer's items ("" if none).
func pick(at: Vector2) -> String:
	var ray := _ray(at)
	var best := ""
	var best_dist := INF
	var best_room := ""
	var best_room_dist := INF
	var layer: int = app.layer
	for it in doc.items():
		var is_room: bool = it.kind == "room"
		if EditorDoc.KIND_LAYER[it.kind] != layer and not (is_room and layer == 3):
			continue
		var xf := Items.xform(it.kind, it.data)
		var inv := xf.affine_inverse()
		var box := Items.local_aabb(it.kind, it.data, doc.level, true).grow(0.05)
		var hit = box.intersects_ray(inv * (ray[0] as Vector3), inv.basis * (ray[1] as Vector3))
		if hit == null:
			continue
		var dist := (xf * (hit as Vector3)).distance_to(ray[0])
		if is_room:
			if dist < best_room_dist:
				best_room_dist = dist
				best_room = it.id
		elif dist < best_dist:
			best_dist = dist
			best = it.id
	return best if best != "" else best_room


func snap_pos(kind: String, d: Dictionary, p: Vector3) -> Vector3:
	if kind == "room":
		var s := LevelData.vec3(d.get("size"), Vector3(16, 6, 16))
		p.x = snappedf(p.x - s.x * 0.5, LevelData.GRID) + s.x * 0.5
		p.z = snappedf(p.z - s.z * 0.5, LevelData.GRID) + s.z * 0.5
		return p
	var step: float = app.snap_step
	if step > 0.0 and not Input.is_key_pressed(KEY_ALT):
		p.x = snappedf(p.x, step)
		p.z = snappedf(p.z, step)
	return p


## Doors jump onto a doorway when they're close to one.
func _snap_door(d: Dictionary) -> void:
	var p := LevelData.vec3(d.get("pos"))
	for way in RoomBuilder.doorways(doc.level):
		if not way.open and (way.pos as Vector3).distance_to(p) < 2.5:
			d.pos = LevelData.arr3(way.pos)
			d.yaw = way.yaw
			return


# --- Placing ----------------------------------------------------------------------------------

## Starts placing a palette entry: it follows the mouse until you click.
func begin_place(entry: Dictionary) -> void:
	cancel_place()
	_placing = entry
	hint.emit("Click to place %s. R turns it. Keep clicking to place more. Esc or right-click to stop." % entry.title)


func cancel_place() -> void:
	_placing = {}
	_ghost_pos = Vector3.INF
	if _ghost:
		_ghost.free()
		_ghost = null


func is_placing() -> bool:
	return not _placing.is_empty()


func rotate_placing(degrees: float) -> void:
	if is_placing():
		Items.rotate(_placing.kind, _placing.data, degrees)
		_ghost_pos = Vector3.INF


## The item a palette entry becomes at a point.
func _template_at(entry: Dictionary, p: Vector3) -> Dictionary:
	var d: Dictionary = (entry.data as Dictionary).duplicate(true)
	var kind: String = entry.kind
	p = snap_pos(kind, d, p)
	p.y += float(d.get("pos_y", 0.0))
	d.erase("pos_y")
	if kind == "object" and String(d.get("type", "")) == "platform":
		d.points = [LevelData.arr3(p), LevelData.arr3(p + Vector3(0, 0, -8))]
	elif kind == "object" and String(d.get("type", "")) == "hazard":
		var room := doc.level.find_room(doc.room_at(p))
		if room.is_empty():
			d.zones = [{"pos": LevelData.arr3(p), "size": [8, 4, 8]}]
		else:
			d.zones = [{"pos": room.get("pos"), "size": room.get("size")}]
	else:
		d.pos = LevelData.arr3(p)
		if kind == "object" and String(d.get("type", "")) == "door":
			_snap_door(d)
	return d


func _move_ghost(at: Vector2) -> void:
	var p := ground_point(at)
	if p == Vector3.INF:
		return
	var d := _template_at(_placing, p)
	var where := Items.get_pos(_placing.kind, d)
	if where == _ghost_pos and _ghost:
		return
	_ghost_pos = where
	if _ghost:
		_ghost.free()
	_ghost = ItemVisuals.build(_placing.kind, d, doc, false, app.layer)
	_vp.add_child(_ghost)


func _place(at: Vector2) -> void:
	var p := ground_point(at)
	if p == Vector3.INF:
		return
	var d := _template_at(_placing, p)
	var id := doc.add(_placing.kind, d, int(app.place_wave) - 1)
	doc.select(id)
	doc.commit()
	placed.emit(id)


# --- Mouse ------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if doc == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_dist = clampf(_dist * 0.9, 3.0, 400.0)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = clampf(_dist * 1.1, 3.0, 400.0)
				_update_camera()
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_press_at = mb.position
					_panning = mb.shift_pressed
					_orbiting = not mb.shift_pressed
				else:
					if is_placing() and mb.position.distance_to(_press_at) < 4.0:
						cancel_place()
						hint.emit("")
					_orbiting = false
					_panning = false
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					grab_focus()
					_press_at = mb.position
					if is_placing():
						_place(mb.position)
					else:
						var id := pick(mb.position)
						doc.select(id)
						_begin_drag(id, mb.position)
				else:
					_end_drag()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_yaw -= mm.relative.x * 0.006
			_pitch = clampf(_pitch - mm.relative.y * 0.006, deg_to_rad(-89.0), deg_to_rad(-5.0))
			_update_camera()
		elif _panning:
			_pan(Vector2(-mm.relative.x, mm.relative.y) * _dist * 0.0016)
		elif not _drag.is_empty():
			_drag_to(mm.position)
		elif is_placing():
			_move_ghost(mm.position)


func _begin_drag(id: String, at: Vector2) -> void:
	_drag = {}
	var it := doc.item(id)
	if it.is_empty():
		return
	var pos := Items.get_pos(it.kind, it.data)
	var hit := ground_point(at, pos.y)
	if hit == Vector3.INF:
		return
	_drag = {"id": id, "kind": it.kind, "offset": pos - hit, "y": pos.y, "moved": false}


func _drag_to(at: Vector2) -> void:
	if not _drag.moved and at.distance_to(_press_at) < 5.0:
		return
	var d := doc.find(_drag.id)
	var hit := ground_point(at, _drag.y)
	if d.is_empty() or hit == Vector3.INF:
		return
	var kind: String = _drag.kind
	var p := snap_pos(kind, d, hit + _drag.offset)
	p.y = _drag.y
	if p.is_equal_approx(Items.get_pos(kind, d)):
		return
	_drag.moved = true
	Items.set_pos(kind, d, p)
	if kind == "object" and String(d.get("type", "")) == "door":
		_snap_door(d)
	if kind == "room":
		doc.normalize()  # walls and doorways follow the room
		rebuild()
	else:
		var node: Node3D = _nodes.get(_drag.id)
		if node:
			node.transform = Items.xform(kind, d)
		refresh_overlay()


func _end_drag() -> void:
	if not _drag.is_empty() and _drag.moved:
		if _drag.kind == "enemy":
			doc.settle_enemy(_drag.id)
		doc.commit()
	_drag = {}
