class_name Wiring
extends RefCounted
## Triggers in plain words. A trigger (a "rule" in interaction.json) reads
## "When <event>, [if <conditions>,] <actions>". This file knows which
## things each event can come from, which things each action can target,
## and how to say a trigger as a sentence.

## [event, menu text, kinds of source]. "zone" covers both zone events.
const EVENTS := [
	["level_started", "The level starts", ""],
	["entered", "Seekers walk into a zone", "trigger_zone"],
	["pressed", "A button or plate group is pressed", "button"],
	["combat_started", "A room's fight starts", "combat"],
	["wave_cleared", "A wave is beaten", "combat"],
	["combat_ended", "A room's fight is won", "combat"],
	["enemy_defeated", "An enemy is defeated", "enemy"],
	["health_below", "An enemy's HP drops below a percent", "enemy"],
	["dialogue_ended", "A dialogue ends", "dialogue"],
	["box_broken", "A supply box is broken", "box"],
	["node_broken", "A Lumidium crystal is broken", "lumidium_node"],
	["timer_done", "A timer runs out", "timer"],
	["flag_set", "A flag is set", "flag"],
	["talked", "Someone is talked to", "person"],
	["step_completed", "A quest step is done", "step"],
]

## [action, menu text, object types it can target ("" = no target)].
const ACTIONS := [
	["open", "Open a door", "door"],
	["close", "Close a door", "door"],
	["toggle", "Switch (open/closed, on/off)", "door,hazard,platform,bridge,teleporter,trigger_zone"],
	["start_combat", "Start a room's fight", "combat"],
	["disable", "Turn off (hazard, trap, zone, platform, teleporter)", "hazard,trap,trigger_zone,platform,teleporter"],
	["enable", "Turn on (hazard, zone, platform)", "hazard,trigger_zone,platform"],
	["extend", "Extend a bridge", "bridge"],
	["retract", "Retract a bridge", "bridge"],
	["start", "Start a platform moving", "platform"],
	["stop", "Stop a platform, or someone walking", "platform,person"],
	["step", "Move a platform one stop", "platform"],
	["wake", "Wake a teleporter", "teleporter"],
	["start_dialogue", "Start a dialogue", "dialogue"],
	["banner", "Show a banner", ""],
	["wait", "Wait", ""],
	["set_flag", "Set a flag", ""],
	["start_timer", "Start a timer", ""],
	["give_item", "Give each Seeker an item", ""],
	["complete_objective", "Complete a quest objective (old quests)", ""],
	["complete_step", "Complete a quest step", "step"],
	["set_quest_flag", "Set a quest flag (lasts the whole quest)", ""],
	["set_story_flag", "Set a story flag (kept after the quest)", ""],
	["take_item", "Take an item from the Seeker who talked", ""],
	["show", "Bring someone in", "person"],
	["hide", "Send someone away", "person"],
	["walk", "Have someone walk their route", "person"],
	["set_talk", "Change what someone says", "person"],
	["escort", "Have someone follow the party (escort)", "person"],
	["stop_escort", "Stop an escort", "escort"],
]

const ITEMS := [["oro", "Oro"], ["hp_gel", "HP Gel"], ["lp_cell", "LP Cell"], ["cure_salt", "Cure Salt"],
	["trap_scanner", "Trap Scanner"], ["lumidium", "Lumidium (carried)"]]

const VERBS := {"open": "open", "close": "close", "toggle": "switch", "start_combat": "start the fight in",
	"disable": "turn off", "enable": "turn on", "extend": "extend", "retract": "retract", "start": "start",
	"stop": "stop", "step": "move", "wake": "wake", "start_dialogue": "start", "show": "bring in",
	"hide": "send away", "stop_escort": "stop escorting"}


static func event_row(event: String) -> Array:
	if event == "party_present":
		event = "entered"
	for row in EVENTS:
		if row[0] == event:
			return row
	return [event, event, ""]


static func action_row(action: String) -> Array:
	for row in ACTIONS:
		if row[0] == action:
			return row
	return [action, action, ""]


