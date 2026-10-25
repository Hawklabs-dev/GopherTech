extends Control

var equipment: Array = []
var visible_equipment: Array = []
var busy := false
var operation := "list"
var api_url := "http://127.0.0.1:8000"
var request_node: HTTPRequest
var status: Label
var summary: Label
var search: LineEdit
var records: ItemList
var details: Label
var refresh: Button
var save: Button
var fields: Dictionary = {}
var form_message: Label
var borrower: LineEdit
var checkout: Button
var checkin: Button
var action_message: Label
var selected_id := -1
var online := false

func label(text: String, size: int = 16) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	return node

func panel(parent: Node) -> VBoxContainer:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182535")
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	box.add_theme_stylebox_override("panel", style)
	parent.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	box.add_child(column)
	return column

func _ready() -> void:
	var configured := OS.get_environment("GOPHERTECH_API_URL").strip_edges().trim_suffix("/")
	if not configured.is_empty():
		api_url = configured
	var background := ColorRect.new()
	background.color = Color("0c1420")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 18)
	scroll.add_child(root)
	root.add_child(label("HAWKLABS  /  WORKSHOP", 14))
	root.add_child(label("GopherTech", 36))
	root.add_child(label("Your workshop. Your business.", 18))
	var navigation := HBoxContainer.new()
	root.add_child(navigation)
	var equipment_page := VBoxContainer.new()
	equipment_page.add_theme_constant_override("separation", 18)
	root.add_child(equipment_page)
	var bills = load("res://finance_dashboard.gd").new()
	bills.kind = "payable"
	bills.visible = false
	root.add_child(bills)
	var invoices = load("res://finance_dashboard.gd").new()
	invoices.kind = "receivable"
	invoices.visible = false
	root.add_child(invoices)
	var pages := [equipment_page, bills, invoices]
	var titles := ["Equipment", "Bills to pay", "Invoices to collect"]
	var navigation_group := ButtonGroup.new()
	for index in range(pages.size()):
		var tab := Button.new()
		tab.text = titles[index]
		tab.toggle_mode = true
		tab.button_group = navigation_group
		tab.button_pressed = index == 0
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size.y = 44
		var selected_index := index
		tab.pressed.connect(func():
			for page_index in range(pages.size()):
				pages[page_index].visible = page_index == selected_index
		)
		navigation.add_child(tab)

	status = label("Connecting…")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equipment_page.add_child(status)
	summary = label("Equipment inventory", 22)
	equipment_page.add_child(summary)
	var inventory := panel(equipment_page)
	var toolbar := HBoxContainer.new()
	inventory.add_child(toolbar)
	search = LineEdit.new()
	search.placeholder_text = "Find equipment or a person's name"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_text: String): render_records())
	toolbar.add_child(search)
	refresh = Button.new()
	refresh.text = "Refresh"
	refresh.pressed.connect(load_equipment)
	toolbar.add_child(refresh)
	records = ItemList.new()
	records.custom_minimum_size.y = 170
	records.item_selected.connect(show_details)
	inventory.add_child(records)
	details = label("Select equipment to see its details.")
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory.add_child(details)
	var action_row := HBoxContainer.new()
	inventory.add_child(action_row)
	borrower = LineEdit.new()
	borrower.placeholder_text = "Who is taking it?"
	borrower.max_length = 120
	borrower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	borrower.custom_minimum_size.y = 44
	action_row.add_child(borrower)
	checkout = Button.new()
	checkout.text = "Check out"
	checkout.custom_minimum_size.y = 44
	checkout.pressed.connect(func(): change_custody(false))
	action_row.add_child(checkout)
	checkin = Button.new()
	checkin.text = "Check in"
	checkin.custom_minimum_size.y = 44
	checkin.pressed.connect(func(): change_custody(true))
	action_row.add_child(checkin)
	action_message = label("Select equipment to check it in or out.")
	action_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory.add_child(action_message)
	var add_toggle := Button.new()
	add_toggle.text = "Add new equipment"
	add_toggle.toggle_mode = true
	add_toggle.custom_minimum_size.y = 40
	equipment_page.add_child(add_toggle)
	var form := panel(equipment_page)
	form.get_parent().visible = false
	add_toggle.toggled.connect(func(open: bool): form.get_parent().visible = open)
	form.add_child(label("Add equipment", 22))
	form.add_child(label("Keep a record of the tools and hardware in your workshop."))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	form.add_child(grid)
	for key in ["name", "manufacturer", "model", "notes"]:
		grid.add_child(label(key.capitalize() + (" *" if key == "name" else "")))
		var input := LineEdit.new()
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.max_length = 2000 if key == "notes" else 200
		input.placeholder_text = "Required" if key == "name" else "Optional"
		grid.add_child(input)
		fields[key] = input
	save = Button.new()
	save.text = "Save equipment"
	save.pressed.connect(add_equipment)
	form.add_child(save)
	form_message = label("Saved records are stored in your local equipment database.")
	form_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(form_message)
	equipment_page.add_child(label("HawkLabs • Equipment desk", 14))
	request_node = HTTPRequest.new()
	request_node.timeout = 8.0
	request_node.request_completed.connect(on_response)
	add_child(request_node)
	load_equipment()

func selected_equipment() -> Dictionary:
	for item in equipment:
		if int(item["id"]) == selected_id:
			return item
	return {}

func update_actions() -> void:
	var item := selected_equipment()
	var ready := not busy and online and not item.is_empty()
	var out: bool = item.get("status", "available") == "checked_out"
	checkout.disabled = not ready or out
	checkin.disabled = not ready or not out
	borrower.editable = ready and not out

