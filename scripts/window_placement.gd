class_name WindowPlacement
extends RefCounted
## The editor window behaves like other editors (Grayson 2026-11-14): it
## resizes freely (the layout follows it), opens maximized the first time,
## and after that comes back the size, place and state (maximized or not)
## it was left in. Kept in the editor's settings (AppSettings).
##
## Left alone when Godot embeds the app in its Game tab (that tab sizes it:
## choose "Stretch to Fit" in the Game bar, or turn off "Embed Game on Next
## Play"), when --resolution / --position are given, in tests (a script
## runs the main loop) and without a display.

const MIN_SIZE := Vector2i(1024, 600)


static func _managed(window: Window) -> bool:
	if window == null or DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		return false
	if Engine.get_main_loop() and Engine.get_main_loop().get_script() != null:
		return false  # a test script runs the app
	for arg in OS.get_cmdline_args():
		if arg in ["--resolution", "--position", "-f", "--fullscreen", "-m", "--maximized", "-w", "--windowed"]:
			return false
	return true


## Puts the window where it was last time (maximized the first time).
static func restore(window: Window) -> void:
	if window == null or DisplayServer.get_name() == "headless":
		return
	window.min_size = MIN_SIZE
	if not _managed(window):
		return
	var rect = AppSettings.get_value("window_rect", null)
	if rect is Array and rect.size() == 4:
		var r := Rect2i(int(rect[0]), int(rect[1]), maxi(int(rect[2]), MIN_SIZE.x), maxi(int(rect[3]), MIN_SIZE.y))
		if _on_a_screen(r):
			window.mode = Window.MODE_WINDOWED
			window.size = r.size
			window.position = r.position
	if bool(AppSettings.get_value("window_maximized", true)):
		window.mode = Window.MODE_MAXIMIZED


## Remembers where the window is (called on resizes and on closing).
static func save(window: Window) -> void:
	if not _managed(window):
		return
	var maximized := window.mode == Window.MODE_MAXIMIZED or window.mode == Window.MODE_FULLSCREEN
	AppSettings.set_value("window_maximized", maximized)
	if window.mode == Window.MODE_WINDOWED:
		AppSettings.set_value("window_rect", [window.position.x, window.position.y, window.size.x, window.size.y])


## Whether most of a saved rect is still on a screen (a monitor may be gone).
static func _on_a_screen(r: Rect2i) -> bool:
	for i in DisplayServer.get_screen_count():
		var screen := DisplayServer.screen_get_usable_rect(i)
		var overlap := screen.intersection(r)
		if overlap.get_area() * 2 >= r.get_area() and r.size.x <= screen.size.x + 16 and r.size.y <= screen.size.y + 16:
			return true
	return false