## Ids (with labels) an event can come from or an action can target:
## [[id, label]...]. `kinds` is the third column of EVENTS / ACTIONS.
static func candidates(kinds: String, doc: EditorDoc) -> Array:
	var out := []
	for kind in kinds.split(",", false):
		match kind:
			"combat":
				for c in doc.level.combat.rooms:
					out.append([String(c.room), doc.label_of(String(c.room))])
			"enemy":
				for p in doc.level.placements():
					out.append([String(p.id), doc.label_of(String(p.id))])
			"dialogue":
				for d in doc.level.interaction.dialogues:
					out.append([String(d.id), doc.label_of(String(d.id))])
			"button":
				var seen := {}
				for o in doc.level.interaction.objects:
					if String(o.get("type", "")) != "button":
						continue
					var source := doc.press_source(String(o.id))
					if not seen.has(source):
						seen[source] = true
						var g := doc.group_of(String(o.id))
						out.append([source, doc.label_of(source) if g.is_empty()
							else "%s: %d together" % [doc.label_of(source), (g.buttons as Array).size()]])
			"timer":
				for rule in doc.level.interaction.rules:
					for a in rule.get("do", []):
						if String(a.get("action", "")) == "start_timer" and String(a.get("id", "")) != "":
							out.append([String(a.id), "Timer \"%s\"" % a.id])
			"flag":
				for flag in doc.level.interaction.flags:
					out.append([String(flag), "Flag \"%s\"" % flag])
			"step":
				if doc.quest:
					for st in doc.quest.step_options():
						out.append([st[0], "Step " + String(st[1])])
			"escort":
				# People here, and the quest's people on Nomad-2 (escorts
				# come along to its levels).
				var seen := {}
				for o in doc.level.interaction.objects:
					if String(o.get("type", "")) == "person":
						seen[String(o.id)] = true
						out.append([String(o.id), doc.label_of(String(o.id))])
				if doc.quest and not doc.is_nomad2():
					for o in doc.quest.nomad2_people():
						if not seen.has(String(o.get("id", ""))):
							out.append([String(o.id), "%s (%s, from Nomad-2)" % [String(o.get("name", o.id)), o.id]])
			_:
				for o in doc.level.interaction.objects:
					if String(o.get("type", "")) == kind:
						out.append([String(o.id), doc.label_of(String(o.id))])
	return out


## The events that make sense coming from one item (for "Add a trigger").
static func events_for(kind: String, d: Dictionary, doc: EditorDoc) -> PackedStringArray:
	var out := PackedStringArray()
	var mine := ""
	if kind == "enemy":
		mine = "enemy"
	elif kind == "area":
		mine = "combat" if not doc.level.combat_room(String(d.get("id", ""))).is_empty() else ""
	elif kind == "object":
		mine = String(d.get("type", ""))
	for row in EVENTS:
		if mine != "" and row[2] == mine:
			out.append(row[0])
	return out


## "When Button (gate_button) is pressed: open Door (gate)."
static func describe(rule: Dictionary, doc: EditorDoc) -> String:
	var when: Dictionary = rule.get("when", {})
	var text := "When " + _when_text(when, doc)
	var checks := PackedStringArray()
	for c in rule.get("if", []):
		checks.append(_check_text(c))
	if not checks.is_empty():
		text += ", if " + " and ".join(checks)
	var acts := PackedStringArray()
	for a in rule.get("do", []):
		acts.append(_action_text(a, doc))
	text += ": " + (", then ".join(acts) if not acts.is_empty() else "(nothing yet)") + "."
	if not bool(rule.get("once", true)):
		text += " (every time)"
	return text


static func _when_text(when: Dictionary, doc: EditorDoc) -> String:
	var source := String(when.get("source", ""))
	var who := doc.label_of(source) if source != "" else "?"
	match String(when.get("event", "")):
		"level_started":
			return "the level starts"
		"entered":
			return "a Seeker walks into %s" % who
		"party_present":
			return "the whole party is inside %s" % who
		"pressed":
			return "%s is pressed" % who
		"combat_started":
			return "the fight in %s starts" % who
		"wave_cleared":
			return ("wave %d of %s is beaten" % [int(when.value), who]) if when.has("value") else "any wave of %s is beaten" % who
		"combat_ended":
			return "the fight in %s is won" % who
		"enemy_defeated":
			return "%s is defeated" % who
		"health_below":
			return "%s drops to %d%% HP" % [who, int(when.get("value", 50))]
		"dialogue_ended":
			return ("%s ends with \"%s\"" % [who, when.value]) if when.has("value") else "%s ends" % who
		"box_broken", "node_broken":
			return "%s is broken" % who
		"timer_done":
			return "timer \"%s\" runs out" % source
		"flag_set":
			return "flag \"%s\" is set" % source
		"talked":
			return "a Seeker talks to %s" % who
		"step_completed":
			return "quest step %s is done" % _step_name(source, doc)
	return "?"


