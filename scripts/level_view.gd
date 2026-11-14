class_name LevelView
extends SubViewportContainer
## The 3D view: shows the level, and lets you look around, pick things,
## drag them and place new ones.
##
## Mouse:  left click = select (or place, while placing); left drag = move
##         along the ground; the handles (W move, E rotate, R resize) work
##         like Godot's; right drag = look around (WASD flies while held);
##         middle drag (or Shift + right drag) = pan; wheel = zoom.
## Only the active layer's items can be picked, so walls never get in the
## way of the door you're trying to click. The navmesh is drawn on top of
## the floors, one color per room; clicking it picks the room when "Click
## picks: Rooms" is on (always on Layer 3).

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
var show_nav := true
## Orthographic camera (the top view is always orthographic).
var ortho := false
## Layer 1: clicks pick rooms (navmesh) instead of pieces.
var pick_rooms := false
var gizmo: TransformGizmo

var _vp: SubViewport
var _camera: Camera3D
var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _items: Node3D
var _overlay: Node3D
var _nav: Node3D
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
var _nav_selected_area := ""


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
  _nav = Node3D.new()
  _vp.add_child(_nav)
  _overlay = Node3D.new()
  _vp.add_child(_overlay)
  gizmo = TransformGizmo.new()
  gizmo.camera = _camera
  _vp.add_child(gizmo)
  _update_camera()


func set_doc(d: EditorDoc) -> void:
  doc = d
  gizmo.doc = d
  doc.nav_updated.connect(refresh_nav)
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
  for it in doc.items():
    if it.kind == "area":
      continue
    var its_layer: int = EditorDoc.KIND_LAYER[it.kind]
    var mine: bool = its_layer == layer
    if not mine and its_layer != 1 and not show_all_layers:
      continue
    var node := ItemVisuals.build(it.kind, it.data, doc, mine, layer)
    _items.add_child(node)
    _nodes[it.id] = node
  _draw_base()
  refresh_overlay()


## Nomad-2 under a quest's additions: its floor, walls, counters, signs and
## spots, drawn but not selectable (it's fixed; the quest adds on top).
func _draw_base() -> void:
  if doc.base.is_empty():
    return
  var root := Node3D.new()
  root.name = "Nomad2"
  _items.add_child(root)
  for p in doc.base_pieces():
    root.add_child(ItemVisuals.build("piece", p, doc, false, 1))
  for l in doc.base.get("labels", []):
    var sign_label := Label3D.new()
    sign_label.text = String(l.get("text", ""))
    sign_label.position = LevelData.vec3(l.get("pos"))
    sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    sign_label.font_size = clampi(int(l.get("size", 48)), 16, 160)
    sign_label.pixel_size = 0.01
    sign_label.outline_size = 10
    sign_label.modulate = Color(0.85, 0.9, 1.0, 0.85)
    root.add_child(sign_label)
  var marks := {"start": [Color(0.25, 0.9, 0.45), "Seekers arrive"], "teleporter": [Color(0.4, 0.8, 1.0), "Teleporter"],
    "depot": [Color(0.9, 0.75, 0.3), "Lumidium depot"], "clerk": [Color(0.75, 0.75, 0.85), ""]}
  for m in doc.base.get("markers", []):
    var spec: Array = marks.get(String(m.get("type", "")), [Color.WHITE, ""])
    var at := LevelData.vec3(m.get("pos"))
    var disc := ItemVisuals._at(ItemVisuals._box(Vector3(1.6, 0.06, 1.6), spec[0], 0.5), at + Vector3(0, 0.03, 0))
    root.add_child(disc)
    var tag := ItemVisuals._label(String(m.get("name", "")) if spec[1] == "" else String(spec[1]), spec[0], 22)
    tag.position = at + Vector3(0, 1.4, 0)
    root.add_child(tag)


## Rebuilds one item's stand-in (while it's being resized), leaving the rest.
func rebuild_item(id: String) -> void:
  var it := doc.item(id)
  var old: Node3D = _nodes.get(id)
  if it.is_empty() or old == null:
    rebuild()
    return
  var layer: int = app.layer
  var node := ItemVisuals.build(it.kind, it.data, doc, EditorDoc.KIND_LAYER[it.kind] == layer, layer)
  _items.add_child(node)
  _items.move_child(node, old.get_index())
  old.free()
  _nodes[id] = node
  refresh_overlay()


