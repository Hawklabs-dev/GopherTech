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
var research_forms: Dictionary = {}
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
var tool_picker: OptionButton
var tool_mount: VBoxContainer
var active_tool := "references"
var syncing_job := false
var menu_button: MenuButton
var outer_margin: MarginContainer
const TOOL_CHOICES := [["references", "Manuals & diagrams"], ["parts", "Parts research"], ["diagnose", "Troubleshooting brief"], ["repair", "Repair brief"], ["fabricate", "Fabrication brief"], ["parts_list", "Parts list"], ["calculators", "Calculators"], ["equipment", "Equipment records"], ["bills", "Bills to pay"], ["invoices", "Invoices to collect"]]

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
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	return box

func action(caption: String, callback: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = caption
	node.custom_minimum_size.y = 48
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
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	layout.add_child(header)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/gophertech-logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(64, 70)
	header.add_child(logo)
	var brand := VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	brand.add_child(text("GopherTech", 24, AMBER))
	brand.add_child(text("Less clicking. More fixing.", 13, MUTED))
	navigation = {"home":"Ask GopherTech", "saved":"Saved conversations", "tools":"Tools"}
	menu_button = MenuButton.new()
	menu_button.text = "Menu"
	menu_button.custom_minimum_size = Vector2(66, 44)
	header.add_child(menu_button)
	for key in navigation: menu_button.get_popup().add_item(navigation[key])
	menu_button.get_popup().id_pressed.connect(func(id: int): show_page(navigation.keys()[id]))
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 8)
	layout.add_child(main)
	page_title = text("", 30)
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
	tool_picker = OptionButton.new()
	tool_picker.custom_minimum_size.y = 50
	for choice in TOOL_CHOICES: tool_picker.add_item(choice[1])
	tool_picker.item_selected.connect(func(index: int): show_page(TOOL_CHOICES[index][0]))
	tools.add_child(tool_picker)
	tool_mount = VBoxContainer.new()
	tools.add_child(tool_mount)
	for key in ["parts", "diagnose", "repair", "fabricate"]:
		build_research(key)
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
	for key in ["bills", "invoices"]:
		var page := make_page(key)
		var finance = load("res://finance_dashboard.gd").new()
		finance.kind = "payable" if key == "bills" else "receivable"
		page.add_child(finance)
	for choice in TOOL_CHOICES:
		pages[choice[0]].visible = false
		tool_mount.add_child(pages[choice[0]])
	for key in ["home", "saved", "tools"]:
		pages[key].visible = false
		stack.add_child(pages[key])
	job_workspace.saved_view.reparent(pages["saved"])
	job_workspace.saved_view.visible = true
	job_workspace.job_loaded.connect(on_job_loaded)
	job_workspace.ask_button.add_theme_stylebox_override("normal", style(Color("593d1e"), AMBER))
	job_workspace.answer_ready.connect(func(): page_scroll.set_deferred("scroll_vertical", int(page_scroll.get_v_scroll_bar().max_value)))
	job_workspace.save_notice.connect(func(value: String): parts_message.text = value)
	reference_desk.question_notes.text_changed.connect(func():
		if not syncing_job: job_workspace.notes.text = reference_desk.question_notes.text
	)
	reference_desk.document_loaded.connect(func(url: String): job_workspace.open_reference(url))
	resized.connect(adapt_layout)
	adapt_layout()
	show_page("home")

func adapt_layout() -> void:
	if outer_margin != null:
		for side in ["left", "right", "top", "bottom"]:
			outer_margin.add_theme_constant_override("margin_" + side, 14 if size.x < 600 else 22)
	if page_title != null: page_title.add_theme_font_size_override("font_size", 25 if size.x < 600 else 30)
	if tile_grid != null:
		tile_grid.columns = 1 if size.x < 960 else 2

