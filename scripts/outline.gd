class_name Outline
extends Tree
## A list of everything on the current layer, grouped by type. Click to
## select; double-click to jump to it.

var app: Node
var _filling := false


func _init() -> void:
	hide_root = true
	custom_minimum_size.y = 200
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_selected.connect(func() -> void:
		if not _filling and get_selected() and get_selected().get_metadata(0) != null:
			app.doc.select(String(get_selected().get_metadata(0))))
	item_activated.connect(func() -> void:
		if get_selected() and get_selected().get_metadata(0) != null:
			app.view.focus(String(get_selected().get_metadata(0))))


func refresh() -> void:
	_filling = true
	clear()
	var doc: EditorDoc = app.doc
	if doc == null:
		_filling = false
		return
	var root := create_item()
	var groups := {}
	var bad := {}
	for p in app.problems:
		if p.level == "error" or not bad.has(p.id):
			bad[p.id] = p.level
	for it in doc.items():
		if EditorDoc.KIND_LAYER[it.kind] != app.layer:
			continue
		var group: String = Catalog.type_name(it.kind, it.data) if it.kind in ["object", "room", "enemy"] else {
			"start": "Start", "piece": "Solid shapes", "wall": "Invisible walls", "decoration": "Decorations"}.get(it.kind, it.kind)
		if not groups.has(group):
			var head := create_item(root)
			head.set_text(0, group)
			head.set_selectable(0, false)
			head.set_custom_color(0, Color(0.65, 0.85, 1.0))
			groups[group] = head
		var row := create_item(groups[group])
		row.set_text(0, Catalog.label(it.kind, it.data, it.id))
		row.set_metadata(0, it.id)
		if bad.has(it.id):
			row.set_custom_color(0, Color(1.0, 0.55, 0.5) if bad[it.id] == "error" else Color(1.0, 0.85, 0.45))
			row.set_tooltip_text(0, "Has a problem: see the Problems tab.")
		if it.id == doc.selected:
			row.select(0)
			scroll_to_item.call_deferred(row)
	for group in groups:
		var head: TreeItem = groups[group]
		head.set_text(0, "%s (%d)" % [group, head.get_child_count()])
	_filling = false
