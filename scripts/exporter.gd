class_name Exporter
extends RefCounted
## Writes a finished copy of a level: the four JSON files and the models it
## uses, into a folder or a zip. The copy leaves out imported models nothing
## uses. The level being edited isn't touched.


## A copy of the level's data, trimmed for export.
static func trimmed(level: LevelData) -> LevelData:
	var copy := LevelData.new()
	copy.dir = level.dir
	copy.meta = level.meta.duplicate(true)
	copy.map = level.map.duplicate(true)
	copy.interaction = level.interaction.duplicate(true)
	copy.combat = level.combat.duplicate(true)
	var used := {}
	for key in ["pieces", "decorations"]:
		for p in copy.map[key]:
			used[String(p.get("asset", ""))] = true
	copy.map.assets = (copy.map.assets as Array).filter(
		func(a: Dictionary) -> bool: return used.has(String(a.get("id", ""))))
	return copy


## Writes the level into `dest` (made if needed). Returns "" or what went wrong.
static func to_folder(level: LevelData, dest: String) -> String:
	var copy := trimmed(level)
	var source := level.dir
	var err := DirAccess.make_dir_recursive_absolute(dest)
	if err != OK:
		return "Couldn't make the folder %s (%s)." % [dest, error_string(err)]
	# Models first (and whatever a .gltf keeps beside it: .bin, textures).
	var assets_from := source.path_join("assets")
	if not (copy.map.assets as Array).is_empty() and source != dest:
		DirAccess.make_dir_recursive_absolute(dest.path_join("assets"))
		var wanted := {}
		var any_gltf := false
		for a in copy.map.assets:
			wanted[String(a.get("file", "")).get_file()] = true
			any_gltf = any_gltf or String(a.get("file", "")).to_lower().ends_with(".gltf")
		for file in DirAccess.get_files_at(assets_from):
			var ext := file.get_extension().to_lower()
			var model := ext in ["glb", "gltf"]
			if (model and wanted.has(file)) or (not model and any_gltf):
				err = DirAccess.copy_absolute(assets_from.path_join(file), dest.path_join("assets").path_join(file))
				if err != OK:
					return "Couldn't copy %s (%s)." % [file, error_string(err)]
	err = copy.save_dir(dest)
	if err != OK:
		return "Couldn't write the level files (%s)." % error_string(err)
	return ""


## Writes the level as a zip holding one folder named `folder_name`.
static func to_zip(level: LevelData, zip_path: String, folder_name: String) -> String:
	var temp := OS.get_user_data_dir().path_join("export_tmp").path_join(folder_name)
	_remove_dir(temp)
	var problem := to_folder(level, temp)
	if problem != "":
		return problem
	var zip := ZIPPacker.new()
	var err := zip.open(zip_path)
	if err != OK:
		return "Couldn't make %s (%s)." % [zip_path, error_string(err)]
	for file in _files_under(temp):
		zip.start_file(folder_name.path_join(file))
		zip.write_file(FileAccess.get_file_as_bytes(temp.path_join(file)))
		zip.close_file()
	zip.close()
	_remove_dir(temp)
	return ""


static func _files_under(dir: String, prefix := "") -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		out.append(prefix.path_join(file) if prefix != "" else file)
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_files_under(dir.path_join(sub), prefix.path_join(sub) if prefix != "" else sub))
	return out


static func _remove_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		_remove_dir(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