func show_page(key: String) -> void:
	if not pages.has(key):
		return
	if key not in ["home", "saved", "tools"]:
		active_tool = key
		for index in range(TOOL_CHOICES.size()):
			if TOOL_CHOICES[index][0] == key: tool_picker.select(index)
		key = "tools"
	active_page = key
	page_scroll.set_deferred("scroll_vertical", 0)
	for name in ["home", "saved", "tools"]: pages[name].visible = name == key
	for choice in TOOL_CHOICES: pages[choice[0]].visible = choice[0] == active_tool
	page_title.text = {"home":"What are we working on?", "saved":"Saved Jobs", "tools":"Tools"}[key]
	page_hint.text = "Ask. Find. Answer. Remember." if key == "home" else "Your saved findings and conversations." if key == "saved" else "Existing tools and records."
	if key == "saved": job_workspace.refresh_jobs()

func build_home() -> void:
	var home := make_page("home")
	job_workspace = load("res://job_workspace.gd").new()
	home.add_child(job_workspace)

func on_job_loaded(value: Dictionary) -> void:
	syncing_job = true
	parts.clear()
	for entry in value.get("parts", []): parts.append(str(entry))
	render_parts()
	reference_desk.question_notes.text = value.get("notes", "")
	syncing_job = false
	if value.is_empty() or (active_page == "saved" and job_workspace.operation == "open"):
		show_page("home")

func build_research(key: String) -> void:
	var page := make_page(key)
	var box := card(page)
	var descriptions := {"parts": "Use the engine identification plate and part number when available. Engine and machine model numbers may differ.", "diagnose": "Build a symptom brief for your research or a technician. This tool organizes your notes; it does not diagnose the engine.", "repair": "Find model-specific service information. Record the job you want to do and what you have already tried.", "fabricate": "Describe the part, material, dimensions and intended use. This brief is not an engineered design or a safety approval."}
	box.add_child(text(descriptions[key], 16, MUTED))
	var inputs: Dictionary = {}
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 14)
	box.add_child(identity)
	var brand_box := VBoxContainer.new()
	brand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(brand_box)
	var model_box := VBoxContainer.new()
	model_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(model_box)
	inputs["brand"] = field(brand_box, "Engine / machine brand (optional)", "Name on the engine plate")
	inputs["model"] = field(model_box, "Model / type / serial (optional)", "Copy the identification if known")
	var captions := {"parts": "Part name or number *", "diagnose": "What happens when you try to use it? *", "repair": "What job do you need help with? *", "fabricate": "What do you need to make? *"}
	inputs["task"] = field(box, captions[key], "Describe it in your own words")
	if key == "diagnose":
		box.add_child(text("Or start with a common symptom", 14, MUTED))
		var symptoms := HFlowContainer.new()
		box.add_child(symptoms)
		for symptom in ["Won't start", "Starts then stops", "Runs rough", "Leaks or smoke"]:
			var chosen: String = symptom
			symptoms.add_child(action(chosen, func(): inputs["task"].text = chosen))
	if key == "parts":
		box.add_child(text("Quantity for supplier request", 14, MUTED))
		var quantity := SpinBox.new()
		quantity.min_value = 1
		quantity.max_value = 999
		quantity.value = 1
		quantity.custom_minimum_size.y = 46
		box.add_child(quantity)
		inputs["quantity"] = quantity
	box.add_child(text("Details / observations (optional)", 14, MUTED))
	var notes := TextEdit.new()
	notes.placeholder_text = "Measurements and units, symptoms, things already checked, or other useful details"
	notes.custom_minimum_size.y = 95
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(notes)
	var category := OptionButton.new()
	category.custom_minimum_size.y = 46
	for title in (["Parts & suppliers", "Parts diagrams", "Service manuals"] if key == "parts" else ["Service information", "Manuals & diagrams"]):
		category.add_item(title)
	box.add_child(category)
	var message := text("Your entries stay in this session. Nothing is saved to equipment records.", 14, MUTED)
	box.add_child(message)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 10)
	box.add_child(actions)
	actions.add_child(action("Build research brief", func(): prepare_research(key), true))
	actions.add_child(action("Find references in app", func(): open_research(key)))
	var output := TextEdit.new()
	output.editable = false
	output.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	output.custom_minimum_size.y = 170
	output.placeholder_text = "Your brief will appear here."
	box.add_child(output)
	box.add_child(text("Finds manufacturer reference sources inside GopherTech. This is a curated directory, not a whole-web search. Exact model fitment and availability are unverified.", 13, MUTED))
	box.add_child(action("Copy brief", func():
		if prepare_research(key):
			DisplayServer.clipboard_set(output.text)
			message.text = "Brief copied. Ready to paste into your job notes or supplier request."
	))
	if key == "parts":
		box.add_child(action("Add to my parts list", add_part))
	research_forms[key] = {"inputs": inputs, "notes": notes, "category": category, "message": message, "output": output}

