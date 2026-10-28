extends Control
## Standalone shop tools with in-app manufacturer references.
## No equipment registration, AI service, database writes, or purchases are required.

const AMBER := Color("ffb347")
const MUTED := Color("a6b3c4")
var pages: Dictionary = {}
var navigation: Dictionary = {}
var page_title: Label
var page_hint: Label
var tile_grid: GridContainer
var active_page := "home"
var work_form: Dictionary = {}
var research_kind := "parts"
var section_outputs: Dictionary = {}
var research_buttons: Dictionary = {}
var research_panel: VBoxContainer
var photos_panel: VBoxContainer
var part_quantity: SpinBox
var header_brand: VBoxContainer
var brand_title: Label
var brand_tagline: Label
var order_summary: Label
const RESEARCH_MODES := {"parts":"Parts", "diagnose":"Troubleshoot", "repair":"Repair", "fabricate":"Fabricate"}
var parts: Array[String] = []
var parts_view: ItemList
var parts_message: Label
var equipment_workspace: Control
var conversion_input: LineEdit
var conversion_kind: OptionButton
var conversion_result: Label
var mix_fuel: LineEdit
var mix_ratio: LineEdit
var mix_result: Label
var reference_desk: VBoxContainer
var page_scroll: ScrollContainer
var job_workspace: VBoxContainer
var tool_mount: VBoxContainer
var active_tool := "references"
var syncing_job := false
var nav_grid: GridContainer
var order_heading: Label
var save_heading: Label
var screen_positions: Dictionary = {}
var machine_input: LineEdit
var machine_timer: Timer
var current_order := ""
var order_views: Dictionary = {}
var tool_states: Dictionary = {}
var tool_buttons: HFlowContainer
var photo_workspace: VBoxContainer
var outer_margin: MarginContainer
const TOOL_CHOICES := [["saved", "Work area"], ["references", "Manuals & diagrams"], ["parts_list", "Parts list"], ["calculators", "Calculators"], ["equipment", "Equipment records"]]

func text(value: String, size: int = 16, color: Color = Color("edf2f7")) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

