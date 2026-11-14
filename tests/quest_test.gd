extends SceneTree
## Quests in the editor (Grayson 2026-11-13), through the real app
## (headless): the game's example quest (copied in) opens at its Nomad-2
## additions over the fixed copy of Nomad-2, people and their sections,
## the quest wiring, the checks, Quest details, new quests and quest levels,
## and Check and export.
##   godot --headless --path . --script res://tests/quest_test.gd
## Needs the game next to the editor (../nomad-seekers) for the example.

const GAME_QUEST := "res://../nomad-seekers/quests/foremans_favour"

var fails := 0
var app: Control


func check(cond: bool, label: String) -> void:
	print(("ok   " if cond else "FAIL ") + label)
	if not cond:
		fails += 1


func settle(n := 3) -> void:
	for i in n:
		await process_frame


func rm(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		rm(path.path_join(d))
	DirAccess.remove_absolute(path)


func copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(f), to.path_join(f))
	for d in DirAccess.get_directories_at(from):
		copy_tree(from.path_join(d), to.path_join(d))


func texts(problems: Array) -> String:
	return " | ".join(problems.map(func(p): return String(p.text)))


func _init() -> void:
	var lib := "/tmp/quest_test_lib"
	rm(lib)
	DirAccess.make_dir_recursive_absolute(lib)
	AppSettings.set_value("library_dir", lib)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await settle()

	# --- The game's example quest ---------------------------------------------------------------
	var source := ProjectSettings.globalize_path(GAME_QUEST).simplify_path()
	var dir := lib.path_join("quests/foremans_favour")
	copy_tree(source, dir)
	app.quests.open_quest_dir(dir)
	await settle()
	var doc: EditorDoc = app.doc
	check(doc != null and doc.level.dir == dir.path_join("nomad2"), "a quest opens at its Nomad-2 additions")
	check(doc.quest != null and doc.quest.title() == "The Foreman's Favour" and doc.is_nomad2(), "which know their quest")
	check(doc.base_pieces().size() >= 10 and not (doc.base.get("markers", []) as Array).is_empty(), "Nomad-2's fixed copy is loaded (%d pieces)" % doc.base_pieces().size())
	check(app.view._items.find_child("Nomad2", false, false) != null, "and drawn under the quest's things")
	var ids: Array = doc.items().map(func(it): return it.id)
	check(not ids.has("nomad2_floor"), "but Nomad-2's pieces can't be selected or edited")
	doc.update_nav(true)
	check(doc.nav.has("mesh") and (doc.nav.mesh as NavigationMesh).get_polygon_count() > 0, "the navmesh covers Nomad-2's floor")
	check(doc.level.map.areas.is_empty(), "and an overlay keeps no rooms")
	check(Catalog.quest_steps.size() == 4, "the quest's steps are offered to fields (%d)" % Catalog.quest_steps.size())
	var problems := LevelCheck.run(doc)
	check(LevelCheck.errors(problems).is_empty(), "the example's Nomad-2 has nothing to fix (%s)" % texts(LevelCheck.errors(problems)))
	app.set_layer(3)
	check(app.layer == 2, "Nomad-2 has no Combat layer")

	# --- People -------------------------------------------------------------------------------
	var entry: Dictionary = Catalog.palette(2, doc).filter(func(e): return e.title == "Person")[0]
	check(entry.group == "People", "Person is in the Interaction palette, under People")
	var pid := doc.add("object", app.view._template_at(entry, Vector3(2, 0, 2)))
	doc.find(pid).name = "Rina Heimar"
	doc.commit()
	doc.select(pid)
	await settle()
	var fields: Array = Catalog.fields("object", doc.find(pid), doc.level).map(func(f): return f.k)
	check(fields.has("name") and fields.has("look.color") and fields.has("show_from") and fields.has("show_until") and fields.has("walking"),
		"a person's fields: name, look, when they're around, walking")
	var inspector_text := "\n".join(app.inspector.find_children("*", "Label", true, false).map(func(l): return (l as Label).text))
	check(inspector_text.contains("What they say") and inspector_text.contains("Walk route"), "the inspector has What they say and Walk route")
	check(texts(LevelCheck.run(doc)).contains("has nothing to say"), "someone with nothing to say gets a note")
	var did := doc.add_dialogue("Rina Heimar")
	doc.find(pid).talk = [{"dialogue": did}, {"dialogue": did, "from_step": "survey"}]
	doc.find(pid).route = {"points": [[2, 0, 2], [6, 0, 2]], "mode": "back_and_forth"}
	doc.find(pid).show_from = "nope"
	doc.commit()
	check(texts(LevelCheck.run(doc)).contains("waits for quest step \"nope\""), "a person waiting on a step the quest lacks is caught")
	doc.find(pid).show_from = "talk_foreman"
	doc.commit()
	await settle(6)
	var node: Node3D = app.view._nodes.get(pid)
	check(node != null and node.find_children("*", "Label3D", true, false).any(func(l): return (l as Label3D).text == "walk 2"),
		"their walk route is drawn")

	# --- Quest wiring -------------------------------------------------------------------------
	check(Wiring.candidates("step", doc).size() == 4, "triggers can pick the quest's steps")
	check(Wiring.candidates("person", doc).map(func(c): return c[0]).has(pid), "and its people")
	check(Wiring.events_for("object", doc.find(pid), doc).has("talked"), "a person sets off \"talked\"")
	var rule := {"id": "", "when": {"event": "talked", "source": pid},
		"if": [{"check": "has_item", "item": "hp_gel", "amount": 1, "is": true}, {"check": "quest_step", "step": "deliver", "is": "current"}],
		"do": [{"action": "take_item", "item": "hp_gel", "amount": 1}, {"action": "complete_step", "target": "deliver"},
			{"action": "set_talk", "target": pid, "dialogue": did}, {"action": "walk", "target": pid}]}
	var said := Wiring.describe(rule, doc)
	check(said.contains("talks to Rina Heimar") and said.contains("has 1 HP Gel") and said.contains("take 1 HP Gel")
		and said.contains("complete quest step \"4.") and said.contains("have Rina Heimar (%s) walk their route" % pid), "quest triggers read as sentences (%s)" % said)
	app.dialogs.edit_rule(rule)
	await settle()
	var editor := app.dialogs._open as ConfirmationDialog
	var options := editor.find_children("*", "OptionButton", true, false) if editor else []
	var labels := []
	for o in options:
		for i in (o as OptionButton).item_count:
			labels.append((o as OptionButton).get_item_text(i))
	check(labels.has("Quest step") and labels.has("The Seeker who talked has") and labels.has("Complete a quest step"),
		"the trigger editor offers the quest's conditions and actions")
	editor.confirmed.emit()
	await settle()
	check(LevelCheck.errors(LevelCheck.run(doc)).is_empty(), "a good quest trigger raises nothing (%s)" % texts(LevelCheck.errors(LevelCheck.run(doc))))
	var saved_rule: Dictionary = doc.level.interaction.rules[doc.level.interaction.rules.size() - 1]
	saved_rule["do"][1].target = "made_up"
	doc.commit()
	check(texts(LevelCheck.run(doc)).contains("completes quest step \"made_up\""), "completing a step the quest lacks is caught")
	saved_rule["do"][1].target = "deliver"
	doc.commit()
	var story_rule := {"id": "", "when": {"event": "talked", "source": pid}, "if": [{"check": "story_flag", "flag": "foreman_friend", "is": true}],
		"do": [{"action": "set_story_flag", "flag": "met_rina", "value": true}]}
	check(Wiring.describe(story_rule, doc).contains("story flag \"foreman_friend\" is on") and Wiring.describe(story_rule, doc).contains("set story flag \"met_rina\" on"),
		"story flags read as sentences")
	doc.find(pid).talk.append({"dialogue": did, "flag": "", "story": true})
	doc.commit()
	check(texts(LevelCheck.run(doc)).contains("waits on a flag with no name"), "a line waiting on an unnamed flag is caught")
	doc.find(pid).talk[2].flag = "foreman_friend"
	doc.commit()
	doc.select(pid)
	await settle(4)
	var says := []
	for o in app.inspector.find_children("*", "OptionButton", true, false):
		says.append((o as OptionButton).get_item_text((o as OptionButton).selected))
	check(says.has("When a story flag is...") and says.has("After step 3: Take Lapis to the beacon at the survey site."),
		"what they say: lines by step and by flag")
	doc.save()

	# --- Quest details ---------------------------------------------------------------------------
	app.quests.quest_details()
	await settle()
	var details := app.dialogs._open as ConfirmationDialog
	check(details != null and details.title.begins_with("Quest:"), "Quest details opens")
	var goals := details.find_children("*", "LineEdit", true, false).map(func(e): return (e as LineEdit).text) if details else []
	check(goals.has("Talk to Foreman Petram Solidus by the teleporter.") and goals.has("Survey site"), "with its steps and areas")
	var detail_labels := details.find_children("*", "Label", true, false).map(func(l): return (l as Label).text) if details else []
	var detail_options := []
	for o in (details.find_children("*", "OptionButton", true, false) if details else []):
		detail_options.append((o as OptionButton).get_item_text((o as OptionButton).selected))
	check(detail_labels.has("ENDINGS") and detail_labels.has("OFFERED ONLY IF") and detail_labels.has("Ending 2  (the default: no conditions)"),
		"Quest details has endings and story-flag requirements")
	check(detail_options.any(func(t): return String(t).begins_with("After step 2:")) and detail_options.any(func(t): return String(t).begins_with("After step 3:")),
		"each area says when it opens (in order: %s)" % ", ".join(detail_options.filter(func(t): return String(t).begins_with("After"))))
	var opened: Dictionary = app.quests._data.endings[0]
	check(int(opened.get("reward", 0)) == 1000 and opened.sets.has("foreman_friend") and opened["if"][0].flag == "gave_crew",
		"the crew ending: its flag, reward and story flag")
	app.quests._data.reward = 950
	(app.quests._data.steps as Array).append({"id": "report_back", "type": "event", "goal": "Tell the foreman."})
	details.confirmed.emit()
	await settle()
	var reread := QuestDoc.open(dir)
	check(int(reread.data.reward) == 950 and reread.steps().size() == 5, "saving writes quest.json")
	check(Catalog.quest_steps.size() == 5, "and the editor picks up the new step")

	var probe := QuestDoc.new()
	probe.data = reread.data.duplicate(true)
	probe.data.areas[0].opens_after = "nope"
	probe.data.endings.reverse()
	probe.data.requires = [{"flag": "", "is": true}]
	var found := "\n".join(probe.problems())
	check(found.contains("opens after step \"nope\"") and found.contains("can never be reached") and found.contains("names no story flag"),
		"the quest check catches a bad unlock, an unreachable ending and a blank requirement")

	# --- Its own level ---------------------------------------------------------------------------
	app.open_path(dir.path_join("levels/survey_site"))
	await settle()
	doc = app.doc
	check(doc.quest != null and not doc.is_nomad2(), "a quest level knows its quest")
	var escorts: Array = Wiring.candidates("escort", doc).map(func(c): return c[0])
	check(escorts.has("lapis") and escorts.has("foreman"), "its triggers can name the quest's people from Nomad-2 (escorts)")
	problems = LevelCheck.run(doc)
	check(LevelCheck.errors(problems).is_empty(), "the example's survey site has nothing to fix (%s)" % texts(LevelCheck.errors(problems)))

	# --- A new quest -----------------------------------------------------------------------------
	var fresh := lib.path_join("quests/new_one")
	check(QuestDialogs.create_quest(fresh, "New One", "Me") == "", "a new quest is made")
	var q := QuestDoc.open(fresh)
	check(q != null and q.data.client == "Me" and LevelData.load_dir(q.nomad2_dir()).meta.kind == "nomad2", "with quest.json and an empty Nomad-2")
	check(q.problems().size() == 1 and q.problems()[0].contains("goes nowhere"), "it needs somewhere to go")
	var made := QuestDialogs.create_quest_level(q, "Old Mine")
	check(made.ends_with("levels/old_mine") and LevelData.is_level_dir(made), "New level for this quest makes one in its folder")
	check(q.data.areas.size() == 1 and q.data.areas[0].quest_level == "old_mine" and q.problems().is_empty(), "and adds it to where the teleporter goes")
	app.open_path(made)
	await settle()
	check(LevelCheck.errors(LevelCheck.run(app.doc)).is_empty(), "the new level starts with nothing to fix (%s)" % texts(LevelCheck.errors(LevelCheck.run(app.doc))))
	var plain := EditorDoc.create("Loose", "", lib.path_join("loose"))
	plain.level.interaction.rules = [{"id": "r", "when": {"event": "level_started"}, "do": [{"action": "complete_step", "target": "x"}]}]
	check(texts(LevelCheck.run(plain)).contains("isn't part of a quest"), "a quest action in a loose level is caught")

	# --- Export --------------------------------------------------------------------------------
	check(QuestDialogs.check_quest(QuestDoc.open(dir)) == "", "the example quest passes its check (%s)" % QuestDialogs.check_quest(QuestDoc.open(dir)))
	var out := "/tmp/quest_test_export/foremans_favour"
	rm("/tmp/quest_test_export")
	check(QuestDialogs.export_quest(QuestDoc.open(dir), out) == "", "it exports")
	check(FileAccess.file_exists(out.path_join("quest.json")) and LevelData.is_level_dir(out.path_join("nomad2"))
		and LevelData.is_level_dir(out.path_join("levels/survey_site")), "quest.json, its Nomad-2 and its levels")
	var exported := LevelData.load_dir(out.path_join("nomad2"))
	check(exported.interaction.objects.any(func(o): return String(o.get("name", "")) == "Rina Heimar"), "with what was added in the editor")
	check(QuestDialogs.check_quest(QuestDoc.open(fresh)).contains("Old Mine") == false, "a fresh quest's level is fine")

	print("FAILS: ", fails)
	quit(fails)