## The navmesh: each piece in its room's color (grey for crumbs too small to
## be a room), the selected room brighter, every polygon outlined.
func refresh_nav() -> void:
  for child in _nav.get_children():
    child.free()
  if doc == null or not show_nav or doc.nav.is_empty():
    return
  var colors := {}
  for a in doc.level.map.areas:
    colors[String(a.id)] = ItemVisuals._color(a.get("color"), Color(0.4, 0.6, 0.95))
  var fill := ImmediateMesh.new()
  var edges := PackedVector3Array()
  var lift := Vector3(0, 0.06, 0)
  var any := false
  for island in doc.nav.islands:
    var area := String(island.get("area", ""))
    var c: Color = colors.get(area, Color(0.55, 0.55, 0.55))
    c.a = 0.62 if area != "" and area == doc.selected else 0.36
    for poly in island.polys:
      if not any:
        fill.surface_begin(Mesh.PRIMITIVE_TRIANGLES, ItemVisuals.nav_material())
        any = true
      for k in range(1, poly.size() - 1):
        for v in [poly[0], poly[k], poly[k + 1]]:
          fill.surface_set_color(c)
          fill.surface_add_vertex(v + lift)
      for k in poly.size():
        edges.append(poly[k] + lift)
        edges.append(poly[(k + 1) % poly.size()] + lift)
  if any:
    fill.surface_end()
    var mi := MeshInstance3D.new()
    mi.mesh = fill
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _nav.add_child(mi)
    _nav.add_child(ItemVisuals.lines(edges, Color(1, 1, 1, 0.07)))
  # Room names over each room.
  for a in doc.level.map.areas:
    var tag := Label3D.new()
    tag.text = Catalog.label("area", a, String(a.id))
    tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    tag.no_depth_test = true
    tag.fixed_size = true
    tag.pixel_size = 0.0011
    tag.font_size = 30
    tag.outline_size = 8
    tag.modulate = colors.get(String(a.id), Color.WHITE).lightened(0.4)
    tag.position = LevelData.vec3(a.get("seed")) + Vector3(0, 1.2, 0)
    _nav.add_child(tag)


## The selection box, enemy rings and trigger lines.
func refresh_overlay() -> void:
  for child in _overlay.get_children():
    child.free()
  gizmo.refresh()
  if doc == null:
    return
  if not doc.nav.is_empty() and (doc.kind_of(doc.selected) == "area" or _nav_selected_area != ""):
    refresh_nav()
  _nav_selected_area = doc.selected if doc.kind_of(doc.selected) == "area" else ""
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
  if it.is_empty() or it.kind == "area":
    return
  var box := Items.local_aabb(it.kind, it.data, doc.level).grow(0.05)
  var outline := ItemVisuals.lines(ItemVisuals.box_edges(box), Color(1.0, 0.9, 0.2), true)
  outline.transform = Items.xform(it.kind, it.data)
  _overlay.add_child(outline)
  if it.kind == "piece":
    _show_hitbox(it.data)
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


## The selected piece's collision, as Godot builds it (the game builds the same).
func _show_hitbox(d: Dictionary) -> void:
  var hit := LevelNav.hitbox(d, doc.level, doc.model_loader())
  var mat := StandardMaterial3D.new()
  mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  mat.albedo_color = Color(0.4, 1.0, 0.85, 0.55)
  mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
  mat.no_depth_test = true
  for pair in hit.shapes:
    var mi := MeshInstance3D.new()
    mi.mesh = (pair[0] as Shape3D).get_debug_mesh()
    mi.material_override = mat
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    mi.transform = (hit.xform as Transform3D) * (pair[1] as Transform3D)
    _overlay.add_child(mi)


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
  var flat := _top or ortho
  # Orthographic shows the same width as perspective would at this zoom;
  # the camera sits well back so nothing between it and the level is cut off.
  _camera.projection = Camera3D.PROJECTION_ORTHOGONAL if flat else Camera3D.PROJECTION_PERSPECTIVE
  _camera.size = 2.0 * _dist * tan(deg_to_rad(_camera.fov) * 0.5)
  _camera.transform = Transform3D(basis, _target + basis.z * (maxf(_dist, 600.0) if flat else _dist))


## Right mouse held: W A S D fly the camera.
func is_flying() -> bool:
  return _orbiting


func set_top_view(on: bool) -> void:
  _top = on
  _update_camera()


