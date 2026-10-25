extends SceneTree

var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func idle(desk: Node) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while desk.busy and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	check(not desk.busy, "reference request completed")

func run() -> void:
	var shop = load("res://shop_dashboard.tscn").instantiate()
	root.add_child(shop)
	shop.show_page("references")
	var desk = shop.reference_desk
	await idle(desk)
	check("paused" in desk.ai_status.text, "paid AI stays paused")
	desk.query.text = "Honda GX160 manual"
	desk.find_sources()
	await idle(desk)
	check(desk.source_list.item_count > 0, "manufacturer directory loads in app")
	if desk.source_list.item_count == 0:
		quit(1)
		return
	desk.source_list.select(0)
	desk.read_selected_source()
	await idle(desk)
	check("Reference integration fixture" in desk.reader.text, "source text arrives through real HTTP")
	check(desk.links.item_count == 1, "supported document links arrive")
	if desk.links.item_count == 0:
		quit(1)
		return
	desk.links.select(0)
	desk.read_selected_link()
	await idle(desk)
	check(desk.document_format == "pdf", "linked PDF stays in app")
	check("GopherTech test diagram" in desk.reader.text, "PDF text extraction reaches Godot")
	desk.view_pdf_page()
	await idle(desk)
	check(desk.page_image.visible and desk.page_image.texture != null, "PDF layout image reaches Godot")
	desk.question_notes.text = "Keep this question while changing pages"
	shop.show_page("home")
	shop.show_page("references")
	check(desk.question_notes.text.begins_with("Keep"), "question pad survives navigation")
	var previous: String = desk.document_text
	desk.api_url = "http://127.0.0.1:1"
	desk.read_document("https://engines.honda.com/offline-test")
	await idle(desk)
	check(desk.document_text == previous, "connection failure preserves document")
	check("Previous content" in desk.message.text, "offline status is explicit")
	print("Reference integration: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	shop.queue_free()
	quit(0 if failures == 0 else 1)
