class_name AppSettings
extends RefCounted
## The editor's own settings (user://editor.cfg): where the game lives (for
## Playtest, enemy names and exporting into the game), what to run it with,
## where your levels are kept, and recently opened levels.

static var path := "user://editor.cfg"
static var _cfg: ConfigFile


static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(path)
	return _cfg


static func reload() -> void:
	_cfg = null


static func get_value(key: String, fallback: Variant = "") -> Variant:
	return _load().get_value("editor", key, fallback)


static func set_value(key: String, value: Variant) -> void:
	_load().set_value("editor", key, value)
	_cfg.save(path)


## The game's project folder (the one with project.godot), or "".
static func game_dir() -> String:
	return String(get_value("game_dir", ""))


static func has_game() -> bool:
	return game_dir() != "" and FileAccess.file_exists(game_dir().path_join("project.godot"))


## What Playtest runs: a Godot executable (run with the game folder) or an
## exported build of the game. Defaults to the Godot this editor runs on.
static func run_with() -> String:
	var p := String(get_value("run_with", ""))
	return p if p != "" else OS.get_executable_path()


## Where new levels are made.
static func library_dir() -> String:
	var p := String(get_value("library_dir", ""))
	if p != "":
		return p
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs != "" and DirAccess.dir_exists_absolute(docs):
		return docs.path_join("Nomad Seekers Levels")
	return ProjectSettings.globalize_path("user://levels")


static func recent() -> PackedStringArray:
	var out := PackedStringArray()
	for p in get_value("recent", PackedStringArray()):
		if LevelData.is_level_dir(String(p)):
			out.append(String(p))
	return out


static func add_recent(dir: String) -> void:
	var list := recent()
	var at := list.find(dir)
	if at >= 0:
		list.remove_at(at)
	list.insert(0, dir)
	if list.size() > 12:
		list.resize(12)
	set_value("recent", list)