func form_values(key: String) -> Dictionary:
	var form: Dictionary = research_forms[key]
	var values := {}
	for name in form["inputs"]:
		values[name] = str(int(form["inputs"][name].value)) if name == "quantity" else form["inputs"][name].text.strip_edges()
	values["notes"] = form["notes"].text.strip_edges()
	values["category"] = form["category"].get_item_text(form["category"].selected)
	return values

func search_query(key: String, values: Dictionary) -> String:
	var terms := PackedStringArray()
	for name in ["brand", "model", "task"]:
		var value: String = values.get(name, "")
		if not value.is_empty():
			terms.append(value)
	terms.append(values.get("category", "service information"))
	if key == "fabricate":
		terms.append("fabrication material dimensions")
	return " ".join(terms)

func prepare_research(key: String) -> bool:
	var form: Dictionary = research_forms[key]
	var values := form_values(key)
	if values["task"].is_empty():
		form["message"].text = "Enter a part or describe the job first. No equipment registration is needed."
		form["inputs"]["task"].grab_focus()
		return false
	var lines := PackedStringArray(["GOPHERTECH — SHOP RESEARCH BRIEF", "", "Task: " + values["task"], "Brand: " + (values["brand"] if not values["brand"].is_empty() else "Not supplied"), "Model / type / serial: " + (values["model"] if not values["model"].is_empty() else "Not supplied"), "", "Observations / dimensions:", values["notes"] if not values["notes"].is_empty() else "None supplied", "", "Research query: " + search_query(key, values)])
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
	form["message"].text = "Brief ready. Find references in app or copy it."
	return true

func open_research(key: String) -> void:
	if not prepare_research(key):
		return
	var values := form_values(key)
	show_page("references")
	reference_desk.query.text = search_query(key, values).left(600)
	if reference_desk.question_notes.text.strip_edges().is_empty():
		reference_desk.question_notes.text = research_forms[key]["output"].text
	reference_desk.find_sources()

func build_parts_list() -> void:
	var page := make_page("parts_list")
	var box := card(page)
	box.add_child(text("Find the part. Check the fit. Keep the details.", 22))
	box.add_child(text("Add items from Find a part, then copy the list for a supplier. The list is saved with your current job when the backend is connected. No orders are placed and no stock or prices are checked.", 15, MUTED))
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
	var entry := "Qty %s: %s | %s | %s" % [values["quantity"], values["task"], values["brand"], values["model"]]
	if not values["notes"].is_empty():
		entry += "\n" + values["notes"]
	if parts.has(entry):
		research_forms["parts"]["message"].text = "This item is already in your parts list."
		return
	parts.append(entry)
	render_parts()
	job_workspace.save_state({"parts":parts.duplicate()})
	research_forms["parts"]["message"].text = "Added to My parts list. No order has been placed."

func render_parts() -> void:
	parts_view.clear()
	for entry in parts:
		parts_view.add_item(entry.get_slice("\n", 0))
	parts_message.text = "%d parts in the current job. Save status is shown on Ask GopherTech." % parts.size()

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
