class_name Items
extends RefCounted
## Where an item is, how it's turned and how big it is, whatever kind it is.
## Map pieces, walls, boundaries and decorations turn on every axis ("rot",
## degrees); objects, enemies and the start only turn around ("yaw").
## Platforms are placed by their stops, hazards by their zones, and areas
## (rooms from the navmesh) sit at their seed point and can't be moved.

## Kinds that turn on all three axes.
const FULL_ROT := ["piece", "wall", "boundary", "decoration"]


static func get_pos(kind: String, d: Dictionary) -> Vector3:
  if kind == "object":
    if String(d.get("type", "")) == "platform":
      var pts: Array = d.get("points", [])
      return LevelData.vec3(pts[0]) if not pts.is_empty() else Vector3.ZERO
    if String(d.get("type", "")) == "hazard":
      var zones: Array = d.get("zones", [])
      return LevelData.vec3(zones[0].get("pos")) if not zones.is_empty() else Vector3.ZERO
  if kind == "area":
    return LevelData.vec3(d.get("seed"))
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
  elif kind == "area":
    return
  else:
    d.pos = LevelData.arr3(p)


static func movable(kind: String) -> bool:
  return kind != "area"


static func has_yaw(kind: String, d: Dictionary) -> bool:
  if kind == "area":
    return false
  if kind == "object" and String(d.get("type", "")) in ["platform", "hazard"]:
    return false
  return true


## Turns on every axis (else only around, if has_yaw).
static func full_rot(kind: String) -> bool:
  return FULL_ROT.has(kind)


static func get_yaw(kind: String, d: Dictionary) -> float:
  return get_rot(kind, d).y if has_yaw(kind, d) else 0.0


## Rotation in degrees (x, y, z).
static func get_rot(kind: String, d: Dictionary) -> Vector3:
  if full_rot(kind) and d.get("rot") is Array:
    return LevelData.vec3(d.rot)
  return Vector3(0, float(d.get("yaw", 0.0)), 0) if has_yaw(kind, d) else Vector3.ZERO


static func set_rot(kind: String, d: Dictionary, r: Vector3) -> void:
  r = Vector3(_wrap(r.x), _wrap(r.y), _wrap(r.z))
  if full_rot(kind):
    d.erase("yaw")
    if r.is_zero_approx():
      d.erase("rot")
    else:
      d.rot = [snappedf(r.x, 0.01), snappedf(r.y, 0.01), snappedf(r.z, 0.01)]
  elif has_yaw(kind, d):
    d.yaw = snappedf(fposmod(r.y, 360.0), 0.01)


static func _wrap(a: float) -> float:
  a = fposmod(a + 180.0, 360.0) - 180.0
  return 0.0 if is_equal_approx(a, 0.0) else a


## Turns an item around the vertical axis by `degrees`.
static func rotate(kind: String, d: Dictionary, degrees: float) -> void:
  if has_yaw(kind, d):
    var r := get_rot(kind, d)
    set_rot(kind, d, Vector3(r.x, r.y + degrees, r.z))


static func xform(kind: String, d: Dictionary) -> Transform3D:
  if full_rot(kind):
    var t := LevelNav.transform_of(d)
    return t
  return Transform3D(Basis(Vector3.UP, deg_to_rad(get_yaw(kind, d))), get_pos(kind, d))


# --- Size (the resize handles) -----------------------------------------------------------------

## Whether the resize handles work on an item.
static func resizable(kind: String, d: Dictionary) -> bool:
  match kind:
    "piece", "wall", "boundary":
      return true
    "decoration":
      return String(d.get("asset", "")) == "builtin:fireflies"
    "object":
      return String(d.get("type", "")) in ["trigger_zone", "platform", "door"]
  return false


## Whether the by-sides resize handles work (anything resizable that's a
## plain box; a platform is placed by its stops, so it isn't).
static func sides_resizable(kind: String, d: Dictionary) -> bool:
  if kind == "object" and String(d.get("type", "")) == "platform":
    return false
  # A curved wall's size runs along its curve, so its box isn't its size.
  return resizable(kind, d) and String(d.get("asset", "")) != "builtin:curved_wall"