func style(background: Color, border: Color = Color("34404c")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	return box

func action(caption: String, callback: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = caption
	node.custom_minimum_size.y = 44
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(callback)
	if primary:
		node.add_theme_stylebox_override("normal", style(Color("593d1e"), AMBER))
		node.add_theme_color_override("font_color", Color("ffdb9e"))
	return node

func card(parent: Node) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", style(Color("18212b")))
	parent.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	frame.add_child(box)
	return box

func field(parent: Node, caption: String, placeholder: String) -> LineEdit:
	parent.add_child(text(caption, 14, MUTED))
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.max_length = 300
	node.custom_minimum_size.y = 46
	parent.add_child(node)
	return node

func make_page(key: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages[key] = page
	return page

func install_theme() -> void:
	var shop_theme := Theme.new()
	shop_theme.default_font_size = 16
	for type in ["Button", "LineEdit", "OptionButton", "TextEdit", "ItemList"]:
		shop_theme.set_stylebox("normal", type, style(Color("202c38")))
		shop_theme.set_stylebox("focus", type, style(Color("26374a"), Color("67baff")))
		shop_theme.set_color("font_color", type, Color("edf2f7"))
	shop_theme.set_stylebox("hover", "Button", style(Color("304254"), Color("67baff")))
	shop_theme.set_stylebox("pressed", "Button", style(Color("513a20"), AMBER))
	shop_theme.set_stylebox("disabled", "Button", style(Color("1b222b")))
	shop_theme.set_color("font_disabled_color", "Button", Color("8d9aab"))
	theme = shop_theme

func _ready() -> void:
	install_theme()
	var backdrop := ColorRect.new()
	backdrop.color = Color("10161e")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var margin := MarginContainer.new()
	outer_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	layout.add_child(header)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/gophertech-logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(52, 60)
	header.add_child(logo)
	header_brand = VBoxContainer.new()
	header_brand.custom_minimum_size.x = 240
	header.add_child(header_brand)
	brand_title = text("GopherTech", 22, AMBER)
	header_brand.add_child(brand_title)
	brand_tagline = text("Figure it out. Figure it right. Get it fixed.", 12, MUTED)
	header_brand.add_child(brand_tagline)
	var order_identity := VBoxContainer.new()
	order_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(order_identity)
	order_heading = text("Quick search", 18, AMBER)
	order_heading.max_lines_visible = 1
	order_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	order_identity.add_child(order_heading)
	order_summary = text("No work order selected", 14, MUTED)
	order_summary.max_lines_visible = 2
	order_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	order_identity.add_child(order_summary)
	navigation = {"home":"Go For Gopher", "saved":"Work Area", "parts_list":"Parts", "tools":"Tools"}
	save_heading = text("", 12, MUTED)
	save_heading.max_lines_visible = 2
	layout.add_child(save_heading)
	nav_grid = GridContainer.new()
	nav_grid.columns = 4
	nav_grid.add_theme_constant_override("h_separation", 8)
	nav_grid.add_theme_constant_override("v_separation", 8)
	layout.add_child(nav_grid)
	for key in navigation:
		var destination: String = key
		var button := action(navigation[key], func(): show_page(destination))
		button.icon = load("res://assets/gophertech-logo.png")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 20)
		button.add_theme_font_size_override("font_size", 14)
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.set_meta("destination", key)
		nav_grid.add_child(button)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 8)
	layout.add_child(main)
	page_title = text("", 23)
	main.add_child(page_title)
	page_hint = text("", 15, MUTED)
	main.add_child(page_hint)
	var scroll := ScrollContainer.new()
	page_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)
	build_home()
	make_page("saved")
	var tools := make_page("tools")
	tool_buttons = HFlowContainer.new()
	tool_buttons.add_theme_constant_override("h_separation", 8)
	tool_buttons.add_theme_constant_override("v_separation", 8)
	tools.add_child(tool_buttons)
	for choice in TOOL_CHOICES:
		var destination: String = choice[0]
		if destination == "parts_list": continue
		tool_buttons.add_child(action(choice[1], func(): show_page(destination)))
	tool_mount = VBoxContainer.new()
	tools.add_child(tool_mount)
	build_parts_list()
	build_calculators()
	var references := make_page("references")
	reference_desk = load("res://reference_desk.gd").new()
	reference_desk.focus_requested.connect(func(control: Control): page_scroll.call_deferred("ensure_control_visible", control))
	references.add_child(reference_desk)
	var equipment_page := make_page("equipment")
	equipment_workspace = load("res://equipment_dashboard.tscn").instantiate()
	equipment_workspace.embedded = true
	equipment_workspace.custom_minimum_size.y = 840
	equipment_page.add_child(equipment_workspace)
	for choice in TOOL_CHOICES:
		if choice[0] == "saved": continue
		pages[choice[0]].visible = false
		tool_mount.add_child(pages[choice[0]])
	var notes_page: VBoxContainer = pages["saved"]
	notes_page.add_theme_constant_override("separation", 8)
	machine_input = field(notes_page, "Machine details (optional)", "Year, make, model, serial — enter what you know")
	machine_timer = Timer.new()
	machine_timer.one_shot = true
	machine_timer.wait_time = 0.8
	machine_timer.timeout.connect(func(): job_workspace.save_state({"machine_description": machine_input.text}))
	add_child(machine_timer)
	machine_input.text_changed.connect(func(_value: String):
		if not syncing_job:
			machine_timer.start()
			update_order_heading()
	)
	build_research(notes_page)
	photos_panel = card(notes_page)
	photos_panel.get_parent().visible = false
	photos_panel.add_child(text("Work order photos", 21))
	photo_workspace = load("res://work_order_photos.gd").new()
	photos_panel.add_child(photo_workspace)
	for key in ["home", "saved", "tools"]:
		pages[key].visible = false
		stack.add_child(pages[key])
	job_workspace.saved_view.reparent(pages["saved"])
	job_workspace.saved_view.visible = true
	notes_page.move_child(job_workspace.saved_view, 0)
	job_workspace.sections_enabled = true
	job_workspace.notes.reparent(research_panel)
	job_workspace.notes.custom_minimum_size.y = 110
	job_workspace.notes.placeholder_text = "Measurements, symptoms, checks, repair and fabrication notes — saved automatically"
	# The notes editor is shared by every research action; no duplicate pads.
	research_panel.move_child(job_workspace.notes, work_form["actions"].get_index())
	reference_desk.question_notes = job_workspace.notes
	var retry_save := action("Retry save", func():
		machine_timer.stop()
		job_workspace.notes_timer.stop()
		job_workspace.save_state({"machine_description":machine_input.text}.merged(job_workspace.collect_notes()))
	)
	retry_save.visible = false
	work_form["actions"].add_child(retry_save)
	job_workspace.set_meta("machine_input", machine_input)
	job_workspace.before_switch.connect(func():
		if not machine_timer.is_stopped():
			machine_timer.stop()
			job_workspace.save_state({"machine_description": machine_input.text})
	)
	job_workspace.status_changed.connect(func(value: String):
		save_heading.text = value
		retry_save.visible = not job_workspace.busy and not job_workspace.pending_state.is_empty()
	)
	job_workspace.job_loaded.connect(on_job_loaded)
	job_workspace.ask_button.add_theme_stylebox_override("normal", style(Color("593d1e"), AMBER))
	job_workspace.answer_ready.connect(scroll_to_answer)
	job_workspace.reference_ready.connect(scroll_to_reference)
	job_workspace.save_notice.connect(func(value: String): parts_message.text = value)
	reference_desk.document_loaded.connect(func(url: String): job_workspace.open_reference(url))
	resized.connect(adapt_layout)
	adapt_layout()
	set_research_kind("parts")
	show_page("home")