static func _step_name(id: String, doc: EditorDoc) -> String:
	if doc and doc.quest:
		for st in doc.quest.step_options():
			if st[0] == id:
				return "\"%s\"" % st[1]
	return "\"%s\"" % id


static func _check_text(c: Dictionary) -> String:
	match String(c.get("check", "")):
		"flag":
			return "flag \"%s\" is %s" % [c.get("flag", "?"), "on" if c.get("is", true) else "off"]
		"difficulty_at_least":
			return "difficulty is %s or higher" % String(c.get("value", "normal")).replace("_", " ")
		"party_at_least":
			return "there are %d or more Seekers" % int(c.get("value", 1))
		"quest_active":
			return "quest \"%s\" is active" % c.get("value", "?")
		"quest_step":
			var state: String = {"current": "is the current step", "not_done": "isn't done yet"}.get(String(c.get("is", "done")), "is done")
			return "quest step \"%s\" %s" % [c.get("step", "?"), state]
		"quest_flag":
			return "quest flag \"%s\" is %s" % [c.get("flag", "?"), "on" if c.get("is", true) else "off"]
		"story_flag":
			return "story flag \"%s\" is %s" % [c.get("flag", "?"), "on" if c.get("is", true) else "off"]
		"has_item":
			return "the Seeker %s %d %s" % ["has" if c.get("is", true) else "doesn't have", int(c.get("amount", 1)), _item_name(c)]
		"escort_near":
			return "%s is %swithin %s m" % [c.get("target", "?"), "" if c.get("is", true) else "not ", str(c.get("distance", 8))]
	return "?"


static func _item_name(d: Dictionary) -> String:
	var item := String(d.get("item", "oro"))
	if item == "lumidium":
		return "%s Lumidium" % String(d.get("color", "raw")).capitalize()
	for row in ITEMS:
		if row[0] == item:
			return row[1]
	return item.replace("_", " ")


static func _action_text(a: Dictionary, doc: EditorDoc) -> String:
	var action := String(a.get("action", ""))
	match action:
		"banner":
			return "show \"%s\"" % a.get("text", "")
		"wait":
			return "wait %s s" % str(a.get("seconds", 1))
		"set_flag":
			return "set flag \"%s\" %s" % [a.get("flag", "?"), "on" if a.get("value", true) else "off"]
		"start_timer":
			return "start timer \"%s\" (%s s)" % [a.get("id", "?"), str(a.get("seconds", 1))]
		"give_item":
			return "give %d %s" % [int(a.get("amount", 1)), String(a.get("item", "?")).replace("_", " ")]
		"complete_objective":
			return "complete quest objective \"%s\"" % a.get("key", "?")
		"complete_step":
			return "complete quest step %s" % _step_name(String(a.get("target", a.get("step", ""))), doc)
		"set_quest_flag":
			return "set quest flag \"%s\" %s" % [a.get("flag", "?"), "on" if a.get("value", true) else "off"]
		"set_story_flag":
			return "set story flag \"%s\" %s" % [a.get("flag", "?"), "on" if a.get("value", true) else "off"]
		"take_item":
			return "take %d %s" % [int(a.get("amount", 1)), _item_name(a)]
		"walk", "escort":
			var who := String(a.get("target", ""))
			return ("have %s walk their route" if action == "walk" else "have %s follow the party") % (doc.label_of(who) if who != "" else "?")
		"set_talk":
			var target_id := String(a.get("target", ""))
			return "have %s say %s" % [doc.label_of(target_id) if target_id != "" else "?", doc.label_of(String(a.get("dialogue", "")))]
	var target := String(a.get("target", ""))
	var text := "%s %s" % [VERBS.get(action, action), doc.label_of(target) if target != "" else "?"]
	if action == "step":
		text += " one stop"
	return text