## Which of the item's own axes can be resized ([x, y, z]). A boundary is a
## plane, so it has no thickness to pull.
static func resize_axes(kind: String, _d: Dictionary) -> Array:
  return [true, true, false] if kind == "boundary" else [true, true, true]


## The item's box in metres in its own frame (turned, not scaled), relative
## to where it's placed: what the by-sides handles slide.
static func sized_box(kind: String, d: Dictionary, level: LevelData) -> AABB:
  var box := local_aabb(kind, d, level)
  if scaled(kind, d):
    var sc := LevelData.vec3(d.get("scale"), Vector3.ONE)
    return AABB(box.position * sc, box.size * sc)
  return box


## True when the item's size is a "scale" on an imported model.
static func scaled(kind: String, d: Dictionary) -> bool:
  return kind == "piece" and not String(d.get("asset", "")).begins_with("builtin:")


## The item's size in metres along its own axes.
static func get_size(kind: String, d: Dictionary, level: LevelData) -> Vector3:
  if scaled(kind, d):
    return Models.aabb(level, String(d.get("asset", ""))).size * LevelData.vec3(d.get("scale"), Vector3.ONE)
  if kind == "boundary":
    var dims: Array = d.get("size", [8, 4])
    return Vector3(float(dims[0]), float(dims[1]), 0.1)
  if String(d.get("asset", "")) == "builtin:curved_wall":
    return LevelData.vec3(d.get("size"), Vector3(8, 3, 0.5))
  return local_aabb(kind, d, level).size


## Sizes are kept between 5 cm and 1 km a side.
const MAX_SIZE := 1000.0

static func set_size(kind: String, d: Dictionary, level: LevelData, size: Vector3) -> void:
  size = size.clamp(Vector3.ONE * 0.05, Vector3.ONE * MAX_SIZE)
  if scaled(kind, d):
    var base := Models.aabb(level, String(d.get("asset", ""))).size
    var sc := Vector3(size.x / maxf(base.x, 0.001), size.y / maxf(base.y, 0.001), size.z / maxf(base.z, 0.001))
    d.scale = [snappedf(sc.x, 0.001), snappedf(sc.y, 0.001), snappedf(sc.z, 0.001)]
  elif kind == "boundary":
    d.size = [snappedf(size.x, 0.01), snappedf(size.y, 0.01)]
  else:
    d.size = [snappedf(size.x, 0.01), snappedf(size.y, 0.01), snappedf(size.z, 0.01)]


## The item's box in its own space (see xform). `pick`: the part you click.
static func local_aabb(kind: String, d: Dictionary, level: LevelData, pick := false) -> AABB:
  match kind:
    "start":
      return _base(Vector3(1.0, 1.8, 1.0))
    "area":
      var centre := get_pos(kind, d)
      var box := AABB()
      var first := true
      for poly in d.get("polys", []):
        for v in poly:
          var p := LevelData.vec3(v) - centre
          box = AABB(p, Vector3.ZERO) if first else box.expand(p)
          first = false
      return box.grow(0.05) if not first else _base(Vector3(1, 0.1, 1))
    "boundary":
      var dims: Array = d.get("size", [8, 4])
      var w := float(dims[0])
      var h := float(dims[1]) if dims.size() > 1 else 4.0
      return AABB(Vector3(-w * 0.5, 0, -0.1 if pick else -0.05), Vector3(w, h, 0.2 if pick else 0.1))
    "wall":
      return _base(LevelData.vec3(d.get("size"), Vector3(4, 4, 0.4)))
    "piece", "decoration":
      var asset := String(d.get("asset", ""))
      match asset:
        "builtin:box", "builtin:ramp", "builtin:cylinder", "builtin:stairs":
          return _base(LevelData.vec3(d.get("size"), Vector3(4, 0.5, 4)))
        "builtin:curved_wall":
          var parts := LevelNav.builtin_meshes(asset, LevelData.vec3(d.get("size"), Vector3(8, 3, 0.5)), LevelNav.shape_params(d))
          return (parts[0][1] as Transform3D) * (parts[0][0] as Mesh).get_aabb()
        "builtin:fireflies":
          return _base(LevelData.vec3(d.get("size"), Vector3(6, 3, 6)))
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