func adapt_layout() -> void:
	if outer_margin != null:
		for side in ["left", "right", "top", "bottom"]:
			outer_margin.add_theme_constant_override("margin_" + side, 14 if size.x < 600 else 22)
	if page_title != null: page_title.add_theme_font_size_override("font_size", 21 if size.x < 600 else 23)
	if header_brand != null: header_brand.custom_minimum_size.x = 120 if size.x < 600 else 240
	if brand_title != null: brand_title.add_theme_font_size_override("font_size", 18 if size.x < 600 else 22)
	if brand_tagline != null: brand_tagline.visible = size.x >= 600
	if nav_grid != null: nav_grid.columns = 2 if size.x < 600 else 4
	if tile_grid != null:
		tile_grid.columns = 1 if size.x < 960 else 2

func show_page(key: String, refresh: bool = true, remember_position: bool = true) -> void:
	if RESEARCH_MODES.has(key):
		set_research_kind(key)
		key = "saved"
	elif key in ["notes", "photos"]:
		if key == "photos": set_research_kind("photos")
		elif research_kind == "photos": set_research_kind("parts")
		key = "saved"
	if not pages.has(key): return
	if key != "home" and job_workspace.voice_input.active: job_workspace.voice_input.cancel()
	var previous := active_tool if active_page == "tools" else active_page
	if remember_position: screen_positions[previous] = page_scroll.scroll_vertical
	var selected_tool := key in ["references", "calculators", "equipment"]
	if selected_tool: active_tool = key
	active_page = "tools" if selected_tool else key
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	for name in ["home", "saved", "tools"]: pages[name].visible = name == active_page
	for choice in TOOL_CHOICES:
		if choice[0] == "saved": continue
		pages[choice[0]].visible = choice[0] == ("parts_list" if active_page == "parts_list" else active_tool) and active_page in ["tools", "parts_list"]
	tool_buttons.visible = active_page == "tools"
	if active_page == "parts_list": pages["tools"].visible = true
	for child in nav_grid.get_children(): child.set_pressed_no_signal(child.get_meta("destination") == active_page)
	page_title.text = navigation.get(active_page, "Tools")
	page_hint.visible = false
	var position_key := active_tool if active_page == "tools" else active_page
	page_scroll.set_deferred("scroll_vertical", screen_positions.get(position_key, 0))
	if active_page == "saved" and refresh: job_workspace.refresh_jobs()

