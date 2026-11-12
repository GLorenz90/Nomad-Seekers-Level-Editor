extends SceneTree
func _init() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var app := scene.instantiate()
	root.add_child(app)
	await process_frame
	print("app up, doc=", app.doc)
	var doc := EditorDoc.create("Smoke", "small", "forest", "/tmp/smoke_level")
	print("created ", doc)
	app.set_doc(doc)
	await process_frame
	print("problems: ", app.problems.size())
	for p in app.problems:
		print(" ", p.level, ": ", p.text)
	quit()
