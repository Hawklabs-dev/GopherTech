extends VBoxContainer

var kind := "payable"
var api_url := "http://127.0.0.1:8000"
var request_node: HTTPRequest
var busy := false
var online := false
var operation := "list"
var documents: Array = []
var visible_documents: Array = []
var selected_id := -1
var status: Label
var totals_label: Label
var search: LineEdit
var records: ItemList
var details: Label
var refresh: Button
var save: Button
var payment_save: Button
var inputs: Dictionary = {}
var currency: OptionButton
var payment_inputs: Dictionary = {}
var message: Label
var form_panel: PanelContainer
var add_toggle: Button
var document_request_key := ""
var document_fingerprint := ""
var payment_request_key := ""
var payment_fingerprint := ""
var payment_drafts: Dictionary = {}

func text_label(text: String, size: int = 16) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

func card() -> VBoxContainer:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182535")
	style.set_corner_radius_all(12)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	frame.add_child(box)
	return box

func button(text: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 42
	node.pressed.connect(callback)
	return node

func field(grid: GridContainer, caption: String, placeholder: String, max_length: int = 160) -> LineEdit:
	var caption_node := text_label(caption)
	caption_node.custom_minimum_size.x = 170
	caption_node.autowrap_mode = TextServer.AUTOWRAP_OFF
	grid.add_child(caption_node)
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.max_length = max_length
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(node)
	return node

func new_key() -> String:
	var bytes := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-%s-%s-%s" % [bytes.substr(0, 8), bytes.substr(8, 4), bytes.substr(12, 4), bytes.substr(16, 4), bytes.substr(20, 12)]

func today() -> String:
	return Time.get_date_string_from_system()

func _ready() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var configured := OS.get_environment("GOPHERTECH_API_URL").strip_edges().trim_suffix("/")
	if not configured.is_empty():
		api_url = configured
	add_child(text_label("Bills to pay" if kind == "payable" else "Invoices to collect", 26))
	status = text_label("Choose Refresh to load your records.")
	add_child(status)
	totals_label = text_label("No balances loaded.", 20)
	add_child(totals_label)
	var inventory := card()
	var toolbar := HBoxContainer.new()
	inventory.add_child(toolbar)
	search = LineEdit.new()
	search.placeholder_text = "Find a name or bill number" if kind == "payable" else "Find a name or invoice number"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_value: String): render_records())
	toolbar.add_child(search)
	refresh = button("Refresh", load_documents)
	toolbar.add_child(refresh)
	records = ItemList.new()
	records.custom_minimum_size.y = 120
	records.item_selected.connect(show_details)
	inventory.add_child(records)
	details = text_label("Select a record to see its balance and payment history.")
	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size.y = 100
	inventory.add_child(detail_scroll)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(details)
	var payment_grid := GridContainer.new()
	payment_grid.columns = 2
	payment_grid.add_theme_constant_override("h_separation", 18)
	payment_grid.add_theme_constant_override("v_separation", 8)
	inventory.add_child(payment_grid)
	payment_inputs["amount"] = field(payment_grid, "Payment amount", "Example: 25.00", 20)
	payment_inputs["paid_on"] = field(payment_grid, "Payment date", "YYYY-MM-DD", 10)
	payment_inputs["paid_on"].text = today()
	payment_inputs["reference"] = field(payment_grid, "Payment reference", "Optional — receipt or transfer number", 120)
	payment_save = button("Record payment made" if kind == "payable" else "Record payment received", record_payment)
	inventory.add_child(payment_save)
	inventory.add_child(text_label("Records a payment that already happened. No money is sent."))
	message = text_label("Select a bill or invoice before recording a payment.")
	add_child(message)
	add_toggle = button("Add a bill" if kind == "payable" else "Add an invoice", func(): form_panel.visible = not form_panel.visible)
	add_child(add_toggle)
	var form := card()
	form_panel = form.get_parent()
	form_panel.visible = false
	form.add_child(text_label("New bill" if kind == "payable" else "New customer invoice", 22))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	form.add_child(grid)
	inputs["party"] = field(grid, "Supplier" if kind == "payable" else "Customer", "Name")
	inputs["reference"] = field(grid, "Bill number" if kind == "payable" else "Invoice number", "Example: INV-1001", 120)
	inputs["issue_date"] = field(grid, "Bill date" if kind == "payable" else "Invoice date", "YYYY-MM-DD", 10)
	inputs["issue_date"].text = today()
	inputs["due_date"] = field(grid, "Due date", "YYYY-MM-DD", 10)
	var currency_label := text_label("Currency")
	currency_label.custom_minimum_size.x = 170
	currency_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	grid.add_child(currency_label)
	currency = OptionButton.new()
	for option in ["Choose currency", "CAD", "USD", "EUR", "GBP"]:
		currency.add_item(option)
	grid.add_child(currency)
	inputs["amount"] = field(grid, "Total including tax", "Example: 125.50", 20)
	inputs["notes"] = field(grid, "Notes", "Optional", 2000)
	form.add_child(text_label("Enter the total from the existing bill or invoice. Tax is not calculated here."))
	save = button("Save bill" if kind == "payable" else "Save invoice", create_document)
	form.add_child(save)
	request_node = HTTPRequest.new()
	request_node.timeout = 10.0
	request_node.request_completed.connect(on_response)
	add_child(request_node)
	visibility_changed.connect(func():
		if is_visible_in_tree() and not busy:
			load_documents()
	)
	set_busy(false)
	if is_visible_in_tree():
		load_documents()