func build_home() -> void:
	var home := make_page("home")
	job_workspace = load("res://job_workspace.gd").new()
	home.add_child(job_workspace)

func on_job_loaded(value: Dictionary) -> void:
	var incoming: String = value.get("id", "")
	var changing_order: bool = incoming != current_order
	photo_workspace.bind_job(incoming)
	if changing_order:
		var adopt_initial: bool = current_order.is_empty() and not incoming.is_empty() and job_workspace.operation in ["question", "create"] and job_workspace.creation_body.is_empty()
		if RESEARCH_MODES.has(research_kind): section_outputs[research_kind] = work_form["output"].text
		var form_state := {"kind":research_kind, "outputs":section_outputs.duplicate(), "quantity":part_quantity.value}
		form_state["_reference"] = reference_desk.capture_workspace()
		tool_states[current_order] = form_state
		screen_positions[active_tool if active_page == "tools" else active_page] = page_scroll.scroll_vertical
		order_views[current_order] = screen_positions.duplicate()
		screen_positions = order_views.get(incoming, {}).duplicate()
		current_order = incoming
		var restored: Dictionary = form_state if adopt_initial else tool_states.get(incoming, {})
		if not adopt_initial: reference_desk.restore_workspace(restored.get("_reference", {}))
		work_form["message"].text = ""
		section_outputs = restored.get("outputs", {}).duplicate()
		part_quantity.value = restored.get("quantity", 1)
		set_research_kind(restored.get("kind", "parts"), true)
	else:
		set_research_kind(research_kind, true)
	syncing_job = true
	if incoming != "" and current_order == incoming and machine_timer.is_stopped(): machine_input.text = value.get("machine_description", "")
	elif incoming.is_empty(): machine_input.text = ""
	if job_workspace.pending_state.has("machine_description"): machine_input.text = job_workspace.pending_state["machine_description"]
	update_order_heading()
	parts.clear()
	for entry in value.get("parts", []): parts.append(str(entry))
	render_parts()
	syncing_job = false
	if not value.is_empty() and (job_workspace.operation == "open" or (job_workspace.operation == "create" and not job_workspace.creation_body.is_empty())):
		show_page("saved", false, not changing_order)

func update_order_heading() -> void:
	var value: Dictionary = job_workspace.job
	order_heading.text = job_workspace.order_label(value) if not value.is_empty() else "Quick search"
	var description := machine_input.text.strip_edges()
	order_summary.text = description if not description.is_empty() else "Machine details not entered" if not value.is_empty() else "No work order selected"
	order_heading.tooltip_text = order_heading.text
	order_summary.tooltip_text = order_summary.text

func build_research(page: VBoxContainer) -> void:
	var modes := HFlowContainer.new()
	modes.add_theme_constant_override("h_separation", 6)
	page.add_child(modes)
	var choices := RESEARCH_MODES.duplicate()
	choices["photos"] = "Photos"
	for key in choices:
		var mode: String = key
		var button := action(choices[key], func(): set_research_kind(mode))
		button.toggle_mode = true
		modes.add_child(button)
		research_buttons[key] = button
	research_panel = card(page)
	research_panel.add_theme_constant_override("separation", 8)
	work_form["panel_title"] = text("", 21, AMBER)
	research_panel.add_child(work_form["panel_title"])
	work_form["hint"] = text("", 14, MUTED)
	research_panel.add_child(work_form["hint"])
	work_form["task_label"] = text("", 14, MUTED)
	research_panel.add_child(work_form["task_label"])
	var task := LineEdit.new()
	task.max_length = 300
	task.custom_minimum_size.y = 44
	research_panel.add_child(task)
	work_form["task"] = task
	task.text_changed.connect(func(value: String): job_workspace.set_section_task(value))
	work_form["notes_label"] = text("", 14, MUTED)
	research_panel.add_child(work_form["notes_label"])
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	research_panel.add_child(actions)
	work_form["actions"] = actions
	work_form["find_button"] = action("", func(): open_research(research_kind), true)
	actions.add_child(work_form["find_button"])
	work_form["brief_button"] = action("", func(): prepare_research(research_kind))
	actions.add_child(work_form["brief_button"])
	work_form["add_button"] = action("Add part to list", add_part)
	actions.add_child(work_form["add_button"])
	actions.add_child(action("Copy brief", func():
		if prepare_research(research_kind): DisplayServer.clipboard_set(work_form["output"].text)
	))
	work_form["message"] = text("", 13, MUTED)
	research_panel.add_child(work_form["message"])
	var output := TextEdit.new()
	output.editable = false
	output.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	output.custom_minimum_size.y = 150
	output.visible = false
	research_panel.add_child(output)
	work_form["output"] = output

