extends SceneTree
## Interface-only acceptance checks. No new research or AI behavior is exercised.

var failures := 0

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var shop = load("res://shop_dashboard.tscn").instantiate()
	root.add_child(shop)
	var work = shop.job_workspace
	work.request_node.cancel_request()
	work.busy = false
	work.ask_button.disabled = false
	check(shop.active_page == "home", "opens directly to quick search")
	check(work.question is TextEdit and work.ask_button.text == "Ask GopherTech", "one obvious input and ask action")
	check(shop.nav_grid.get_child_count() == 4, "four direct touch navigation buttons")
	work.apply_job({"id":"ui-fixture", "notes":"", "parts":[], "sources":[{"title":"Original UI fixture source","url":"https://engines.honda.com/fixture","read":false}], "messages":[{"id":1,"role":"assistant","content":"Check the identification plate first.\n\nExtra technical explanation.\n\nDo not bypass safety interlocks.\n\nWhat model is it?"}]})
	check(not "Technical details" in work.conversation.text, "routine technical links removed")
	check("Do not bypass" in work.conversation.text, "safety text remains visible")
	check(not "Original UI fixture source" in work.conversation.text, "job reference history starts collapsed")
	work.on_link("sources")
	check("Original UI fixture source" in work.conversation.text, "old job references remain accessible")
	var sourced := "I could not verify the spark plug.\n\nWhat is the full model designation?"
	work.apply_job({"id":"ui-fixture", "notes":"", "parts":[], "sources":[], "messages":[{"id":1,"role":"user","content":"GX160 manual"},{"id":2,"role":"assistant","content":"Reference found.","evidence":[{"title":"GX160 manual","url":"https://engines.honda.com/fixture"}]},{"id":3,"role":"user","content":"TRX200 spark plug"},{"id":4,"role":"assistant","content":sourced}]})
	check(work.conversation.text.count("View source:") == 1, "only the supported exchange has a source action")
	check(work.conversation.text.find("View source:") < work.conversation.text.find("TRX200 spark plug"), "old evidence stays with its exchange")
	check("────────────────────────" in work.conversation.text, "exchanges have visible separation")
	work.operation = "question"
	work.submitted_question = "Original submitted question"
	work.question.text = "A new draft typed while waiting"
	var reply := {"id":"ui-fixture", "section_drafts":{}, "title":"Fixture", "notes":"", "parts":[], "sources":[], "messages":[{"id":3,"role":"assistant","content":sourced}]}
	work.on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(reply).to_utf8_buffer())
	check(work.question.text == "A new draft typed while waiting", "incoming answer preserves a newer draft")
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	check(shop.page_scroll.scroll_vertical >= 0, "answer scrolling completes without errors")
	shop.show_page("home")
	await process_frame
	work.show_document({"url":"https://engines.honda.com/fixture.pdf", "format":"pdf", "text":"Fixture page one\fFixture page two", "links":[]})
	check("Next PDF page" in work.document_reader.text, "PDF text retains visible page boundaries")
	check(work.document_reader.scroll_vertical == 0, "new document starts at the beginning")
	var page_image := Image.create(600, 900, false, Image.FORMAT_RGB8)
	work.pdf_image.texture = ImageTexture.create_from_image(page_image)
	work.pdf_image.visible = true
	await process_frame
	work.fit_pdf_page()
	check(absf(work.pdf_image.custom_minimum_size.y - work.pdf_image.size.x * 1.5) < 1.0, "PDF height follows its aspect ratio rather than a fixed desktop height")
	for key in shop.navigation:
		shop.nav_grid.get_child(shop.navigation.keys().find(key)).pressed.emit()
		check(shop.active_page == key, "touch button opens " + key)
	for choice in shop.TOOL_CHOICES:
		shop.show_page(choice[0])
		check(shop.pages[choice[0]].is_visible_in_tree(), "preserved secondary tool: " + choice[0])
	shop.show_page("home")
	root.size = Vector2i(390, 844)
	await process_frame
	await process_frame
	check(shop.size.x <= 390, "portrait layout uses actual phone-sized width")
	check(work.question.size.x <= 390, "question input fits portrait width")
	check(work.ask_button.size.y >= 44 and shop.nav_grid.get_child(0).size.y >= 44, "main touch targets remain usable")
	root.size = Vector2i(360, 800)
	await process_frame
	await process_frame
	check(work.question.size.x <= 360 and shop.nav_grid.get_global_rect().end.x <= 360, "compact header and input fit a narrow portrait screen")
	print("Work order interface: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	shop.queue_free()
	quit(0 if failures == 0 else 1)
