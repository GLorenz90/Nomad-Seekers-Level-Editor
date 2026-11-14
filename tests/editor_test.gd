extends SceneTree
## Headless checks of the editor's data side: rooms found from the navmesh,
## boundaries splitting them, sizes from the room count, surfaces, the export
## checks (leash rule, doors nothing opens, enemies off the navmesh), saving.
##   godot --headless --path . --script res://tests/editor_test.gd

var fails := 0


func check(cond: bool, label: String) -> void:
  print(("ok   " if cond else "FAIL ") + label)
  if not cond:
    fails += 1


func texts(problems: Array, severity := "") -> String:
  var out := ""
  for p in problems:
    if severity == "" or p.level == severity:
      out += String(p.text) + " | "
  return out


func floor_piece(doc: EditorDoc, pos: Vector3, size: Vector3) -> String:
  return doc.add("piece", {"asset": "builtin:box", "size": LevelData.arr3(size), "pos": LevelData.arr3(pos - Vector3(0, size.y, 0)), "surface": "floor"})


func wall(doc: EditorDoc, pos: Vector3, size: Vector3) -> String:
  return doc.add("piece", {"asset": "builtin:box", "size": LevelData.arr3(size), "pos": LevelData.arr3(pos), "surface": "obstacle"})


func _init() -> void:
  var dir := "/tmp/ed_test_v2"
  DirAccess.make_dir_recursive_absolute(dir)
  var doc := EditorDoc.create("Test", "forest", dir)
  check(not doc.level.meta.has("size"), "a new level has no size to pick")

  # One floor: one room, blue.
  floor_piece(doc, Vector3(0, 0, 0), Vector3(32, 0.5, 16))
  doc.commit()
  doc.update_nav()
  check(doc.level.map.areas.size() == 1, "a floor makes one room (%d)" % doc.level.map.areas.size())
  var first := String(doc.level.map.areas[0].id)
  check(first == "room_1" and doc.level.size() == "arena", "it's room_1, and one room is an Arena")
  var blue := ItemVisuals._color(doc.level.map.areas[0].color, Color.BLACK)
  check(blue.b > blue.r and blue.b > blue.g, "the first room is blue (%s)" % blue)

  # A wall with a doorway, and a boundary across the doorway: two rooms.
  wall(doc, Vector3(0, 0, -5), Vector3(0.5, 3, 6))
  wall(doc, Vector3(0, 0, 5), Vector3(0.5, 3, 6))
  var b := doc.add("boundary", {"pos": [0, 0, 0], "rot": [0, 90, 0], "size": [4, 3]})
  doc.commit()
  doc.update_nav()
  check(doc.level.map.areas.size() == 2, "a boundary across the doorway splits it into two rooms (%d)" % doc.level.map.areas.size())
  check(doc.level.find_area(first).size() > 0, "the first room keeps its id")
  var second := ""
  for a in doc.level.map.areas:
    if String(a.id) != first:
      second = String(a.id)
  check(doc.room_at(Vector3(-8, 0, 0)) != doc.room_at(Vector3(8, 0, 0)) and doc.room_at(Vector3(8, 0, 0)) != "", "each side of the boundary is its own room")
  check(doc.level.find_area(first).color != doc.level.find_area(second).color, "the new room gets a new color")
  check(doc.level.size() == "", "two rooms fit no size")
  check(texts(LevelCheck.run(doc), "error").contains("fits no level size"), "and the check says so")

  # Make the second one a corridor: back to an Arena with a corridor (error).
  doc.level.find_area(second).kind = "corridor"
  doc.commit()
  check(doc.level.room_count() == 1 and doc.level.corridor_count() == 1, "a room can be marked as a corridor")
  check(texts(LevelCheck.run(doc), "error").contains("An Arena is one room"), "an Arena can't have a corridor")

  # Remove the boundary: the two merge into the older one.
  doc.remove(b)
  doc.commit()
  doc.update_nav()
  check(doc.level.map.areas.size() == 1 and String(doc.level.map.areas[0].id) == first, "removing the boundary merges them into the first room")

  # Joining: split again, then join the second into the first.
  b = doc.add("boundary", {"pos": [0, 0, 0], "rot": [0, 90, 0], "size": [4, 3]})
  doc.commit()
  doc.update_nav()
  second = ""
  for a in doc.level.map.areas:
    if String(a.id) != first:
      second = String(a.id)
  doc.join_areas(first, second)
  doc.commit()
  doc.update_nav()
  check(doc.level.map.areas.size() == 1 and doc.room_at(Vector3(8, 0, 0)) == first, "joining makes both sides one room")
  doc.split_area(first)
  doc.commit()
  doc.update_nav()
  check(doc.level.map.areas.size() == 2, "splitting the join gives two rooms again")

  # Surfaces: intangible pieces don't change the navmesh; obstacles cut it.
  var left := doc.room_at(Vector3(-8, 0, 0))
  var ghost := doc.add("piece", {"asset": "builtin:box", "size": [4, 2, 4], "pos": [-8, 0, 0], "surface": "intangible"})
  doc.commit()
  doc.update_nav()
  check(left != "" and doc.room_at(Vector3(-8, 0, 0)) == left, "an intangible box doesn't block the navmesh")
  doc.find(ghost).surface = "obstacle"
  doc.commit()
  doc.update_nav()
  check(doc.room_at(Vector3(-8, 0, 0)) == "", "an obstacle box does (and nothing stands on top of it)")
  check(doc.room_at(Vector3(-8, 2.2, 0)) == "", "its top isn't walkable")
  doc.find(ghost).surface = "floor"
  doc.commit()
  doc.update_nav()
  check(doc.room_at(Vector3(-8, 2.2, 0)) != "", "a floor block can be stood on (its top is a room of its own)")
  doc.remove(ghost)
  doc.commit()

  # Model surfaces and per-copy overrides.
  doc.level.map.assets.append({"id": "rock", "file": "assets/rock.glb", "surface": "obstacle", "hitbox": "convex"})
  var p := {"asset": "rock"}
  check(doc.level.surface_of(p) == "obstacle" and doc.level.hitbox_of(p) == "convex", "a copy uses its model's surface and hitbox")
  p.surface = "floor"
  check(doc.level.surface_of(p) == "floor", "unless it overrides them")
  doc.level.map.assets.clear()

  # Turning and resizing (the handles' data side).
  var w := wall(doc, Vector3(10, 0, 6), Vector3(4, 3, 0.5))
  var wd := doc.find(w)
  Items.set_rot("piece", wd, Vector3(0, 90, 15))
  check(Items.get_rot("piece", wd).is_equal_approx(Vector3(0, 90, 15)), "pieces turn on every axis")
  Items.set_size("piece", wd, doc.level, Vector3(6, 3, 0.5))
  check(LevelData.vec3(wd.size).is_equal_approx(Vector3(6, 3, 0.5)), "built-in shapes resize")
  var bd := doc.find(b)
  Items.set_size("boundary", bd, doc.level, Vector3(5, 4, 1))
  check(bd.size == [5.0, 4.0], "boundaries resize as a plane")
  doc.remove(w)
  doc.commit()

  # A boundary too narrow to close the doorway warns.
  var narrow := doc.add("boundary", {"pos": [10, 0, 0], "rot": [0, 90, 0], "size": [2, 3]})
  doc.commit()
  check(texts(LevelCheck.for_id(LevelCheck.run(doc), narrow), "warning").contains("doesn't split anything"), "a boundary the navmesh goes round is flagged")
  doc.remove(narrow)
  doc.commit()

  # Export checks.
  var e := doc.add("enemy", {"enemy": "grub_hound", "pos": [-8, 0, 0], "wander": true, "wander_radius": 10.0, "limited_chase": true, "chase_radius": 5.0})
  doc.commit()
  var probs := LevelCheck.run(doc)
  check(texts(LevelCheck.for_id(probs, e), "error") != "", "chase shorter than wander is an error")
  doc.find(e).chase_radius = 15.0
  doc.commit()
  check(texts(LevelCheck.for_id(LevelCheck.run(doc), e), "error") == "", "chase longer than wander is fine")
  var lost := doc.add("enemy", {"enemy": "grub_hound", "pos": [80, 0, 80]})
  doc.commit()
  check(texts(LevelCheck.for_id(LevelCheck.run(doc), lost), "error").contains("outside every room"), "an enemy off the navmesh is an error")
  doc.remove(lost)
  var door := doc.add("object", {"type": "door", "start": "closed", "pos": [0, 0, 0], "yaw": 90})
  doc.commit()
  check(texts(LevelCheck.for_id(LevelCheck.run(doc), door), "error") != "", "a door nothing opens is an error")
  doc.level.map.start.pos = [50, 0, 50]
  doc.commit()
  check(texts(LevelCheck.for_id(LevelCheck.run(doc), EditorDoc.START), "error").contains("isn't on the navmesh"), "a start off the navmesh is an error")
  doc.level.map.start.pos = [-6, 0, 4]
  doc.commit()

  # Save and reopen: areas keep their polygons for the game.
  check(doc.save() == OK, "the level saves")
  var again := EditorDoc.open(dir)
  check(again != null and again.items().size() == doc.items().size(), "and reopens with every item")
  check(again != null and not (again.level.map.areas[0].get("polys", []) as Array).is_empty(), "rooms are saved with their navmesh polygons")
  check(again != null and again.level.area_at(Vector3(-8, 0, 0)) == left and again.level.area_at(Vector3(8, 0, 0)) != left,
    "the game can tell which room a point is in")

  # Undo.
  var before := doc.items().size()
  doc.add("enemy", {"enemy": "grub_hound", "pos": [-6, 0, 2]})
  doc.commit()
  doc.undo()
  check(doc.items().size() == before, "undo removes the last addition")

  # The bundled example.
  var ex_dir := ProjectSettings.globalize_path("res://examples/starter_large")
  if FileAccess.file_exists(ex_dir.path_join("level.json")):
    var ex := EditorDoc.open(ex_dir)
    check(ex != null and ex.level.room_count() == 15, "the starter example has 15 rooms")
    check(ex != null and LevelCheck.errors(LevelCheck.run(ex)).is_empty(), "the starter example has nothing to fix: " + (texts(LevelCheck.run(ex)) if ex else ""))
  print("FAILS: ", fails)
  quit(fails)
