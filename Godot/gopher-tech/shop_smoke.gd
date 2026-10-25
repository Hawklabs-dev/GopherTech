extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var dashboard = load("res://shop_dashboard.tscn").instantiate()
	root.add_child(dashboard)
	await process_frame
	check(dashboard.active_page == "home", "home is the entry point")
	check(dashboard.pages.size() == 13, "three main pages preserve all ten tools")
	check(dashboard.navigation.size() == 3, "only three main navigation choices")
	check(dashboard.job_workspace.question != null, "main screen has a large question input")
	check(dashboard.pages["home"].visible, "home starts visible")
	check(not dashboard.pages["equipment"].visible, "equipment registration is optional")
	for key in dashboard.navigation:
		dashboard.menu_button.get_popup().id_pressed.emit(dashboard.navigation.keys().find(key))
		check(dashboard.active_page == key, "navigation opens " + key)
		var visible_pages := 0
		for page in dashboard.pages.values():
			visible_pages += int(page.is_visible_in_tree())
		check(visible_pages == (2 if key == "tools" else 1), "only selected main page and tool are visible")
	for key in ["parts", "diagnose", "repair", "fabricate"]:
		check(not dashboard.prepare_research(key), "blank request blocked")
		dashboard.research_forms[key]["inputs"]["task"].text = "Carburetor & gasket #123"
		check(dashboard.prepare_research(key), "standalone request needs no model/profile")
		check("Carburetor & gasket #123" in dashboard.research_forms[key]["output"].text, "brief retains request")
		check("Carburetor & gasket #123" in dashboard.search_query(key, dashboard.form_values(key)), "query retains task details")
	var desk = dashboard.reference_desk
	desk.request_node.cancel_request()
	desk.set_busy(false)
	desk.operation = "document"
	desk.on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"text": "Engine manual\nDiagram on page 4\nCheck model applicability", "url": "https://engines.honda.com/manual", "format": "html", "links": [{"title": "Manual PDF", "url": "https://cdn.powerequipment.honda.com/manual.pdf"}]}).to_utf8_buffer())
	check("Engine manual" in desk.reader.text, "manufacturer text displayed in app")
	check(desk.links.item_count == 1, "document links displayed")
	desk.filter_document("diagram")
	check("Diagram on page 4" in desk.reader.text and not "Engine manual" in desk.reader.text, "document find filters text")
	desk.filter_document("")
	check("Engine manual" in desk.reader.text, "clearing find restores source")
	desk.on_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	check("Engine manual" in desk.reader.text, "failed reference load preserves previous text")
	desk.question_notes.text = "Keep my question"
	dashboard.open_research("parts")
	check(dashboard.active_page == "tools" and dashboard.active_tool == "references", "research stays inside Tools")
	check(desk.question_notes.text == "Keep my question", "new research does not overwrite questions")
	desk.request_node.cancel_request()
	desk.set_busy(false)
	dashboard.add_part()
	dashboard.add_part()
	check(dashboard.parts.size() == 1, "identical parts are not added twice")
	dashboard.show_page("home")
	dashboard.show_page("parts")
	check(dashboard.research_forms["parts"]["inputs"]["task"].text == "Carburetor & gasket #123", "navigation retains work")
	dashboard.conversion_input.text = "1"
	dashboard.conversion_kind.select(0)
	dashboard.convert_units()
	check("25.4000 mm" in dashboard.conversion_result.text, "inch to millimetre conversion")
	dashboard.conversion_kind.select(2)
	dashboard.convert_units()
	check("1.3558 N" in dashboard.conversion_result.text, "foot-pound torque conversion")
	dashboard.conversion_input.text = "-1"
	dashboard.convert_units()
	check("Enter" in dashboard.conversion_result.text, "negative value rejected")
	dashboard.mix_fuel.text = "5"
	dashboard.mix_ratio.text = "50"
	dashboard.calculate_mix()
	check("100.00 mL" in dashboard.mix_result.text, "fuel mix arithmetic")
	dashboard.mix_ratio.text = "0"
	dashboard.calculate_mix()
	check("Enter" in dashboard.mix_result.text, "zero ratio rejected")
	for choice in dashboard.TOOL_CHOICES:
		dashboard.show_page(choice[0])
		check(dashboard.pages[choice[0]].is_visible_in_tree(), "existing tool remains accessible: " + choice[0])
	dashboard.show_page("home")
	var screenshot := OS.get_environment("GOPHERTECH_SCREENSHOT")
	if not screenshot.is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(screenshot) == OK, "screenshot saved")
	print("Shop smoke: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	dashboard.queue_free()
	quit(0 if failures == 0 else 1)