## Orthographic (no perspective) from any angle.
func set_ortho(on: bool) -> void:
  ortho = on
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
    for p in doc.level.map.pieces:
      var b := Items.xform("piece", p) * Items.local_aabb("piece", p, doc.level)
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
  # Arrow keys always pan; W A S D only while looking around (right mouse
  # held), as in Godot, so W / E / R are free for the handles.
  var fly := _orbiting
  var move := Vector2.ZERO
  if Input.is_key_pressed(KEY_LEFT) or (fly and Input.is_key_pressed(KEY_A)):
    move.x -= 1.0
  if Input.is_key_pressed(KEY_RIGHT) or (fly and Input.is_key_pressed(KEY_D)):
    move.x += 1.0
  if Input.is_key_pressed(KEY_UP) or (fly and Input.is_key_pressed(KEY_W)):
    move.y += 1.0
  if Input.is_key_pressed(KEY_DOWN) or (fly and Input.is_key_pressed(KEY_S)):
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


## The id under the mouse ("" if none): the active layer's items, or a room
## (its navmesh) on Layer 3, or on Layer 1 with pick_rooms on.
func pick(at: Vector2) -> String:
  var layer: int = app.layer
  if layer == 1 and pick_rooms:
    return pick_area(at)
  var ray := _ray(at)
  var best := ""
  var best_dist := INF
  for it in doc.items():
    if it.kind == "area" or EditorDoc.KIND_LAYER[it.kind] != layer:
      continue
    var xf := Items.xform(it.kind, it.data)
    var inv := xf.affine_inverse()
    var box := Items.local_aabb(it.kind, it.data, doc.level, true).grow(0.05)
    var hit = box.intersects_ray(inv * (ray[0] as Vector3), inv.basis * (ray[1] as Vector3))
    if hit == null:
      continue
    var dist := (xf * (hit as Vector3)).distance_to(ray[0])
    if dist < best_dist:
      best_dist = dist
      best = it.id
  if best == "" and layer == 3:
    return pick_area(at)
  return best


## The room (area) whose navmesh is under the mouse ("" if none).
func pick_area(at: Vector2) -> String:
  if doc.nav.is_empty():
    return ""
  var ray := _ray(at)
  var best := ""
  var best_dist := INF
  for island in doc.nav.islands:
    if String(island.get("area", "")) == "":
      continue
    for poly in island.polys:
      for k in range(1, poly.size() - 1):
        var hit = Geometry3D.ray_intersects_triangle(ray[0], ray[1], poly[0], poly[k], poly[k + 1])
        if hit != null and (hit as Vector3).distance_to(ray[0]) < best_dist:
          best_dist = (hit as Vector3).distance_to(ray[0])
          best = String(island.area)
  return best


## Where a placed item lands under the mouse: on top of whatever the ray
## hits first (a floor, a block), else on the ground plane.
func surface_point(at: Vector2) -> Vector3:
  var ray := _ray(at)
  var best := Vector3.INF
  var best_dist := INF
  for p in doc.solid_pieces():
    if doc.level.surface_of(p) == "intangible":
      continue
    var xf := Items.xform("piece", p)
    var inv := xf.affine_inverse()
    var box := Items.local_aabb("piece", p, doc.level)
    var hit = box.intersects_ray(inv * (ray[0] as Vector3), inv.basis * (ray[1] as Vector3))
    if hit == null:
      continue
    var world := xf * (hit as Vector3)
    var dist := world.distance_to(ray[0])
    if dist < best_dist:
      best_dist = dist
      best = world
  return best if best != Vector3.INF else ground_point(at)


func snap_pos(_kind: String, _d: Dictionary, p: Vector3) -> Vector3:
  var step: float = app.snap_step
  if step > 0.0 and not Input.is_key_pressed(KEY_ALT):
    p.x = snappedf(p.x, step)
    p.z = snappedf(p.z, step)
  return p


# --- Placing ----------------------------------------------------------------------------------

## Starts placing a palette entry: it follows the mouse until you click.
func begin_place(entry: Dictionary) -> void:
  cancel_place()
  _placing = entry
  if entry.kind == "material":
    hint.emit("Painting with %s: click shapes or models to paint them. Click a painted one again to take it off. Esc or right-click to stop." % entry.title)
    return
  hint.emit("Click to place %s. R turns it a quarter turn while placing. Keep clicking to place more. Esc or right-click to stop." % entry.title)


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
    d.zones = [{"pos": LevelData.arr3(p), "size": [8, 4, 8]}]
  else:
    d.pos = LevelData.arr3(p)
  return d


