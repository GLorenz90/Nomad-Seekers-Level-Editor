extends SceneTree
## Real mouse clicks on the Place list (needs a window):
##   godot --path . --resolution 1600x900 --script res://tests/palette_click_test.gd
## Right-clicking a folder, a category or a model opens its menu; a
## left-click opens and closes a folder. (Folder rows used to be
## unselectable, and Godot's Tree reports no clicks on those, so their menu
## never opened; and Godot 4.7 reports the click's x wrongly, so the row is
## found from the mouse position.)

var fails := 0
var app: Control
var pal: Palette


func check(cond: bool, label: String) -> void:
  print(("ok   " if cond else "FAIL ") + label)
  if not cond:
    fails += 1


func frames(n := 3) -> void:
  for i in n:
    await process_frame


func click(row: TreeItem, button: MouseButton) -> void:
  pal._tree.scroll_to_item(row, true)
  await frames()
  var r: Rect2 = pal._tree.get_item_area_rect(row)
  var at: Vector2 = pal._tree.get_screen_transform() * (r.position + Vector2(70, r.size.y / 2))
  var mm := InputEventMouseMotion.new()
  mm.position = at
  mm.global_position = at
  Input.parse_input_event(mm)
  await frames(2)
  for pressed in [true, false]:
    var mb := InputEventMouseButton.new()
    mb.button_index = button
    mb.pressed = pressed
    mb.position = at
    mb.global_position = at
    Input.parse_input_event(mb)
    await process_frame
  await frames()


func menu_items() -> Array:
  return range(pal._menu.item_count).map(func(i): return pal._menu.get_item_text(i))


func _init() -> void:
  app = load("res://scenes/main.tscn").instantiate()
  root.add_child(app)
  await frames(5)
  app.set_doc(EditorDoc.create("Clicks", "", "/tmp/palette_click_level"))
  await frames(5)
  for w in root.find_children("*", "Window", true, false):
    w.hide()
  pal = app.palette
  var doc: EditorDoc = app.doc
  doc.add_folder("prefab", "Caves")
  doc.level.map.assets.append({"id": "cave_mouth", "file": "assets/cave_mouth.glb", "category": "prefab", "folder": "Caves/Big"})
  doc.commit()
  pal.refresh(true)
  await frames()

  var caves := pal.find_row("Prefabs/Caves")
  await click(caves, MOUSE_BUTTON_RIGHT)
  check(pal._menu.visible and menu_items().has("Delete folder and everything in it...") and menu_items().has("Model settings for everything in here..."),
    "right-clicking a folder opens its menu")
  check(not caves.is_selected(0), "and leaves nothing selected")
  pal._menu.hide()
  await frames()
  var was := caves.collapsed
  await click(caves, MOUSE_BUTTON_LEFT)
  check(caves.collapsed != was and not pal._menu.visible, "left-clicking a folder opens or closes it")
  await click(caves, MOUSE_BUTTON_LEFT)
  check(caves.collapsed == was, "and again the other way")

  var cat := pal.find_row("Prefabs")
  await click(cat, MOUSE_BUTTON_RIGHT)
  check(pal._menu.visible and menu_items().has("New folder..."), "right-clicking a category opens its menu")
  pal._menu.hide()
  await frames()

  pal._set_collapsed(cat, false)
  await frames()
  var model := pal.find_row("Cave Mouth")
  await click(model, MOUSE_BUTTON_RIGHT)
  check(pal._menu.visible and menu_items().has("Model settings..."), "right-clicking a model opens its menu (%s)" % ", ".join(menu_items()))
  pal._menu.hide()

  print("FAILS: ", fails)
  quit(fails)