func change_custody(returning: bool) -> void:
	var item := selected_equipment()
	if busy or not online or item.is_empty():
		return
	var out: bool = item.get("status", "available") == "checked_out"
	if returning != out:
		return
	if not returning and borrower.text.strip_edges().is_empty():
		action_message.text = "Enter the name of the person taking this equipment."
		borrower.grab_focus()
		return
	operation = "checkin" if returning else "checkout"
	var payload: Dictionary = {"checkout_id": item.get("checkout_id")} if returning else {"borrower": borrower.text.strip_edges()}
	set_busy(true)
	action_message.text = "Checking in…" if returning else "Checking out…"
	var url := "%s/equipment/%d/%s" % [api_url, selected_id, operation]
	var error := request_node.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		set_busy(false)
		action_message.text = "Could not start. Your entry has been kept. Try again."

func set_busy(value: bool) -> void:
	busy = value
	refresh.disabled = value
	save.disabled = value
	for input in fields.values():
		input.editable = not value
	update_actions()

func load_equipment() -> void:
	if busy:
		return
	operation = "list"
	set_busy(true)
	status.text = "Loading equipment…"
	var error := request_node.request(api_url + "/equipment/availability")
	if error != OK:
		set_busy(false)
		status.text = "Could not start the connection. Check the API address and refresh."

func add_equipment() -> void:
	if busy:
		return
	if fields["name"].text.strip_edges().is_empty():
		form_message.text = "Enter an equipment name before saving."
		fields["name"].grab_focus()
		return
	var payload := {}
	for key in fields:
		var value: String = fields[key].text.strip_edges()
		payload[key] = null if value.is_empty() else value
	operation = "create"
	set_busy(true)
	form_message.text = "Saving equipment…"
	var error := request_node.request(api_url + "/equipment", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		set_busy(false)
		form_message.text = "Save did not start. Your entries have been kept."

func on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if operation == "list":
		online = false
	set_busy(false)
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		if operation in ["checkout", "checkin"]:
			online = false
			update_actions()
			action_message.text = "Could not confirm the change. Refresh to check what happened before trying again."
			var problem: Variant = JSON.parse_string(body.get_string_from_utf8())
			if code in [404, 409, 422] and problem is Dictionary and problem.get("detail") is String:
				action_message.text = problem["detail"]
		elif operation == "create":
			form_message.text = "Save could not be confirmed. Refresh the inventory before retrying to avoid duplicates. Your entries have been kept."
		else:
			status.text = "Offline • Choose Refresh to reconnect. Previous results may be out of date."
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if operation in ["checkout", "checkin"]:
		if not data is Dictionary or not data.has("id"):
			online = false
			update_actions()
			action_message.text = "Unexpected reply. Refresh before trying again."
			return
		action_message.text = "Equipment checked in. Thank you!" if operation == "checkin" else "Equipment checked out to " + borrower.text.strip_edges() + "."
		borrower.text = ""
		load_equipment()
		return
	if operation == "create":
		if not data is Dictionary or not data.has("id"):
			form_message.text = "Save response was unexpected. Refresh before retrying."
			return
		for input in fields.values():
			input.text = ""
		form_message.text = "Equipment saved successfully."
		load_equipment()
		return
	if not data is Dictionary or not data.get("equipment") is Array:
		status.text = "Unexpected server response. Previous results may be out of date."
		return
	for item in data["equipment"]:
		if not item is Dictionary or not item.has("id") or not item.has("name"):
			status.text = "Invalid equipment record received. Refresh to try again."
			return
	online = true
	equipment = data["equipment"]
	status.text = "Connected • Updated " + Time.get_time_string_from_system()
	render_records()

func render_records() -> void:
	records.clear()
	visible_equipment.clear()
	var query := search.text.strip_edges().to_lower()
	for item in equipment:
		var haystack := "%s %s %s %s %s" % [item.get("name", ""), item.get("manufacturer", ""), item.get("model", ""), item.get("notes", ""), item.get("borrower", "")]
		if not query.is_empty() and not query in haystack.to_lower():
			continue
		visible_equipment.append(item)
		var availability: String = "Out with " + str(item.get("borrower", "someone")) if item.get("status") == "checked_out" else "Available"
		records.add_item("#%d   %s  •  %s" % [int(item["id"]), item["name"], availability])
	var out_count := 0
	for item in equipment:
		if item.get("status") == "checked_out":
			out_count += 1
	summary.text = "%d available  •  %d out  •  %d shown" % [equipment.size() - out_count, out_count, visible_equipment.size()]
	if equipment.is_empty():
		details.text = "Your workshop starts here. Add your first piece of equipment below."
	elif visible_equipment.is_empty():
		details.text = "No equipment matches your search. Try another name or model."
	else:
		details.text = "Select equipment to see its details."
	var selected_index := -1
	for index in range(visible_equipment.size()):
		if int(visible_equipment[index]["id"]) == selected_id:
			selected_index = index
	if selected_index >= 0:
		records.select(selected_index)
		show_details(selected_index)
	else:
		selected_id = -1
		action_message.text = "Select equipment to check it in or out."
	update_actions()

func show_details(index: int) -> void:
	var item: Dictionary = visible_equipment[index]
	var changed_selection := selected_id != int(item["id"])
	selected_id = int(item["id"])
	if changed_selection or action_message.text.begins_with("Select equipment"):
		action_message.text = "Ready to return it? Choose Check in." if item.get("status") == "checked_out" else "Enter your name, then choose Check out."
	var availability: String = "Out with " + str(item.get("borrower", "someone")) if item.get("status") == "checked_out" else "Available — ready to take"
	var lines := PackedStringArray([str(item["name"]), availability])
	for key in ["manufacturer", "model", "notes"]:
		var value: Variant = item.get(key)
		lines.append(key.capitalize() + ": " + ("—" if value == null or str(value).is_empty() else str(value)))
	details.text = "\n".join(lines)
	update_actions()
