class_name Licenses
extends RefCounted
## A level's licenses folder: one optional place for the license files of
## whatever the builder brought in (a model pack's License.txt, a note from an
## artist). Nothing is required; the files just travel with the level when
## it's exported or shared. The game never reads them.

const FOLDER := "licenses"
## Text and document files only. A file with no extension (LICENSE, COPYING)
## is kept as .txt.
const FILES := ["txt", "md", "pdf", "rtf", "html", "htm"]
const FILTERS := ["*.txt,*.md,*.pdf,*.rtf,*.html,*.htm,LICENSE,LICENCE,COPYING,NOTICE ; License files", "* ; Any file"]


static func folder(level: LevelData) -> String:
	return level.dir.path_join(FOLDER)


## The license files in the level, by name.
static func list(level: LevelData) -> PackedStringArray:
	var dir := folder(level)
	if level.dir == "" or not DirAccess.dir_exists_absolute(dir):
		return PackedStringArray()
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if FILES.has(f.get_extension().to_lower()):
			out.append(f)
	out.sort()
	return out


## Copies a file into the licenses folder. Returns the name it's kept under,
## or "" if it isn't a text or document file or couldn't be copied. Adding
## the same file twice keeps one copy.
static func add_file(level: LevelData, path: String) -> String:
	var ext := path.get_extension().to_lower()
	var base := path.get_file().get_basename() if ext != "" else path.get_file()
	if ext == "":
		ext = "txt"
	elif not FILES.has(ext):
		return ""
	var name := _free_name(level, _clean(base), ext, FileAccess.get_md5(path))
	if name.begins_with("="):
		return name.substr(1)
	if DirAccess.copy_absolute(path, folder(level).path_join(name)) != OK:
		return ""
	return name


## Writes a license typed in the editor as a .txt file; returns its name.
static func write(level: LevelData, title: String, text: String) -> String:
	var base := _clean(title) if title.strip_edges() != "" else "license"
	var name := _free_name(level, base, "txt", "")
	var f := FileAccess.open(folder(level).path_join(name), FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(text.strip_edges() + "\n")
	f.close()
	return name


static func remove(level: LevelData, name: String) -> void:
	if list(level).has(name):
		DirAccess.remove_absolute(folder(level).path_join(name))


## Copies the licenses folder into an exported level.
static func copy_to(level: LevelData, dest: String) -> String:
	var files := list(level)
	if files.is_empty() or dest == level.dir:
		return ""
	DirAccess.make_dir_recursive_absolute(dest.path_join(FOLDER))
	for f in files:
		var err := DirAccess.copy_absolute(folder(level).path_join(f), dest.path_join(FOLDER).path_join(f))
		if err != OK:
			return "Couldn't copy the license %s (%s)." % [f, error_string(err)]
	return ""


## A file name that's safe on every system (keeps case and spaces readable).
static func _clean(base: String) -> String:
	var out := ""
	for ch in base.strip_edges():
		out += ch if (ch.is_valid_identifier() or ch in " -.()" or (ch >= "0" and ch <= "9")) else "_"
	out = out.strip_edges().trim_prefix(".")
	return out if out != "" else "license"


## The first unused name for base.ext; "=name" if a file with the same
## contents (md5) is already there under that name.
static func _free_name(level: LevelData, base: String, ext: String, md5: String) -> String:
	DirAccess.make_dir_recursive_absolute(folder(level))
	var name := base + "." + ext
	var n := 2
	while FileAccess.file_exists(folder(level).path_join(name)):
		if md5 != "" and FileAccess.get_md5(folder(level).path_join(name)) == md5:
			return "=" + name
		name = "%s (%d).%s" % [base, n, ext]
		n += 1
	return name
