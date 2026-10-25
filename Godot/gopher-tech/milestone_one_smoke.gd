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
	check(shop.active_page == "home", "opens directly to question workflow")
	check(work.question is TextEdit and work.ask_button.text == "Ask GopherTech", "one obvious input and ask action")
	check(shop.menu_button.get_popup().item_count == 3, "history and tools live in a compact menu")
	work.apply_job({"id":"ui-fixture", "notes":"", "parts":[], "sources":[{"title":"Original UI fixture source","url":"https://engines.honda.com/fixture","read":false}], "messages":[{"id":1,"role":"assistant","content":"Check the identification plate first.\n\nExtra technical explanation.\n\nDo not bypass safety interlocks.\n\nWhat model is it?"}]})
	check(not "Extra technical" in work.conversation.text, "long detail starts collapsed")
	check("Do not bypass" in work.conversation.text, "important safety text remains visible")
	work.on_link("detail:1")
	check("Extra technical" in work.conversation.text, "technical details expand on request")
	work.on_link("detail:1")
	check(not "Extra technical" in work.conversation.text, "technical details collapse again")
	check(not "Original UI fixture source" in work.conversation.text, "supporting sources start collapsed")
	work.on_link("sources")
	check("Original UI fixture source" in work.conversation.text, "supporting sources remain accessible")
	for key in shop.navigation:
		shop.menu_button.get_popup().id_pressed.emit(shop.navigation.keys().find(key))
		check(shop.active_page == key, "menu opens " + key)
	for choice in shop.TOOL_CHOICES:
		shop.show_page(choice[0])
		check(shop.pages[choice[0]].is_visible_in_tree(), "preserved secondary tool: " + choice[0])
	shop.show_page("home")
	root.size = Vector2i(390, 844)
	await process_frame
	await process_frame
	check(shop.size.x <= 390, "portrait layout uses actual phone-sized width")
	check(work.question.size.x <= 390, "question input fits portrait width")
	check(work.ask_button.size.y >= 44 and shop.menu_button.size.y >= 44, "main touch targets remain usable")
	root.size = Vector2i(360, 800)
	await process_frame
	await process_frame
	check(work.question.size.x <= 360 and shop.menu_button.get_global_rect().end.x <= 360, "compact header and input fit a narrow portrait screen")
	print("Milestone 1 interface: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	shop.queue_free()
	quit(0 if failures == 0 else 1)