func _move_ghost(at: Vector2) -> void:
  if _placing.kind == "material":
    _show_paint_target(pick_piece(at))
    return
  var p := surface_point(at)
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
  if _placing.kind == "material":
    _paint(at)
    return
  var p := surface_point(at)
  if p == Vector3.INF:
    return
  var d := _template_at(_placing, p)
  var id := doc.add(_placing.kind, d, int(app.place_wave) - 1)
  doc.select(id)
  doc.commit()
  placed.emit(id)


## Paints the piece under the mouse with the material being painted (or
## takes it off, if it already wears it).
func _paint(at: Vector2) -> void:
  var id := pick_piece(at)
  var d := doc.find(id)
  if d.is_empty():
    return
  var mat := String(_placing.data.get("material", ""))
  if String(d.get("material", "")) == mat:
    d.erase("material")
    app.toast("Took %s off %s." % [_placing.title, doc.label_of(id)])
  else:
    d.material = mat
    app.toast("Painted %s with %s." % [doc.label_of(id), _placing.title])
  doc.commit()


## Outlines the piece a click would paint.
func _show_paint_target(id: String) -> void:
  if _ghost:
    _ghost.free()
    _ghost = null
  var it := doc.item(id)
  if it.is_empty():
    return
  _ghost = ItemVisuals.lines(ItemVisuals.box_edges(Items.local_aabb(it.kind, it.data, doc.level).grow(0.05)), Color(0.4, 1.0, 0.6), true)
  _ghost.transform = Items.xform(it.kind, it.data)
  _vp.add_child(_ghost)


## The piece (shape or model) under the mouse, on any layer ("" if none).
func pick_piece(at: Vector2) -> String:
  var ray := _ray(at)
  var best := ""
  var best_dist := INF
  for p in doc.level.map.pieces:
    var xf := Items.xform("piece", p)
    var inv := xf.affine_inverse()
    var hit = Items.local_aabb("piece", p, doc.level).intersects_ray(inv * (ray[0] as Vector3), inv.basis * (ray[1] as Vector3))
    if hit != null and (xf * (hit as Vector3)).distance_to(ray[0]) < best_dist:
      best_dist = (xf * (hit as Vector3)).distance_to(ray[0])
      best = String(p.id)
  return best


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
            var handle := gizmo.hit(mb.position)
            if handle != "":
              gizmo.snap_step = app.snap_step
              gizmo.start(handle, mb.position)
            else:
              var id := pick(mb.position)
              doc.select(id)
              _begin_drag(id, mb.position)
        else:
          if gizmo.finish():
            _after_move(doc.selected)
            doc.commit()
          _end_drag()
  elif event is InputEventMouseMotion:
    var mm := event as InputEventMouseMotion
    if _orbiting:
      _yaw -= mm.relative.x * 0.006
      _pitch = clampf(_pitch - mm.relative.y * 0.006, deg_to_rad(-89.0), deg_to_rad(-5.0))
      _update_camera()
    elif _panning:
      _pan(Vector2(-mm.relative.x, mm.relative.y) * _dist * 0.0016)
    elif gizmo.is_dragging():
      gizmo.drag(mm.position, Input.is_key_pressed(KEY_ALT))
      var it := doc.item(doc.selected)
      var node: Node3D = _nodes.get(doc.selected)
      if node and not it.is_empty():
        if Items.resizable(it.kind, it.data) and gizmo.mode == TransformGizmo.Mode.SCALE:
          rebuild_item(doc.selected)
        else:
          node.transform = Items.xform(it.kind, it.data)
          refresh_overlay()
    elif not _drag.is_empty():
      _drag_to(mm.position)
    elif is_placing():
      _move_ghost(mm.position)
    else:
      gizmo.hit(mm.position)


func _begin_drag(id: String, at: Vector2) -> void:
  _drag = {}
  var it := doc.item(id)
  if it.is_empty() or not Items.movable(it.kind):
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
  var node: Node3D = _nodes.get(_drag.id)
  if node:
    node.transform = Items.xform(kind, d)
  refresh_overlay()


func _end_drag() -> void:
  if not _drag.is_empty() and _drag.moved:
    _after_move(_drag.id)
    doc.commit()
  _drag = {}


## Enemies that moved join the waves of the room they now stand in.
func _after_move(id: String) -> void:
  if doc.kind_of(id) == "enemy":
    doc.settle_enemy(id)