func set_research_kind(key: String, restoring: bool = false) -> void:
	if not RESEARCH_MODES.has(key) and key != "photos": return
	var changed := research_kind != key
	if changed and not restoring and RESEARCH_MODES.has(research_kind):
		section_outputs[research_kind] = work_form["output"].text
	if key != "photos": job_workspace.switch_section(key)
	research_kind = key
	for mode in research_buttons: research_buttons[mode].set_pressed_no_signal(mode == key)
	if research_panel == null or photos_panel == null: return
	research_panel.get_parent().visible = key != "photos"
	photos_panel.get_parent().visible = key == "photos"
	if key == "photos": return
	work_form["task"].text = job_workspace.section_drafts.get(key, {}).get("task", "")
	if changed or restoring:
		work_form["output"].text = section_outputs.get(key, "")
		work_form["output"].visible = not work_form["output"].text.is_empty()
	var descriptions := {
		"parts":["Parts research", "Identify a part, find references, and add it to this order's parts list.", "Part name, number or markings", "For example: carburetor gasket or the number stamped on the old part", "Part measurements, fitment and observations", "Find parts references", "Build parts brief"],
		"diagnose":["Troubleshooting", "Record the symptom and checks already performed before choosing the next check.", "What is happening?", "For example: turns over but will not start", "Symptoms, test results and checks already done", "Find troubleshooting references", "Build diagnostic brief"],
		"repair":["Repair plan", "Find model-specific procedures and keep a record of the work performed.", "Repair to carry out", "For example: replace the water pump", "Repair steps, measurements and work performed", "Find repair references", "Build repair brief"],
		"fabricate":["Fabrication plan", "Keep dimensions, material and intended use together for this work order.", "What needs to be made?", "For example: a replacement mounting bracket", "Dimensions, units, material and fabrication notes", "Find fabrication references", "Build fabrication brief"]}
	var content: Array = descriptions[key]
	work_form["panel_title"].text = content[0]
	work_form["hint"].text = content[1]
	work_form["task_label"].text = content[2]
	work_form["task"].placeholder_text = content[3]
	work_form["notes_label"].text = content[4] + " — saved automatically"
	work_form["find_button"].text = content[5]
	work_form["brief_button"].text = content[6]
	work_form["add_button"].visible = key == "parts"
	if changed:
		work_form["message"].text = ""

func form_values(key: String) -> Dictionary:
	return {"machine":machine_input.text.strip_edges(), "task":work_form["task"].text.strip_edges(),
		"notes":job_workspace.notes.text.strip_edges(), "quantity":str(int(part_quantity.value)),
		"category":{"parts":"parts and suppliers", "diagnose":"troubleshooting service information", "repair":"service manuals", "fabricate":"fabrication material dimensions"}.get(key, "service information")}

func search_query(key: String, values: Dictionary) -> String:
	var terms := PackedStringArray()
	for name in ["machine", "task"]:
		var value: String = values.get(name, "")
		if not value.is_empty():
			terms.append(value)
	terms.append(values.get("category", "service information"))
	if key == "fabricate":
		terms.append("fabrication material dimensions")
	return " ".join(terms)

