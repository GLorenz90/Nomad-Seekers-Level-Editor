class_name QuestDoc
extends RefCounted
## A quest folder (Grayson 2026-11-13: quests are sessions, like PSO):
##   <quest>/quest.json      title, client, briefing, reward, steps, areas
##   <quest>/nomad2/         what it adds to Nomad-2: a level folder (kind
##                           "nomad2") laid over a read-only copy of Nomad-2
##   <quest>/levels/<name>/  levels only this quest uses
## The game's QuestBook reads the same files (docs/level_format.md, "Quests").
## The editor edits one level at a time; a level inside a quest folder knows
## its quest (EditorDoc.quest), so its wiring can name the quest's steps and
## people.

const STEP_TYPES := [["event", "Done by a trigger (talk, deliver, reach a spot...)"],
	["clear", "Clear every room of an area in one trip"], ["defeat", "Defeat a number of an enemy"],
	["bank_lumidium", "Bank Lumidium at teleporters"]]

var dir := ""
var data := {}


static func create(folder: String, title: String) -> QuestDoc:
	var q := QuestDoc.new()
	q.dir = folder
	q.data = {"format": 1, "id": EditorDoc.slug(title), "title": title, "client": "", "text": "", "reward": 500,
		"steps": [{"id": "step_1", "type": "event", "goal": ""}], "areas": []}
	return q


## The quest in a folder (null if it has no quest.json).
static func open(folder: String) -> QuestDoc:
	var path := folder.path_join("quest.json")
	if not FileAccess.file_exists(path):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return null
	var q := QuestDoc.new()
	q.dir = folder
	q.data = parsed
	if not (q.data.get("steps") is Array):
		q.data.steps = []
	if not (q.data.get("areas") is Array):
		q.data.areas = []
	return q


## The quest a level folder belongs to: its nomad2/ or levels/<name>/.
static func find_for(level_dir: String) -> QuestDoc:
	if level_dir == "":
		return null
	var parent := level_dir.get_base_dir()
	if level_dir.get_file() == "nomad2":
		return open(parent)
	if parent.get_file() == "levels":
		return open(parent.get_base_dir())
	return null


func save() -> Error:
	var f := FileAccess.open(dir.path_join("quest.json"), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t", false))
	f.close()
	return OK


func title() -> String:
	return String(data.get("title", "Quest"))


func nomad2_dir() -> String:
	return dir.path_join("nomad2")


func levels_dir() -> String:
	return dir.path_join("levels")


## The quest's own levels, by folder name.
func levels() -> PackedStringArray:
	var out := PackedStringArray()
	if DirAccess.dir_exists_absolute(levels_dir()):
		for sub in DirAccess.get_directories_at(levels_dir()):
			if LevelData.is_level_dir(levels_dir().path_join(sub)):
				out.append(sub)
	out.sort()
	return out


func steps() -> Array:
	return data.get("steps", [])


## [[id, "1. goal"]...] for pickers.
func step_options() -> Array:
	var out := []
	var list := steps()
	for i in list.size():
		var s: Dictionary = list[i]
		var goal := String(s.get("goal", ""))
		out.append([String(s.get("id", "")), "%d. %s" % [i + 1, goal if goal != "" else String(s.get("id", ""))]])
	return out


func has_step(id: String) -> bool:
	for s in steps():
		if String(s.get("id", "")) == id:
			return true
	return false


## A new step id from its goal ("Talk to Brandt" -> talk_to_brandt), unique.
func new_step_id(goal: String) -> String:
	var base := EditorDoc.slug(goal).left(24).trim_suffix("_") if goal.strip_edges() != "" else "step"
	if base == "level":
		base = "step"
	var id := base
	var n := 2
	while has_step(id):
		id = "%s_%d" % [base, n]
		n += 1
	return id


## The people the quest puts on Nomad-2 (for escorts in its levels).
func nomad2_people() -> Array:
	var level := LevelData.load_dir(nomad2_dir())
	if level == null:
		return []
	return level.interaction.objects.filter(func(o): return String(o.get("type", "")) == "person")


## Problems with the quest itself (not its levels): [text...].
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if title().strip_edges() == "":
		out.append("The quest has no title. Set one in Quest > Quest details.")
	if steps().is_empty():
		out.append("The quest has no steps. Add at least one in Quest > Quest details.")
	if (data.get("areas", []) as Array).is_empty():
		out.append("The quest goes nowhere: add an area or one of its own levels in Quest > Quest details.")
	var seen := {}
	for s in steps():
		var id := String(s.get("id", ""))
		if id == "" or seen.has(id):
			out.append("Two steps have the same id (\"%s\")." % id)
		seen[id] = true
		match String(s.get("type", "event")):
			"defeat":
				if String(s.get("enemy", "")) == "":
					out.append("Step \"%s\" asks to defeat an enemy, but doesn't say which." % id)
	for a in data.get("areas", []):
		var own := String(a.get("quest_level", ""))
		if own != "" and not levels().has(own):
			out.append("The quest goes to its level \"%s\", which isn't in its levels folder." % own)
		if own == "" and String(a.get("area", "")) == "":
			out.append("One of the quest's areas has no area or level chosen.")
		var after := String(a.get("opens_after", ""))
		if after != "" and not has_step(after):
			out.append("\"%s\" opens after step \"%s\", which the quest doesn't have." % [a.get("name", "An area"), after])
		if a.has("opens_with") and String(a.opens_with) == "":
			out.append("\"%s\" opens with a quest flag, but no flag is named." % a.get("name", "An area"))
	var endings: Array = data.get("endings", [])
	for i in endings.size():
		var e: Dictionary = endings[i]
		for c in e.get("if", []):
			if String(c.get("flag", "")) == "":
				out.append("Ending %d checks a flag with no name." % (i + 1))
		for k in (e.get("sets", {}) as Dictionary):
			if String(k) == "":
				out.append("Ending %d sets a story flag with no name." % (i + 1))
		if (e.get("if", []) as Array).is_empty() and i < endings.size() - 1:
			out.append("Ending %d has no conditions, so the endings after it can never be reached. Move it last." % (i + 1))
	for c in data.get("requires", []):
		if String(c.get("flag", "")) == "":
			out.append("\"Offered only if\" names no story flag.")
	return out
