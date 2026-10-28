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
	check(dashboard.active_page == "home", "quick search is the entry point")
	check(dashboard.pages.size() == 7, "one work area replaces order/details/photo pages")
	check(dashboard.navigation.size() == 4, "four main navigation choices")
	check(dashboard.job_workspace.question != null, "main screen has a large question input")
	check(dashboard.pages["home"].visible, "quick search starts visible")
	check(not dashboard.pages["equipment"].visible, "equipment registration is optional")
	for key in dashboard.navigation:
		dashboard.nav_grid.get_child(dashboard.navigation.keys().find(key)).pressed.emit()
		check(dashboard.active_page == key, "navigation opens " + key)
		var visible_pages := 0
		for page in dashboard.pages.values():
			visible_pages += int(page.is_visible_in_tree())
		check(visible_pages == (2 if key in ["tools", "parts_list"] else 1), "only selected main page and tool are visible")
	var section_tasks := {"parts":"Carburetor & gasket #123", "diagnose":"No spark", "repair":"Replace belt", "fabricate":"Bracket dimensions"}
	for key in section_tasks:
		dashboard.show_page(key)
		check(dashboard.work_form["task"].text.is_empty() and dashboard.job_workspace.notes.text.is_empty(), "unused section starts empty")
		check(not dashboard.prepare_research(key), "blank request blocked")
		dashboard.work_form["task"].text = section_tasks[key]
		dashboard.work_form["task"].text_changed.emit(section_tasks[key])
		dashboard.job_workspace.notes.text = "Measurements for " + key
		dashboard.job_workspace.notes.text_changed.emit()
		check(dashboard.prepare_research(key), "standalone request needs no model/profile")
		check(section_tasks[key] in dashboard.work_form["output"].text, "brief retains this section's request")
		check(section_tasks[key] in dashboard.search_query(key, dashboard.form_values(key)), "query retains this section's task")
	check(dashboard.reference_desk.question_notes == dashboard.job_workspace.notes, "reference reader shares the one durable notes editor")
	var task_editor = dashboard.work_form["task"]
	var notes_editor = dashboard.job_workspace.notes
	for mode in dashboard.RESEARCH_MODES:
		dashboard.show_page(mode)
		check(dashboard.active_page == "saved", "all research modes open the same work area")
		check(dashboard.work_form["task"] == task_editor and dashboard.job_workspace.notes == notes_editor, "mode changes reuse the same input controls")
		check(task_editor.text == section_tasks[mode], "mode restores its own task")
		check(notes_editor.text == "Measurements for " + mode, "mode restores its own notes")
	var titles := []
	for mode in dashboard.RESEARCH_MODES:
		dashboard.set_research_kind(mode)
		titles.append(dashboard.work_form["panel_title"].text)
		check(dashboard.research_panel.get_parent().visible, "research selection displays content beneath the mode buttons")
		check(dashboard.work_form["add_button"].visible == (mode == "parts"), "parts-only action changes with the selected panel")
	check(titles.size() == 4 and titles.count("Parts research") == 1 and titles.count("Troubleshooting") == 1 and titles.count("Repair plan") == 1 and titles.count("Fabrication plan") == 1, "four visibly distinct research panels")
	dashboard.show_page("photos")
	check(dashboard.active_page == "saved" and dashboard.photo_workspace.is_visible_in_tree() and not dashboard.research_panel.get_parent().visible, "photos populate within the same work area")
	dashboard.show_page("parts")
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
	check(dashboard.work_form["task"].text == "Carburetor & gasket #123", "navigation retains work")
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