func prepare_research(key: String) -> bool:
	var form: Dictionary = work_form
	var values := form_values(key)
	if values["task"].is_empty():
		form["message"].text = "Enter a part or describe the job first. No equipment registration is needed."
		form["task"].grab_focus()
		return false
	var lines := PackedStringArray(["GOPHERTECH — SHOP RESEARCH BRIEF", "", "Task: " + values["task"], "Machine: " + (values["machine"] if not values["machine"].is_empty() else "Not supplied"), "", "Observations / dimensions:", values["notes"] if not values["notes"].is_empty() else "None supplied", "", "Research query: " + search_query(key, values)])
	if key == "parts":
		lines.append("\nQuantity requested: " + values["quantity"])
		lines.append("\nBefore ordering: confirm engine model/type, part supersession, fitment, quantity, price, shipping and return policy with the seller. No availability or compatibility has been verified.")
	elif key == "diagnose":
		lines.append("\nDetails to gather: when it began, exact starting/running behavior, noises or leaks, recent work, and any model-specific error codes. Consult the manufacturer's service information before testing.")
	elif key == "fabricate":
		lines.append("\nConfirm: measurement units, interfaces, material, tolerances, loads, temperature and intended use. Safety-critical parts need qualified design review.")
	else:
		lines.append("\nConfirm the exact model, procedure, tools and specifications in the manufacturer's service manual. No torque or repair specification has been generated.")
	form["output"].text = "\n".join(lines)
	section_outputs[key] = form["output"].text
	form["output"].visible = true
	form["message"].text = "Brief ready. Find references in app or copy it."
	return true

func open_research(key: String) -> void:
	if not prepare_research(key):
		return
	var values := form_values(key)
	show_page("references")
	reference_desk.query.text = search_query(key, values).left(600)
	reference_desk.find_sources()

func build_parts_list() -> void:
	var page := make_page("parts_list")
	var box := card(page)
	box.add_child(text("Find the part. Check the fit. Keep the details.", 22))
	box.add_child(text("Parts for this work order. Find another part using the shared job details.", 15, MUTED))
	part_quantity = SpinBox.new()
	part_quantity.min_value = 1
	part_quantity.max_value = 999
	part_quantity.value = 1
	part_quantity.custom_minimum_size.y = 44
	box.add_child(text("Quantity for the next part", 14, MUTED))
	box.add_child(part_quantity)
	parts_view = ItemList.new()
	parts_view.custom_minimum_size.y = 240
	box.add_child(parts_view)
	parts_message = text("Your list is empty. Start with Find a part.", 15, MUTED)
	box.add_child(parts_message)
	box.add_child(action("Find another part", func(): show_page("parts"), true))
	box.add_child(action("Copy supplier request", func():
		if parts.is_empty():
			parts_message.text = "Add a part before copying a request."
			return
		DisplayServer.clipboard_set("Please quote these parts and confirm fitment, availability, shipping and return terms:\n\n" + "\n\n".join(parts))
		parts_message.text = "Supplier request copied. No order has been placed."
	))
	box.add_child(action("Remove selected item", func():
		var selected := parts_view.get_selected_items()
		if selected.is_empty():
			parts_message.text = "Select the item you want to remove."
			return
		parts.remove_at(selected[0])
		render_parts()
		job_workspace.save_state({"parts":parts.duplicate()})
	))

func add_part() -> void:
	if not prepare_research("parts"):
		return
	var values := form_values("parts")
	var entry := "Qty %s: %s" % [values["quantity"], values["task"]]
	if not values["machine"].is_empty(): entry += " | " + values["machine"]
	if not values["notes"].is_empty():
		entry += "\n" + values["notes"]
	if parts.has(entry):
		work_form["message"].text = "This item is already in your parts list."
		return
	parts.append(entry)
	render_parts()
	job_workspace.save_state({"parts":parts.duplicate()})
	work_form["message"].text = "Added to My parts list. No order has been placed."

func render_parts() -> void:
	parts_view.clear()
	for entry in parts:
		parts_view.add_item(entry.get_slice("\n", 0))
	parts_message.text = "%d parts in the current job. Save status is shown at the top." % parts.size()

