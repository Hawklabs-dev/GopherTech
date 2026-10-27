extends VBoxContainer
## Persistent conversations with source research and optional local passage selection.

signal job_loaded(job: Dictionary)
signal save_notice(value: String)
signal answer_ready
signal reference_ready(control: Control)

var saved_view: VBoxContainer
var question: TextEdit
var ask_button: Button
var status: Label
var saved_status: Label
var conversation: RichTextLabel
var job_list: ItemList
var notes: TextEdit
var notes_timer: Timer
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
	var archive := Button.new()
	archive.text = "Archive conversation & start new"
	archive.pressed.connect(func():
		if busy or not pending_state.is_empty() or not notes_timer.is_stopped():
			flush_state()
			set_status("Wait for saving to finish, then archive.")
			return
		if job.has("id"): send("archive", "/jobs/" + job["id"] + "/archive")
	)
	add_child(archive)
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
	label(saved_view, "Pick up a conversation, with its notes and saved references.")
	job_list = ItemList.new()
	job_list.custom_minimum_size.y = 240
	job_list.item_activated.connect(func(index: int): open_job(jobs[index]["id"]))
	saved_view.add_child(job_list)
	var open := Button.new()
	open.text = "Continue selected conversation"
	open.custom_minimum_size.y = 46
	open.pressed.connect(func():
		var selected := job_list.get_selected_items()
		if not selected.is_empty(): open_job(jobs[selected[0]]["id"])
	)
	saved_view.add_child(open)
	var fresh := Button.new()
	fresh.text = "New conversation"
	fresh.custom_minimum_size.y = 46
	fresh.pressed.connect(new_job)
	saved_view.add_child(fresh)
	label(saved_view, "Conversation notes — saved automatically", 18)
	notes = TextEdit.new()
	notes.placeholder_text = "Observations, measurements and things already checked"
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes.custom_minimum_size.y = 180
	saved_view.add_child(notes)
	saved_status = label(saved_view, "Notes save automatically when the backend is connected.")
	notes_timer = Timer.new()
	notes_timer.one_shot = true
	notes_timer.wait_time = 0.8
	notes_timer.timeout.connect(func(): save_state({"notes":notes.text}))
	add_child(notes_timer)
	notes.text_changed.connect(func():
		if not applying: notes_timer.start()
	)
	request_node = HTTPRequest.new()
	request_node.timeout = 90.0
	request_node.body_size_limit = 16 * 1024 * 1024
	request_node.request_completed.connect(on_response)
	add_child(request_node)
	send("startup", "/jobs?include_archived=false", {}, HTTPClient.METHOD_GET)

func set_status(value: String) -> void:
	status.text = value
	if saved_status != null: saved_status.text = value

func send(kind: String, path: String, body: Dictionary = {}, method: int = HTTPClient.METHOD_POST) -> void:
	if busy: return
	operation = kind
	busy = true
	request_node.timeout = 20.0 if kind == "question" else 5.0 if kind in ["startup", "list", "open", "state", "create", "archive"] else 45.0
	ask_button.disabled = true
	if kind == "question": ask_button.text = "Finding useful information…"
	var error := request_node.request(api_url + path, ["Content-Type: application/json"], method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
	if error != OK:
		if kind == "state":
			in_flight_state.merge(pending_state, true)
			pending_state = in_flight_state.duplicate(true)
		busy = false
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
	if busy or not pending_state.is_empty() or not notes_timer.is_stopped():
		notes_timer.stop()
		if not applying: pending_state["notes"] = notes.text
		pending_open = id
		flush_state()
		return
	send("open", "/jobs/" + id, {}, HTTPClient.METHOD_GET)

func new_job() -> void:
	if busy or not pending_state.is_empty() or not notes_timer.is_stopped():
		set_status("Let the current job finish saving before starting another.")
		flush_state()
		return
	job = {}
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
	elif not pending_open.is_empty():
		var id := pending_open
		pending_open = ""
		open_job(id)
	elif not pending_reference.is_empty() and job.has("id"):
		var url := pending_reference
		pending_reference = ""
		set_status("Reading and saving the reference…")
		send("reference", "/jobs/" + job["id"] + "/reference", {"url":url})

func apply_job(value: Dictionary) -> void:
	if not notes_timer.is_stopped():
		notes_timer.stop()
		pending_state["notes"] = notes.text
	if job.get("id", "") != value.get("id", ""):
		document = {}
		document_panel.visible = false
		live_browser.reset()
		sources_expanded = false
	job = value
	for name in pending_state: job[name] = pending_state[name]
	applying = true
	notes.text = job.get("notes", "")
	applying = false
	source_records = job.get("sources", [])
	render_conversation()
	job_loaded.emit(job)

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
	if operation in ["question", "open", "create", "state"] and (not data.get("id") is String or not data.get("messages") is Array):
		if operation == "state":
			in_flight_state.merge(pending_state, true)
			pending_state = in_flight_state.duplicate(true)
		set_status("Incomplete saved-job reply. Your question and unsaved changes are kept; retry before closing.")
		return
	if operation in ["startup", "list"]:
		jobs = data.get("jobs", [])
		job_list.clear()
		for entry in jobs: job_list.add_item(("[Archived] " if entry.get("archived_at") != null else "") + entry["title"] + "  •  " + entry["updated_at"].substr(0, 10))
		set_status("Ready · Ask a question. Reference mode; automatic web answers are not available.")
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
		apply_job(data["job"])
		show_document(data["document"])
		set_status("Opened saved reference copy; it has not been refreshed. Check model, region and revision." if data.get("cached", false) else "Reference read and saved with this job. Check model, serial range and region.")
	else:
		apply_job(data)
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
		if operation == "create": create_key = ""
	call_deferred("drain")
