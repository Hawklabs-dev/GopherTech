extends VBoxContainer
## Persistent conversations with source research and optional local passage selection.

signal job_loaded(job: Dictionary)
signal status_changed(value: String)
signal before_switch
signal save_notice(value: String)
signal answer_ready
signal reference_ready(control: Control)

var order_number: LineEdit
var order_picker: VBoxContainer
var new_order_row: HBoxContainer
var order_search: LineEdit
var displayed_jobs: Array = []
var drafts: Dictionary = {}
var creation_body: Dictionary = {}
var pending_creation: Dictionary = {}
var saved_view: VBoxContainer
var question: TextEdit
var ask_button: Button
var status: Label
var saved_status: Label
var conversation: RichTextLabel
var job_list: ItemList
var notes: TextEdit
var notes_timer: Timer
var active_section := "parts"
var section_drafts: Dictionary = {}
var section_dirty := false
var sections_enabled := false
var request_node: HTTPRequest
var job: Dictionary = {}
var jobs: Array = []
var source_records: Array = []
var document: Dictionary = {}
var document_panel: VBoxContainer
var document_reader: TextEdit
var live_browser: VBoxContainer
var document_links: RichTextLabel
var document_header: RichTextLabel
var pdf_controls: HBoxContainer
var pdf_page: SpinBox
var pdf_image: TextureRect
var api_url := "http://127.0.0.1:8000"
var busy := false
var operation := ""
var pending_state: Dictionary = {}
var in_flight_state: Dictionary = {}
var pending_reference := ""
var pending_open := ""
var request_key := ""
var request_fingerprint := ""
var create_key := ""
var applying := false
var sources_expanded := false
var submitted_question := ""
var latest_answer_paragraph := 0

func label(parent: Node, value: String, size: int = 15) -> Label:
	var node := Label.new()
	node.text = value
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size", size)
	parent.add_child(node)
	return node

func rich(parent: Node, height: float) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.selection_enabled = true
	node.fit_content = true
	node.custom_minimum_size.y = height
	parent.add_child(node)
	node.meta_clicked.connect(on_link)
	return node

func key() -> String:
	var value := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-%s-%s-%s" % [value.substr(0,8),value.substr(8,4),value.substr(12,4),value.substr(16,4),value.substr(20,12)]

func escape(value: String) -> String:
	return value.replace("[", "[lb]")

