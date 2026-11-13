class_name Palette
extends VBoxContainer
## The left-hand panel: the things you can place on the current layer.
## Click one, then click in the view.

var app: Node
var _search: LineEdit
var _list: VBoxContainer
var _wave_row: HBoxContainer
var _wave: SpinBox
var _buttons: Array[Button] = []


func _init() -> void:
	custom_minimum_size.x = 230
	var title := Label.new()
	title.text = "Place"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search..."
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: refresh())
	add_child(_search)
	_wave_row = HBoxContainer.new()
	var wave_label := Label.new()
	wave_label.text = "Into wave"
	wave_label.tooltip_text = "Enemies you place inside a room join this wave of that room. A number past the room's last wave adds a new wave."
	wave_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_wave_row.add_child(wave_label)
	_wave = SpinBox.new()
	_wave.min_value = 1
	_wave.max_value = 30
	_wave.value = 1
	_wave.tooltip_text = wave_label.tooltip_text
	_wave.value_changed.connect(func(v: float) -> void: app.place_wave = int(v))
	_wave_row.add_child(_wave)
	add_child(_wave_row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	add_child(scroll)


func set_wave(n: int) -> void:
	_wave.set_value_no_signal(n)


func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_buttons.clear()
	if app.doc == null:
		return
	var layer: int = app.layer
	_wave_row.visible = layer == 3
	var filter := _search.text.strip_edges().to_lower()
	var group := ""
	for entry in Catalog.palette(layer, app.doc):
		if filter != "" and not String(entry.title).to_lower().contains(filter):
			continue
		if entry.group != group:
			group = entry.group
			var head := Label.new()
			head.text = group
			head.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
			_list.add_child(head)
		var b := Button.new()
		b.text = entry.title
		b.tooltip_text = entry.tip
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.pressed.connect(func() -> void:
			for other in _buttons:
				other.set_pressed_no_signal(other == b)
			app.begin_place(entry))
		_list.add_child(b)
		_buttons.append(b)
	if layer == 1:
		var add := Button.new()
		add.text = "Import a model..."
		add.tooltip_text = "Bring in a .glb or .gltf model (from an asset pack, or your own) to build with."
		add.pressed.connect(func() -> void: app.dialogs.import_model())
		_list.add_child(add)
		var start := Button.new()
		start.text = "Select the start point"
		start.tooltip_text = "Where Seekers arrive. Drag it to move it."
		start.pressed.connect(func() -> void:
			app.doc.select(EditorDoc.START)
			app.view.focus(EditorDoc.START))
		_list.add_child(start)


## Un-presses every button (placing stopped).
func clear_pressed() -> void:
	for b in _buttons:
		b.set_pressed_no_signal(false)
