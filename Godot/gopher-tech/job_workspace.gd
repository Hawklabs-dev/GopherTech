extends VBoxContainer
## Persistent reference-mode conversations. No model, credential or paid API calls.

signal job_loaded(job: Dictionary)
signal save_notice(value: String)
signal answer_ready

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
var expanded_details: Dictionary = {}
var sources_expanded := false

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
	question.placeholder_text = "Ask about a problem, part, manual or repair…"
	question.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	question.custom_minimum_size.y = 110
	add_child(question)
	ask_button = Button.new()
	ask_button.text = "Ask GopherTech"
	ask_button.custom_minimum_size.y = 54
	ask_button.pressed.connect(ask)
	add_child(ask_button)
	status = label(self, "Source research · Your work saves locally.", 13)
	conversation = rich(self, 160)
	conversation.text = "Ask in your own words. I’ll keep the useful details with this conversation."
	document_panel = VBoxContainer.new()
	document_panel.add_theme_constant_override("separation", 12)
	document_panel.visible = false
	add_child(document_panel)
	label(document_panel, "Reference document", 21)
	document_header = rich(document_panel, 50)
	document_reader = TextEdit.new()
	document_reader.editable = false
	document_reader.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	document_reader.custom_minimum_size.y = 350
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
	pdf_image.custom_minimum_size.y = 780
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
	send("startup", "/jobs", {}, HTTPClient.METHOD_GET)

func set_status(value: String) -> void:
	status.text = value
	if saved_status != null: saved_status.text = value

func send(kind: String, path: String, body: Dictionary = {}, method: int = HTTPClient.METHOD_POST) -> void:
	if busy: return
	operation = kind
	busy = true
	ask_button.disabled = true
	var error := request_node.request(api_url + path, ["Content-Type: application/json"], method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
	if error != OK:
		if kind == "state":
			in_flight_state.merge(pending_state, true)
			pending_state = in_flight_state.duplicate(true)
		busy = false
		ask_button.disabled = false
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
	document = {}
	question.text = ""
	applying = true
	notes.text = ""
	applying = false
	conversation.text = "Ask a question to start a saved conversation."
	document_panel.visible = false
	job_loaded.emit(job)
	set_status("New job • Reference mode (not AI).")

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
		expanded_details.clear()
		sources_expanded = false
	job = value
	for name in pending_state: job[name] = pending_state[name]
	applying = true
	notes.text = job.get("notes", "")
	applying = false
	source_records = job.get("sources", [])
	render_conversation()
	job_loaded.emit(job)

func brief_answer(value: String) -> String:
	var paragraphs := value.split("\n\n", false)
	if paragraphs.size() > 1 and paragraphs[0].begins_with("Keeping "):
		paragraphs.remove_at(0)
	if paragraphs.is_empty(): return value
	var selected := PackedStringArray([paragraphs[0]])
	for paragraph in paragraphs.slice(1):
		if paragraph.begins_with("Next ") or paragraph.begins_with("No matching ") or "Do not " in paragraph or "do not " in paragraph or paragraph.begins_with("Keep ignition") or "not verified engineering" in paragraph or paragraph.ends_with("?"):
			selected.append(paragraph)
	return "\n\n".join(selected)

func render_conversation() -> void:
	var transcript := ""
	for entry in job.get("messages", []):
		var id := str(entry["id"])
		var content: String = entry["content"]
		if entry["role"] == "assistant" and not expanded_details.get(id, false):
			content = brief_answer(content)
		transcript += "[color=#ffb347][b]%s[/b][/color]\n%s\n" % ["You" if entry["role"] == "user" else "GopherTech", escape(content)]
		if entry["role"] == "assistant":
			transcript += "[url=detail:%s][color=#a6b3c4]%s[/color][/url]\n" % [id, "Less detail" if expanded_details.get(id, false) else "Technical details"]
		transcript += "\n"
	if transcript.is_empty(): transcript = "Ask your question above to continue.\n\n"
	if not source_records.is_empty():
		transcript += "[url=sources]Sources & saved findings (%d)[/url]\n" % source_records.size()
	if sources_expanded:
		for index in range(source_records.size()):
			var entry: Dictionary = source_records[index]
			transcript += "[url=source:%d]%s[/url] · %s\n" % [index, escape(entry["title"]), "saved copy · " + str(entry.get("updated_at", "")).substr(0, 10) if entry.get("read", false) else "unverified reference location"]
	conversation.text = transcript

func on_link(meta: Variant) -> void:
	var value := str(meta)
	if value.begins_with("detail:"):
		var id := value.trim_prefix("detail:")
		expanded_details[id] = not expanded_details.get(id, false)
		render_conversation()
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

func show_document(value: Dictionary) -> void:
	document = value
	document_reader.text = value.get("text", "")
	document_header.text = escape(value.get("url", "")) + "\n" + escape(value.get("notice", "")) + "\n[url=external]Optional: open external copy[/url]"
	document_links.text = "[b]Related document links[/b] — confirm model, serial range and region.\n"
	var entries: Array = value.get("links", [])
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		document_links.text += "[url=document:%d]%s[/url] %s\n" % [index, escape(entry.get("title", "Document")), escape(entry.get("applicability", ""))]
	document_panel.visible = true
	pdf_controls.visible = value.get("format") == "pdf"
	pdf_image.visible = false
	pdf_page.value = 1

func on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	ask_button.disabled = false
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
		for entry in jobs: job_list.add_item(entry["title"] + "  •  " + entry["updated_at"].substr(0, 10))
		set_status("Reference mode (not AI). Jobs save to this computer.")
		if operation == "startup" and not jobs.is_empty():
			open_job(jobs[0]["id"])
			return
	elif operation == "pdf":
		var image := Image.new()
		if image.load_png_from_buffer(Marshalls.base64_to_raw(data.get("png_base64", ""))) == OK:
			pdf_image.texture = ImageTexture.create_from_image(image)
			pdf_image.visible = true
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
			question.text = ""
			request_key = ""
			document_panel.visible = false
			answer_ready.emit()
		if operation == "state":
			in_flight_state.clear()
			save_notice.emit("Notes and parts saved with the current job.")
		if operation == "create": create_key = ""
	call_deferred("drain")