func _ready() -> void:
	add_theme_constant_override("separation", 16)
	var configured := OS.get_environment("GOPHERTECH_API_URL").strip_edges().trim_suffix("/")
	if not configured.is_empty(): api_url = configured
	question = TextEdit.new()
	question.placeholder_text = "Tell me what’s happening. Make/model helps, if you know it…"
	question.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and (event.ctrl_pressed or event.meta_pressed):
			question.accept_event()
			ask()
	)
	question.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	question.custom_minimum_size.y = 110
	add_child(question)
	ask_button = Button.new()
	ask_button.text = "Ask GopherTech"
	ask_button.custom_minimum_size.y = 54
	ask_button.pressed.connect(ask)
	add_child(ask_button)
	status = label(self, "Connecting to your local workspace…", 13)
	conversation = rich(self, 160)
	conversation.text = "Ask in your own words. I’ll keep the useful details with this conversation."
	document_panel = VBoxContainer.new()
	document_panel.add_theme_constant_override("separation", 12)
	document_panel.visible = false
	add_child(document_panel)
	label(document_panel, "Reference document", 21)
	document_header = rich(document_panel, 50)
	live_browser = load("res://reference_browser.gd").new()
	document_panel.add_child(live_browser)
	live_browser.visible = false
	live_browser.saved_text_requested.connect(func():
		live_browser.visible = false
		document_reader.visible = true
		document_links.visible = true
		document_header.text = "Saved text · [url=livepage]Return to live webpage[/url]"
		if document.get("url", "") != live_browser.current_url:
			document_reader.text = "No saved text is available for this page. Return to the live webpage to continue browsing."
			document_links.visible = false
		else:
			document_reader.text = document.get("text", "").replace("\f", "\n\n──────── Next PDF page ────────\n\n")
	)
	document_reader = TextEdit.new()
	document_reader.editable = false
	document_reader.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	document_reader.custom_minimum_size.y = 350
	document_reader.scroll_past_end_of_file = false
	document_panel.add_child(document_reader)
	document_links = rich(document_panel, 30)
	pdf_controls = HBoxContainer.new()
	document_panel.add_child(pdf_controls)
	label(pdf_controls, "PDF page (1–60)")
	pdf_page = SpinBox.new()
	pdf_page.min_value = 1
	pdf_page.max_value = 60
	pdf_controls.add_child(pdf_page)
	var view := Button.new()
	view.text = "View page"
	view.pressed.connect(func():
		if not document.is_empty(): send("pdf", "/research/pdf-page", {"url":document["url"],"page":int(pdf_page.value)})
	)
	pdf_controls.add_child(view)
	pdf_image = TextureRect.new()
	pdf_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pdf_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pdf_image.custom_minimum_size.y = 400
	pdf_image.resized.connect(fit_pdf_page)
	pdf_image.visible = false
	document_panel.add_child(pdf_image)
	saved_view = VBoxContainer.new()
	saved_view.add_theme_constant_override("separation", 14)
	saved_view.visible = false
	add_child(saved_view)
	var order_actions := HFlowContainer.new()
	order_actions.add_theme_constant_override("h_separation", 8)
	saved_view.add_child(order_actions)
	var change := Button.new()
	change.text = "Find / switch order"
	change.custom_minimum_size.y = 44
	change.pressed.connect(func():
		order_picker.visible = not order_picker.visible
		if order_picker.visible: refresh_jobs()
	)
	order_actions.add_child(change)
	var fresh := Button.new()
	fresh.text = "New work order"
	fresh.custom_minimum_size.y = 44
	fresh.pressed.connect(func():
		new_order_row.visible = not new_order_row.visible
		if new_order_row.visible: order_number.grab_focus()
	)
	order_actions.add_child(fresh)
	new_order_row = HBoxContainer.new()
	new_order_row.visible = false
	saved_view.add_child(new_order_row)
	order_number = LineEdit.new()
	order_number.placeholder_text = "New order number (optional)"
	order_number.max_length = 80
	order_number.custom_minimum_size.y = 44
	order_number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_order_row.add_child(order_number)
	var create := Button.new()
	create.text = "Create"
	create.custom_minimum_size.y = 44
	create.pressed.connect(func(): create_order())
	new_order_row.add_child(create)
	order_picker = VBoxContainer.new()
	order_picker.add_theme_constant_override("separation", 8)
	saved_view.add_child(order_picker)
	order_search = LineEdit.new()
	order_search.placeholder_text = "Find by order number or machine"
	order_search.custom_minimum_size.y = 44
	order_search.text_changed.connect(func(_value: String): render_jobs())
	order_picker.add_child(order_search)
	job_list = ItemList.new()
	job_list.custom_minimum_size.y = 170
	job_list.fixed_icon_size = Vector2i(30, 34)
	job_list.item_selected.connect(func(index: int): open_job(displayed_jobs[index]["id"]))
	order_picker.add_child(job_list)
	notes = TextEdit.new()
	notes.placeholder_text = "Observations, measurements and things already checked"
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes.custom_minimum_size.y = 180
	saved_view.add_child(notes)
	saved_status = label(saved_view, "Notes save automatically when the backend is connected.")
	saved_status.visible = false
	notes_timer = Timer.new()
	notes_timer.one_shot = true
	notes_timer.wait_time = 0.8
	notes_timer.timeout.connect(func(): save_state(collect_notes()))
	add_child(notes_timer)
	notes.text_changed.connect(func():
		if not applying:
			section_dirty = true
			notes_timer.start()
	)
	request_node = HTTPRequest.new()
	request_node.timeout = 90.0
	request_node.body_size_limit = 16 * 1024 * 1024
	request_node.request_completed.connect(on_response)
	add_child(request_node)
	send("startup", "/jobs?include_archived=false", {}, HTTPClient.METHOD_GET)

func set_status(value: String) -> void:
	status_changed.emit(value)
	status.text = value
	if saved_status != null: saved_status.text = value