func build_calculators() -> void:
	var page := make_page("calculators")
	var units := card(page)
	units.add_child(text("Unit converter", 22))
	conversion_input = field(units, "Value", "Enter a positive number or zero")
	conversion_kind = OptionButton.new()
	conversion_kind.custom_minimum_size.y = 46
	for option in ["inches → mm", "mm → inches", "ft·lbf → N·m", "N·m → ft·lbf", "in·lbf → N·m", "US fl oz → mL"]:
		conversion_kind.add_item(option)
	units.add_child(conversion_kind)
	conversion_result = text("Choose the units printed in your service information.", 16, MUTED)
	units.add_child(conversion_result)
	units.add_child(action("Convert", convert_units, true))
	var mix := card(page)
	mix.add_child(text("Two-stroke fuel mix", 22))
	mix.add_child(text("Use only the ratio and oil specified by the engine manufacturer. This calculator measures the oil for your chosen ratio; it does not recommend a ratio or apply to four-stroke crankcase oil.", 15, MUTED))
	mix_fuel = field(mix, "Petrol / gasoline amount (litres)", "For example: 5")
	mix_ratio = field(mix, "Specified fuel-to-oil ratio (X:1) — enter X", "Enter the manufacturer's ratio")
	mix_result = text("Enter your fuel amount and specified ratio.", 16, MUTED)
	mix.add_child(mix_result)
	mix.add_child(action("Calculate oil amount", calculate_mix, true))

func convert_units() -> void:
	var raw := conversion_input.text.strip_edges()
	if not raw.is_valid_float() or not is_finite(raw.to_float()) or raw.to_float() < 0:
		conversion_result.text = "Enter a finite number that is zero or greater."
		return
	var factors := [25.4, 1.0 / 25.4, 1.3558179483314, 1.0 / 1.3558179483314, 0.11298482902762, 29.5735295625]
	var units := ["mm", "inches", "N·m", "ft·lbf", "N·m", "mL"]
	var value: float = raw.to_float() * factors[conversion_kind.selected]
	if not is_finite(value):
		conversion_result.text = "That number is too large to convert."
		return
	conversion_result.text = "Result: %.4f %s" % [value, units[conversion_kind.selected]]

func calculate_mix() -> void:
	var fuel := mix_fuel.text.strip_edges()
	var ratio := mix_ratio.text.strip_edges()
	if not fuel.is_valid_float() or not ratio.is_valid_float():
		mix_result.text = "Enter a positive fuel amount and a fuel-to-oil ratio greater than 1."
		return
	var litres := fuel.to_float()
	var denominator := ratio.to_float()
	if not is_finite(litres) or not is_finite(denominator) or litres <= 0 or denominator <= 1:
		mix_result.text = "Enter a finite positive fuel amount and a ratio greater than 1."
		return
	var oil := litres * 1000.0 / denominator
	if not is_finite(oil):
		mix_result.text = "That number is too large to calculate."
		return
	mix_result.text = "Add %.2f mL of specified oil to %s L of fuel for %s:1." % [oil, fuel, ratio]


func scroll_to_answer() -> void:
	# Wait for wrapping/container layout, then land at the start of the new answer.
	await get_tree().process_frame
	await get_tree().process_frame
	if active_page != "home": return
	var transcript: RichTextLabel = job_workspace.conversation
	var paragraph: int = mini(job_workspace.latest_answer_paragraph, transcript.get_paragraph_count() - 1)
	var offset: float = transcript.get_paragraph_offset(maxi(0, paragraph))
	var target: float = page_scroll.scroll_vertical + transcript.global_position.y - page_scroll.global_position.y + offset - 12.0
	var bar := page_scroll.get_v_scroll_bar()
	target = clampf(target, 0.0, maxf(0.0, bar.max_value - bar.page))
	var motion := create_tween()
	motion.tween_property(page_scroll, "scroll_vertical", int(target), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func scroll_to_reference(control: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if active_page != "home" or not is_instance_valid(control): return
	var bar := page_scroll.get_v_scroll_bar()
	var target := clampf(page_scroll.scroll_vertical + control.global_position.y - page_scroll.global_position.y - 12.0, 0.0, maxf(0.0, bar.max_value - bar.page))
	create_tween().tween_property(page_scroll, "scroll_vertical", int(target), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
