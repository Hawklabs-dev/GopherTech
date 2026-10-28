extends VBoxContainer
## No browser launches, paid APIs or automatic purchases.

signal focus_requested(control: Control)
signal document_loaded(url: String)

var api_url := "http://127.0.0.1:8000"
var request_node: HTTPRequest
var operation := "status"
var busy := false
var search_pending := false
var query: LineEdit
var source_list: ItemList
var source_records: Array = []
var links: ItemList
var link_records: Array = []
var url_input: LineEdit
var message: Label
var provenance: Label
var notice: Label
var reader: TextEdit
var document_text := ""
var document_url := ""
var document_format := ""
var find_text: LineEdit
var page_number: SpinBox
var page_image: TextureRect
var page_caption: Label
var question_notes: TextEdit
var ai_status: Label
var buttons: Array[Button] = []

func label(value: String, size: int = 16) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", size)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(node)
	return node

func button(value: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = value
	node.custom_minimum_size.y = 46
	node.pressed.connect(callback)
	add_child(node)
	buttons.append(node)
	return node

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var configured := OS.get_environment("GOPHERTECH_API_URL").strip_edges().trim_suffix("/")
	if not configured.is_empty():
		api_url = configured
	label("MANUALS • PARTS LISTS • DRAWINGS", 21)
	label("Browse manufacturer references inside GopherTech. This is a curated source directory, not a live whole-web search. Confirm engine model, serial range and region.", 15)
	query = LineEdit.new()
	query.placeholder_text = "Brand, model or document type — for example Honda GX160 manual"
	query.max_length = 600
	query.custom_minimum_size.y = 46
	query.text_submitted.connect(func(_value: String): find_sources())
	add_child(query)
	button("Find reference sources", find_sources)
	source_list = ItemList.new()
	source_list.custom_minimum_size.y = 175
	add_child(source_list)
	button("Read selected source in app", read_selected_source)
	label("Or paste a supported manufacturer HTML / PDF link", 14)
	url_input = LineEdit.new()
	url_input.placeholder_text = "https://… (Honda, Briggs & Stratton, Briggs Racing or Vanguard)"
	url_input.max_length = 2000
	url_input.custom_minimum_size.y = 46
	url_input.text_submitted.connect(func(_value: String): read_url())
	add_child(url_input)
	button("Read pasted link in app", read_url)
	message = label("Start the Python backend to use the reference reader. No API key or paid service is used.", 15)
	provenance = label("No document loaded.", 14)
	notice = label("Public documents are fetched only when you choose to read them. No login, scripts, shopping or payment actions are performed.", 14)
	find_text = LineEdit.new()
	find_text.placeholder_text = "Find words in this document (clear to restore full text)"
	find_text.text_changed.connect(filter_document)
	find_text.custom_minimum_size.y = 46
	add_child(find_text)
	reader = TextEdit.new()
	reader.editable = false
	reader.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	reader.custom_minimum_size.y = 340
	reader.placeholder_text = "Manufacturer text will appear here."
	add_child(reader)
	button("Back to reference sources", func(): focus_requested.emit(query))
	button("Copy document URL", func():
		if not document_url.is_empty():
			DisplayServer.clipboard_set(document_url)
			message.text = "Source URL copied."
	)
	label("SUPPORTED LINKS ON THIS PAGE", 14)
	links = ItemList.new()
	links.custom_minimum_size.y = 170
	add_child(links)
	button("Read selected document link", read_selected_link)
	label("PDF diagrams and page layout", 20)
	label("For PDF documents, choose a page from 1 to 60 to view the original layout. Text extraction alone does not preserve diagrams.", 14)
	page_number = SpinBox.new()
	page_number.min_value = 1
	page_number.max_value = 60
	page_number.value = 1
	page_number.custom_minimum_size.y = 46
	add_child(page_number)
	button("View PDF page in app", view_pdf_page)
	page_caption = label("No PDF page loaded.", 14)
	page_image = TextureRect.new()
	page_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	page_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	page_image.custom_minimum_size.y = 780
	page_image.visible = false
	add_child(page_image)
	ai_status = label("AI is paused. Use Job Details for the shared notes and research workspace.", 14)
	request_node = HTTPRequest.new()
	request_node.timeout = 30.0
	request_node.body_size_limit = 16 * 1024 * 1024
	request_node.request_completed.connect(on_response)
	add_child(request_node)
	start_request("status", "/research/status", {}, HTTPClient.METHOD_GET)

func set_busy(value: bool) -> void:
	busy = value
	for node in buttons:
		node.disabled = value
	source_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
	links.mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
	url_input.editable = not value
	query.editable = not value
	page_number.editable = not value

func start_request(kind: String, path: String, payload: Dictionary, method: int = HTTPClient.METHOD_POST) -> void:
	if busy:
		return
	operation = kind
	set_busy(true)
	var error := request_node.request(api_url + path, ["Content-Type: application/json"], method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(payload))
	if error != OK:
		set_busy(false)
		message.text = "Could not start the connection. Start the backend and try again. Previous content is kept."

func find_sources() -> void:
	if busy:
		search_pending = true
		return
	message.text = "Finding manufacturer reference sources…"
	start_request("sources", "/research/sources", {"query": query.text.strip_edges()})

func read_selected_source() -> void:
	var selected := source_list.get_selected_items()
	if not selected.is_empty() and selected[0] < source_records.size():
		read_document(source_records[selected[0]]["url"])
	else:
		message.text = "Select a manufacturer source first."

func read_selected_link() -> void:
	var selected := links.get_selected_items()
	if not selected.is_empty() and selected[0] < link_records.size():
		read_document(link_records[selected[0]]["url"])
	else:
		message.text = "Select a document link first."

func read_url() -> void:
	read_document(url_input.text.strip_edges())

func read_document(url: String) -> void:
	if busy:
		return
	if url.is_empty():
		message.text = "Paste or select a supported manufacturer URL first."
		return
	message.text = "Reading manufacturer document…"
	start_request("document", "/research/document", {"url": url})

func view_pdf_page() -> void:
	if busy:
		return
	if document_format != "pdf":
		message.text = "Read a PDF document first, then choose a page."
		return
	message.text = "Rendering PDF page…"
	start_request("page", "/research/pdf-page", {"url": document_url, "page": int(page_number.value)})

func filter_document(value: String) -> void:
	if value.strip_edges().is_empty():
		reader.text = document_text
		return
	var rows := document_text.split("\n")
	var matches := PackedStringArray()
	for index in range(rows.size()):
		if value.to_lower() in rows[index].to_lower():
			matches.append("Line %d: %s" % [index + 1, rows[index]])
	reader.text = "Filtered text — clear the find box to restore the full document.\n\n" + ("\n\n".join(matches) if not matches.is_empty() else "No matching text. Try another word or inspect PDF page images.")

func on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	set_busy(false)
	if search_pending:
		search_pending = false
		call_deferred("find_sources")
	var parser := JSON.new()
	var data: Variant = null
	if parser.parse(body.get_string_from_utf8()) == OK:
		data = parser.data
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		message.text = "Could not read this reference. Start the backend or check your connection. Previous content is kept."
		if data is Dictionary and data.get("detail") is String:
			message.text = data["detail"] + " Previous content is kept."
		return
	if not data is Dictionary:
		message.text = "Unexpected server reply. Previous content is kept."
		return
	if operation == "status":
		message.text = "Reference reader connected."
		ai_status.text = data.get("ai_reason", "AI is paused.") + " No AI answer is generated."
	elif operation == "sources":
		if not data.get("sources") is Array:
			message.text = "The source directory could not be read."
			return
		source_records = data["sources"]
		source_list.clear()
		for source in source_records:
			source_list.add_item(source.get("title", "Reference"))
			source_list.set_item_tooltip(source_list.item_count - 1, source.get("description", "") + "\n" + source.get("url", ""))
		message.text = data.get("message", "Sources ready.")
	elif operation == "document":
		if not data.get("text") is String or not data.get("links") is Array or not data.get("url") is String:
			message.text = "The document reply was incomplete. Previous content is kept."
			return
		document_url = data["url"]
		document_format = data.get("format", "text")
		document_text = data["text"]
		provenance.text = "SOURCE: " + document_url
		notice.text = data.get("notice", "")
		url_input.text = document_url
		filter_document(find_text.text)
		link_records = data["links"]
		links.clear()
		for link in link_records:
			links.add_item(link.get("title", "Document link"))
			links.set_item_tooltip(links.item_count - 1, link.get("url", ""))
		page_image.visible = false
		page_image.texture = null
		page_number.value = 1
		page_caption.text = "No PDF page loaded."
		message.text = "Reference loaded in app. Confirm the exact model and document applicability."
		focus_requested.emit(reader)
		document_loaded.emit(document_url)
	elif operation == "page":
		if not data.get("png_base64") is String:
			message.text = "The page image was not available."
			return
		var image := Image.new()
		if image.load_png_from_buffer(Marshalls.base64_to_raw(data["png_base64"])) != OK:
			message.text = "The PDF page image could not be read."
			return
		page_image.texture = ImageTexture.create_from_image(image)
		page_image.visible = true
		page_caption.text = "PDF page %d • %s" % [int(data.get("page", 1)), document_url]
		message.text = "PDF page loaded below. Diagrams are original document images, not AI-generated instructions."
		focus_requested.emit(page_image)

func capture_workspace() -> Dictionary:
	return {"query":query.text, "url_input":url_input.text, "document_text":document_text,
		"document_url":document_url, "document_format":document_format, "reader":reader.text,
		"find":find_text.text, "reader_scroll":reader.scroll_vertical,
		"sources":source_records.duplicate(true), "links":link_records.duplicate(true),
		"provenance":provenance.text, "message":message.text, "notice":notice.text,
		"page":page_number.value, "image":page_image.texture, "image_visible":page_image.visible,
		"page_caption":page_caption.text}

func restore_workspace(snapshot: Dictionary) -> void:
	# Never let a previous machine's outstanding response attach to the new job.
	request_node.cancel_request()
	set_busy(false)
	search_pending = false
	query.text = snapshot.get("query", "")
	url_input.text = snapshot.get("url_input", "")
	document_text = snapshot.get("document_text", "")
	document_url = snapshot.get("document_url", "")
	document_format = snapshot.get("document_format", "")
	find_text.text = snapshot.get("find", "")
	reader.text = snapshot.get("reader", "")
	reader.scroll_vertical = snapshot.get("reader_scroll", 0)
	source_records = snapshot.get("sources", []).duplicate(true)
	link_records = snapshot.get("links", []).duplicate(true)
	source_list.clear()
	links.clear()
	for entry in source_records: source_list.add_item(entry.get("title", entry.get("url", "Reference")))
	for entry in link_records: links.add_item(entry.get("title", entry.get("url", "Document")))
	provenance.text = snapshot.get("provenance", "No document loaded for this work order.")
	message.text = snapshot.get("message", "Find references for this work order.")
	notice.text = snapshot.get("notice", "Check model, serial range and applicability.")
	page_number.value = snapshot.get("page", 1)
	page_image.texture = snapshot.get("image")
	page_image.visible = snapshot.get("image_visible", false)
	page_caption.text = snapshot.get("page_caption", "No PDF page loaded.")
