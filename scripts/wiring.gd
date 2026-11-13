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
	["stop", "Stop a platform", "platform"],
	["step", "Move a platform one stop", "platform"],
	["wake", "Wake a teleporter", "teleporter"],
	["start_dialogue", "Start a dialogue", "dialogue"],
	["banner", "Show a banner", ""],
	["wait", "Wait", ""],
	["set_flag", "Set a flag", ""],
	["start_timer", "Start a timer", ""],
	["give_item", "Give each Seeker an item", ""],
	["complete_objective", "Complete a quest objective", ""],
]

const VERBS := {"open": "open", "close": "close", "toggle": "switch", "start_combat": "start the fight in",
	"disable": "turn off", "enable": "turn on", "extend": "extend", "retract": "retract", "start": "start",
	"stop": "stop", "step": "move", "wake": "wake", "start_dialogue": "start"}


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
	return "?"


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
	return "?"


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
	var target := String(a.get("target", ""))
	var text := "%s %s" % [VERBS.get(action, action), doc.label_of(target) if target != "" else "?"]
	if action == "step":
		text += " one stop"
	return text