func send(kind: String, path: String, body: Dictionary = {}, method: int = HTTPClient.METHOD_POST) -> void:
	if busy: return
	operation = kind
	busy = true
	if kind in ["open", "create"]: lock_editors(true)
	request_node.timeout = 20.0 if kind == "question" else 5.0 if kind in ["startup", "list", "open", "state", "create", "archive"] else 45.0
	ask_button.disabled = true
	if kind == "question": ask_button.text = "Finding useful information…"
	var error := request_node.request(api_url + path, ["Content-Type: application/json"], method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
	if error != OK:
		if kind == "state":
			in_flight_state.merge(pending_state, true)
			pending_state = in_flight_state.duplicate(true)
		busy = false
		lock_editors(false)
		ask_button.disabled = false
		ask_button.text = "Ask GopherTech"
		set_status("Backend unavailable. Your question is kept; it has not been saved. Start run_backend.sh and retry.")

func ask() -> void:
	if busy: return
	var value := question.text.strip_edges()
	if value.is_empty():
		set_status("Type your question first.")
		return
	if value.length() > 4000:
		set_status("Please keep this question under 4,000 characters.")
		return
	var fingerprint := str(job.get("id", "")) + value
	if request_key.is_empty() or fingerprint != request_fingerprint:
		request_key = key()
		request_fingerprint = fingerprint
	var body := {"question":value,"request_key":request_key}
	if job.has("id"): body["job_id"] = job["id"]
	submitted_question = value
	set_status("Reading saved and manufacturer references…")
	send("question", "/jobs/question", body)

func refresh_jobs() -> void:
	if not busy: send("list", "/jobs", {}, HTTPClient.METHOD_GET)

func open_job(id: String) -> void:
	before_switch.emit()
	pending_creation.clear()
	if busy or not pending_state.is_empty() or not notes_timer.is_stopped():
		if not notes_timer.is_stopped() and not applying: pending_state.merge(collect_notes(), true)
		notes_timer.stop()
		pending_open = id
		flush_state()
		return
	send("open", "/jobs/" + id, {}, HTTPClient.METHOD_GET)

func new_job() -> void:
	before_switch.emit()
	if busy or not pending_state.is_empty() or not notes_timer.is_stopped():
		set_status("Let the current job finish saving before starting another.")
		flush_state()
		return
	if job.has("id"): drafts[job["id"]] = question.text
	job = {}
	section_drafts.clear()
	section_dirty = false
	active_section = "parts"
	source_records = []
	pending_reference = ""
	pending_open = ""
	create_key = ""
	request_fingerprint = ""
	submitted_question = ""
	document = {}
	question.text = ""
	applying = true
	notes.text = ""
	applying = false
	conversation.text = "Ask a question to start a saved conversation."
	document_panel.visible = false
	live_browser.reset()
	job_loaded.emit(job)
	sources_expanded = false
	request_key = ""
	question.grab_focus()
	set_status("New conversation · Start with what you know.")

func save_state(changes: Dictionary) -> void:
	pending_state.merge(changes, true)
	call_deferred("flush_state")

func flush_state() -> void:
	if busy or pending_state.is_empty(): return
	if not job.has("id"):
		if create_key.is_empty(): create_key = key()
		send("create", "/jobs", {"title":"Workshop notes / parts","request_key":create_key})
		return
	in_flight_state = pending_state.duplicate(true)
	pending_state.clear()
	set_status("Saving job notes / parts…")
	send("state", "/jobs/" + job["id"] + "/state", in_flight_state, HTTPClient.METHOD_PUT)

func open_reference(url: String) -> void:
	if DisplayServer.get_name() != "headless": show_live_reference(url)
	pending_reference = url
	if not job.has("id"):
		if create_key.is_empty(): create_key = key()
		if not busy: send("create", "/jobs", {"title":"Reference research","request_key":create_key})
		return
	drain()

func drain() -> void:
	if busy: return
	if not pending_state.is_empty():
		flush_state()
	elif not pending_creation.is_empty():
		var body := pending_creation.duplicate()
		pending_creation.clear()
		start_order(body)
	elif not pending_open.is_empty():
		var id := pending_open
		pending_open = ""
		open_job(id)
	elif not pending_reference.is_empty() and job.has("id"):
		var url := pending_reference
		pending_reference = ""
		set_status("Reading and saving the reference…")
		send("reference", "/jobs/" + job["id"] + "/reference", {"url":url})

func apply_job(value: Dictionary) -> bool:
	if not notes_timer.is_stopped():
		notes_timer.stop()
		pending_state.merge(collect_notes(), true)
	var switching: bool = job.get("id", "") != value.get("id", "")
	if switching and job.has("id") and not pending_state.is_empty():
		# An arriving open response must never merge old-order edits into its data.
		pending_open = value.get("id", "")
		set_status("Saving the current order before switching…")
		call_deferred("drain")
		return false
	if switching:
		if job.has("id"): drafts[job["id"]] = question.text
		question.text = drafts.get(value.get("id", ""), "") if operation != "question" else question.text
		document = {}
		document_panel.visible = false
		live_browser.reset()
		sources_expanded = false
	job = value
	for name in pending_state: job[name] = pending_state[name]
	applying = true
	section_drafts = job.get("section_drafts", {}).duplicate(true)
	if not section_drafts.has("parts"):
		section_drafts["parts"] = {"task":"", "notes":job.get("notes", "")}
	notes.text = section_drafts.get(active_section, {}).get("notes", "") if sections_enabled else job.get("notes", "")
	applying = false
	source_records = job.get("sources", [])
	render_conversation()
	if switching or operation in ["open", "create"]:
		order_number.text = ""
		new_order_row.visible = false
		order_picker.visible = false
	job_loaded.emit(job)
	return true

func render_conversation() -> void:
	var transcript := ""
	for entry in job.get("messages", []):
		var id := str(entry["id"])
		var content: String = entry["content"]
		if entry["role"] == "assistant" and ("Page " in content and "Source:" in content):
			content = "This older reply contains unverified PDF extracts. Open the original reference from saved job history before using it."
		if entry["role"] == "assistant": latest_answer_paragraph = transcript.count("\n")
		if entry["role"] == "user" and not transcript.is_empty():
			transcript += "[color=#536175]────────────────────────[/color]\n\n"
		transcript += "[color=#ffb347][b]%s[/b][/color]\n%s\n\n" % ["You" if entry["role"] == "user" else "GopherTech", escape(content)]
		for evidence in entry.get("evidence", []):
			transcript += "[url=evidence:%s]View source: %s[/url]\n" % [evidence["url"], escape(evidence.get("title", "Reference"))]
		if not entry.get("evidence", []).is_empty(): transcript += "\n"
	if transcript.is_empty(): transcript = "Ask your question above to continue.\n\n"
	if not source_records.is_empty():
		transcript += "[url=sources]Job reference history (%d)[/url]\n" % source_records.size()
	if sources_expanded:
		for index in range(source_records.size()):
			transcript += "[url=source:%d]%s[/url]\n" % [index, escape(source_records[index]["title"])]
	var plan: Dictionary = job.get("research", {}).get("plan", {})
	if plan.get("browser_url", "") != "":
		transcript += "\n[url=websearch]Search the web for this question[/url]\nBrowse results inside GopherTech. Answers are not automatically read or verified.\n"
	conversation.text = transcript

func on_link(meta: Variant) -> void:
	var value := str(meta)
	if value == "websearch":
		var url: String = job.get("research", {}).get("plan", {}).get("browser_url", "")
		if not url.is_empty():
			show_live_reference(url)
			set_status("Web search opened inside GopherTech. Browse the results below; automatic answers from these results are not available yet.")
	elif value.begins_with("evidence:"):
		open_reference(value.trim_prefix("evidence:"))
	elif value == "sources":
		sources_expanded = not sources_expanded
		render_conversation()
	elif value.begins_with("source:"):
		var index := value.trim_prefix("source:").to_int()
		if index >= 0 and index < source_records.size(): open_reference(source_records[index]["url"])
	elif value.begins_with("document:"):
		var index := value.trim_prefix("document:").to_int()
		var entries: Array = document.get("links", [])
		if index >= 0 and index < entries.size(): open_reference(entries[index]["url"])
	elif value == "external" and document.has("url"):
		OS.shell_open(document["url"])
	elif value == "livepage":
		var url: String = live_browser.current_url if not live_browser.current_url.is_empty() else document.get("url", "")
		if not url.is_empty(): show_live_reference(url)

func show_document(value: Dictionary) -> void:
	document = value
	document_reader.text = value.get("text", "").replace("\f", "\n\n──────── Next PDF page ────────\n\n")
	document_reader.scroll_vertical = 0
	document_reader.scroll_horizontal = 0
	document_header.text = escape(value.get("url", "")) + "\n" + escape(value.get("notice", "")) + "\n[url=external]Optional: open external copy[/url]"
	if DisplayServer.get_name() != "headless" and value.get("format") != "pdf":
		document_header.text += "\n[url=livepage]View live webpage here[/url]"
	document_links.text = "[b]Related document links[/b] — confirm model, serial range and region.\n"
	var entries: Array = value.get("links", [])
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		document_links.text += "[url=document:%d]%s[/url] %s\n" % [index, escape(entry.get("title", "Document")), escape(entry.get("applicability", ""))]
	document_panel.visible = true
	document_reader.visible = true
	document_links.visible = true
	if DisplayServer.get_name() != "headless" and value.get("format") != "pdf":
		show_live_reference(value.get("url", ""))
	else:
		live_browser.reset()
	pdf_controls.visible = value.get("format") == "pdf"
	pdf_image.visible = false
	pdf_page.value = 1
	reference_ready.emit(document_panel)

func show_live_reference(url: String) -> void:
	document_panel.visible = true
	document_header.text = "[url=livepage]Live webpage[/url] · Click links and scroll within the page."
	var opened: bool = live_browser.open_url(url)
	document_reader.visible = not opened
	document_links.visible = not opened
	pdf_controls.visible = false
	pdf_image.visible = false
	reference_ready.emit(document_panel)

func fit_pdf_page() -> void:
	if pdf_image.texture == null: return
	var image_size := pdf_image.texture.get_size()
	if image_size.x > 0:
		pdf_image.custom_minimum_size.y = maxf(100.0, pdf_image.size.x * image_size.y / image_size.x)

func on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	lock_editors(false)
	ask_button.disabled = false
	ask_button.text = "Ask GopherTech"
	var parser := JSON.new()
	var data: Variant = null
	if parser.parse(body.get_string_from_utf8()) == OK: data = parser.data
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300 or not data is Dictionary:
		if operation == "state":
			in_flight_state.merge(pending_state, true)
			pending_state = in_flight_state.duplicate(true)
		set_status("Request not confirmed. Questions and unsaved edits are kept here. Check the backend and retry; no success or search result is assumed.")
		if data is Dictionary and data.get("detail") is String: set_status(data["detail"])
		if code == 404 and data is Dictionary and data.get("detail") == "Not Found":
			set_status("Restart run_backend.sh to load saved-job support. Your question is kept here.")
		save_notice.emit("Changes are not confirmed saved. Reconnect the backend and retry.")
		return
	if sections_enabled and operation in ["question", "open", "create", "state"] and not data.get("section_drafts") is Dictionary:
		if operation == "state":
			in_flight_state.merge(pending_state, true)
			pending_state = in_flight_state.duplicate(true)
		set_status("Restart the backend to enable section saving. Your unsaved entries are kept here; saving is not confirmed.")
		return
	if operation in ["question", "open", "create", "state"] and (not data.get("id") is String or not data.get("messages") is Array):
		if operation == "state":
			in_flight_state.merge(pending_state, true)
			pending_state = in_flight_state.duplicate(true)
		set_status("Incomplete saved-job reply. Your question and unsaved changes are kept; retry before closing.")
		return
	if operation in ["startup", "list"]:
		jobs = data.get("jobs", [])
		job_list.clear()
		render_jobs()
		set_status("Ready · Local work orders. Reference mode; connected AI is not enabled yet.")
		if operation == "startup":
			question.grab_focus()
	elif operation == "archive":
		new_job()
		set_status("Conversation archived in the database with messages, notes, parts and saved references.")
	elif operation == "pdf":
		var image := Image.new()
		if image.load_png_from_buffer(Marshalls.base64_to_raw(data.get("png_base64", ""))) == OK:
			pdf_image.texture = ImageTexture.create_from_image(image)
			pdf_image.visible = true
			fit_pdf_page()
			reference_ready.emit(pdf_image)
			set_status("PDF page loaded.")
		else:
			set_status("The page image could not be verified. Previous content is kept.")
	elif operation == "reference":
		if not data.get("job") is Dictionary or not data.get("document") is Dictionary or not data["document"].get("text") is String:
			set_status("Incomplete reference reply. Previous content is kept.")
			return
		if not apply_job(data["job"]): return
		show_document(data["document"])
		set_status("Opened saved reference copy; it has not been refreshed. Check model, region and revision." if data.get("cached", false) else "Reference read and saved with this job. Check model, serial range and region.")
	else:
		if not apply_job(data): return
		set_status("Saved · " + str(job.get("title", "Workshop job")) + " · Source research.")
		if operation == "question":
			if question.text.strip_edges() == submitted_question: question.text = ""
			request_key = ""
			document_panel.visible = false
			live_browser.reset()
			answer_ready.emit()
		if operation == "state":
			in_flight_state.clear()
			save_notice.emit("Notes and parts saved with the current job.")
		if operation == "create":
			create_key = ""
			creation_body = {}
			order_number.text = ""

	call_deferred("drain")

func render_jobs() -> void:
	job_list.clear()
	displayed_jobs.clear()
	var query := order_search.text.strip_edges().to_lower()
	for entry in jobs:
		var description: String = str(entry.get("machine_description", "")).strip_edges()
		var title: String = entry.get("title", "")
		if description.is_empty(): description = title if title not in ["Work order", "Workshop job", "Workshop notes / parts"] else "Machine details not entered"
		var caption: String = order_label(entry) + " · " + description.left(110)
		var searchable: String = caption + " " + str(entry.get("work_order_number", "")) + " " + description + " " + title
		if not query.is_empty() and not query in searchable.to_lower(): continue
		displayed_jobs.append(entry)
		job_list.add_item(caption + "  ·  " + entry["updated_at"].substr(0, 10), load("res://assets/gophertech-logo.png"))
	for index in range(job_list.item_count): job_list.set_item_tooltip(index, job_list.get_item_text(index))
	job_list.add_theme_constant_override("v_separation", 18)

func create_order(machine_description: String = "") -> void:
	if busy and operation == "create": return
	before_switch.emit()
	if not notes_timer.is_stopped():
		notes_timer.stop()
		pending_state.merge(collect_notes(), true)
	var body := {"title":"Work order", "machine_description":machine_description.strip_edges()}
	if not order_number.text.strip_edges().is_empty(): body["work_order_number"] = order_number.text.strip_edges()
	pending_open = ""
	if busy or not pending_state.is_empty():
		pending_creation = body
		flush_state()
		set_status("Saving the current work order before opening the new one…")
		return
	start_order(body)

func start_order(body: Dictionary) -> void:
	if creation_body != body:
		create_key = key()
		creation_body = body.duplicate()
	if create_key.is_empty(): create_key = key()
	var payload := body.duplicate()
	payload["request_key"] = create_key
	set_status("Creating work order…")
	send("create", "/jobs", payload)

func lock_editors(locked: bool) -> void:
	notes.editable = not locked
	question.editable = not locked
	if has_meta("machine_input"): get_meta("machine_input").editable = not locked

func order_label(record: Dictionary) -> String:
	var number: String = record.get("work_order_number", "Work order")
	var id: String = record.get("id", "")
	return "WO-" + id.left(8).to_upper() if number == "WO-" + id and not id.is_empty() else number

func collect_notes() -> Dictionary:
	if not sections_enabled: return {"notes":notes.text}
	var section: Dictionary = section_drafts.get(active_section, {"task":"", "notes":""}).duplicate()
	section["notes"] = notes.text
	section_drafts[active_section] = section
	section_dirty = false
	var payload := {"section_drafts":section_drafts.duplicate(true)}
	# Preserve the pre-section notes API as the Parts notes for old clients.
	if section_drafts.has("parts"): payload["notes"] = section_drafts["parts"].get("notes", "")
	return payload

func set_section_task(value: String) -> void:
	if applying or not sections_enabled: return
	var section: Dictionary = section_drafts.get(active_section, {"task":"", "notes":""}).duplicate()
	section["task"] = value
	section_drafts[active_section] = section
	section_dirty = true
	notes_timer.start()

func switch_section(key: String) -> void:
	if key not in ["parts", "diagnose", "repair", "fabricate"] or key == active_section: return
	if key != active_section and (section_dirty or not notes_timer.is_stopped()):
		notes_timer.stop()
		save_state(collect_notes())
	active_section = key
	applying = true
	notes.text = section_drafts.get(key, {}).get("notes", "")
	applying = false
