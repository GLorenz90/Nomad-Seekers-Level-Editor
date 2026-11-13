extends SceneTree
func _init() -> void:
	var app: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	for i in 5:
		await process_frame
	app.open_path(OS.get_environment("SHOT_DIR") if OS.get_environment("SHOT_DIR") != "" else "/tmp/ed_test_level")
	app.set_layer(int(OS.get_environment("SHOT_LAYER")) if OS.get_environment("SHOT_LAYER") != "" else 1)
	if OS.get_environment("SHOT_TOP") == "1":
		app.toggle_top()
	if OS.get_environment("SHOT_MODE") != "":
		app.set_gizmo_mode(int(OS.get_environment("SHOT_MODE")))
	if OS.get_environment("SHOT_SIDES") == "1":
		app.set_gizmo_mode(TransformGizmo.Mode.SCALE)
		app.set_gizmo_mode(TransformGizmo.Mode.SCALE)
	if OS.get_environment("SHOT_LOCAL") == "1":
		app.set_local(true)
	if OS.get_environment("SHOT_ORTHO") == "1":
		app.set_ortho(true)
	if OS.get_environment("SHOT_DIST") != "":
		app.view._dist = float(OS.get_environment("SHOT_DIST"))
		app.view._update_camera()
	if OS.get_environment("SHOT_SEL") != "":
		app.doc.select(OS.get_environment("SHOT_SEL"))
		app.view.focus(OS.get_environment("SHOT_SEL"))
		app.view._dist = float(OS.get_environment("SHOT_SELDIST")) if OS.get_environment("SHOT_SELDIST") != "" else 45.0
		app.view._update_camera()
	for i in 40:
		await process_frame
	for w in root.find_children("*", "Window", true, false):
		w.hide()
	await create_timer(0.5).timeout
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	quit()