func selected_document() -> Dictionary:
	for document in documents:
		if int(document["id"]) == selected_id:
			return document
	return {}

func set_busy(value: bool) -> void:
	busy = value
	records.mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
	records.focus_mode = Control.FOCUS_NONE if value else Control.FOCUS_ALL
	refresh.disabled = value
	save.disabled = value
	var selected := selected_document()
	payment_save.disabled = value or not online or selected.is_empty() or int(selected.get("balance_cents", 0)) <= 0
	for input in inputs.values():
		input.editable = not value
	currency.disabled = value
	for input in payment_inputs.values():
		input.editable = not value

func start_request(url: String, method: int = HTTPClient.METHOD_GET, payload: Dictionary = {}) -> void:
	set_busy(true)
	var error := request_node.request(api_url + url, ["Content-Type: application/json"], method, JSON.stringify(payload) if method != HTTPClient.METHOD_GET else "")
	if error != OK:
		online = false
		set_busy(false)
		message.text = "Could not connect. Your entries have been kept. Choose Refresh to try again."

func load_documents() -> void:
	if busy:
		return
	operation = "list"
	status.text = "Loading records…"
	start_request("/finance/documents")

func valid_amount(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[0-9]+(\\.[0-9]{1,2})?$")
	if pattern.search(value) == null:
		return false
	# Validation only: monetary calculations are performed by the server in cents.
	return value.replace(".", "").to_int() > 0

func valid_date(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
	return pattern.search(value) != null

func create_document() -> void:
	if busy:
		return
	var payload := {"kind": kind}
	for key in inputs:
		payload[key] = inputs[key].text.strip_edges()
	if payload["party"].is_empty() or payload["reference"].is_empty():
		message.text = "Enter the name and bill or invoice number."
		return
	if not valid_amount(payload["amount"]):
		message.text = "Enter a positive amount with no more than two decimal places, such as 125.50."
		return
	if not valid_date(payload["issue_date"]) or not valid_date(payload["due_date"]):
		message.text = "Enter both dates as YYYY-MM-DD."
		return
	if currency.selected <= 0:
		message.text = "Choose the currency shown on the bill or invoice."
		return
	payload["currency"] = currency.get_item_text(currency.selected)
	var fingerprint := JSON.stringify(payload)
	if document_request_key.is_empty() or fingerprint != document_fingerprint:
		document_request_key = new_key()
		document_fingerprint = fingerprint
	payload["request_key"] = document_request_key
	operation = "create"
	message.text = "Saving record…"
	start_request("/finance/documents", HTTPClient.METHOD_POST, payload)

func record_payment() -> void:
	var document := selected_document()
	if busy or not online or document.is_empty() or int(document.get("balance_cents", 0)) <= 0:
		return
	var payload := {}
	for key in payment_inputs:
		payload[key] = payment_inputs[key].text.strip_edges()
	if not valid_amount(payload["amount"]) or not valid_date(payload["paid_on"]):
		message.text = "Enter a positive payment amount and a date as YYYY-MM-DD."
		return
	var fingerprint := str(selected_id) + JSON.stringify(payload)
	if payment_request_key.is_empty() or fingerprint != payment_fingerprint:
		payment_request_key = new_key()
		payment_fingerprint = fingerprint
	payload["request_key"] = payment_request_key
	operation = "payment"
	message.text = "Recording payment…"
	start_request("/finance/documents/%d/payments" % selected_id, HTTPClient.METHOD_POST, payload)

func on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var parser := JSON.new()
	var data: Variant = null
	if parser.parse(body.get_string_from_utf8()) == OK:
		data = parser.data
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		online = false
		set_busy(false)
		status.text = "Offline or request declined. Previous balances may be out of date."
		message.text = "Could not confirm the change. Refresh before retrying; your entries have been kept."
		if data is Dictionary and data.get("detail") is String:
			message.text = data["detail"]
		elif code == 422 and data is Dictionary and data.get("detail") is Array:
			message.text = "Check the dates, names and amount. Dates must be valid calendar dates and the due date cannot precede the bill or invoice date."
		return
	if not data is Dictionary:
		online = false
		set_busy(false)
		message.text = "Unexpected reply. Refresh before retrying."
		return
	if operation in ["create", "payment"]:
		if not data.has("id") or not data.has("balance"):
			online = false
			set_busy(false)
			message.text = "Could not confirm the save. Refresh before retrying."
			return
		select_document_id(int(data["id"]))
		if operation == "create":
			for key in ["party", "reference", "amount", "notes", "due_date"]:
				inputs[key].text = ""
			document_request_key = ""
			form_panel.visible = false
			message.text = "Bill saved." if kind == "payable" else "Invoice saved."
		else:
			payment_inputs["amount"].text = ""
			payment_inputs["reference"].text = ""
			payment_request_key = ""
			message.text = "Payment recorded. Remaining: %s %s." % [data["currency"], data["balance"]]
		set_busy(false)
		load_documents()
		return
	if operation == "details":
		if not data.get("payments") is Array or not data.has("balance"):
			set_busy(false)
			message.text = "Payment history could not be read. Choose Refresh."
			return
		set_busy(false)
		var lines := PackedStringArray(["%s • %s" % [data["party"], data["reference"]], "Total: %s %s   •   Paid: %s   •   Remaining: %s" % [data["currency"], data["amount"], data["paid"], data["balance"]], "Due: " + data["due_date"]])
		for payment in data["payments"]:
			lines.append("%s  •  %s %s  •  %s" % [payment["paid_on"], data["currency"], payment["amount"], payment["reference"]])
		if data["payments"].is_empty():
			lines.append("No payments recorded yet.")
		if not data.get("notes", "").is_empty():
			lines.append(data["notes"])
		details.text = "\n".join(lines)
		return
	if not data.get("documents") is Array or not data.get("totals") is Array:
		online = false
		set_busy(false)
		message.text = "Unexpected balances. Choose Refresh."
		return
	documents.clear()
	for document in data["documents"]:
		if document is Dictionary and document.get("kind") == kind:
			documents.append(document)
	var lines := PackedStringArray()
	for total in data["totals"]:
		if total.get("kind") == kind:
			lines.append("%s %s outstanding  •  %s overdue" % [total["currency"], total["outstanding"], total["overdue"]])
	totals_label.text = "\n".join(lines) if not lines.is_empty() else "No bills to pay yet." if kind == "payable" else "No invoices to collect yet."
	online = true
	status.text = "Up to date • As of " + data.get("as_of", "")
	set_busy(false)
	render_records()

func render_records() -> void:
	records.clear()
	visible_documents.clear()
	var query := search.text.strip_edges().to_lower()
	for document in documents:
		var haystack := "%s %s" % [document["party"], document["reference"]]
		if not query.is_empty() and not query in haystack.to_lower():
			continue
		visible_documents.append(document)
		var state: String = "Paid" if document["status"] == "paid" else "OVERDUE" if document["overdue"] else "Part paid" if document["status"] == "partial" else "Open"
		records.add_item("%s • %s • %s %s • Due %s • %s" % [document["party"], document["reference"], document["currency"], document["balance"], document["due_date"], state])
	var index := -1
	for i in range(visible_documents.size()):
		if int(visible_documents[i]["id"]) == selected_id:
			index = i
	if index >= 0:
		records.select(index)
		show_details(index)
	else:
		select_document_id(-1)
		details.text = "No matching records." if not query.is_empty() else "Select a record to see its balance and payment history."
	set_busy(busy)

func select_document_id(value: int) -> void:
	if value == selected_id:
		return
	if selected_id >= 0:
		payment_drafts[selected_id] = {"amount": payment_inputs["amount"].text, "paid_on": payment_inputs["paid_on"].text, "reference": payment_inputs["reference"].text, "key": payment_request_key, "fingerprint": payment_fingerprint}
	selected_id = value
	var draft: Dictionary = payment_drafts.get(value, {})
	payment_inputs["amount"].text = draft.get("amount", "")
	payment_inputs["paid_on"].text = draft.get("paid_on", today())
	payment_inputs["reference"].text = draft.get("reference", "")
	payment_request_key = draft.get("key", "")
	payment_fingerprint = draft.get("fingerprint", "")

func show_details(index: int) -> void:
	if busy:
		return
	select_document_id(int(visible_documents[index]["id"]))
	operation = "details"
	start_request("/finance/documents/%d" % selected_id)
