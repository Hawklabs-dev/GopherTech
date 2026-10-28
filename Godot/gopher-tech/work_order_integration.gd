extends SceneTree
## Real HTTP, disposable backend; work order switching and draft/save regressions.
var failures := 0
func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)
func _initialize() -> void:
	call_deferred("run")
func idle(work: Node) -> void:
	await process_frame
	var deadline := Time.get_ticks_msec() + 12000
	while (work.busy or not work.pending_state.is_empty() or not work.pending_open.is_empty() or not work.pending_creation.is_empty()) and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	check(not work.busy and work.pending_state.is_empty(), "request/save queue drained")
func run() -> void:
	if OS.get_environment("GOPHERTECH_PHOTO_ROOT").is_empty():
		push_error("Run through tests/run_work_order_integration.py to isolate photo storage.")
		quit(1)
		return
	var shop = load("res://shop_dashboard.tscn").instantiate()
	root.add_child(shop)
	var work = shop.job_workspace
	await idle(work)
	check(shop.active_page == "home", "startup opens quick search")
	if OS.get_environment("GOPHERTECH_REOPEN") == "1":
		check(work.jobs.size() == 2, "two work orders persist across backend restart")
		work.order_search.text = "HL-101"
		work.render_jobs()
		check(work.displayed_jobs.size() == 1, "number search finds exact order after restart")
		work.open_job(work.displayed_jobs[0]["id"])
		await idle(work)
		check(work.notes.text == "12.6 V at battery", "notes persist after restart")
		check(shop.photo_workspace.records.size() == 1, "photo survives app and backend restart")
		shop.photo_workspace.show_photo(0)
		check(shop.photo_workspace.preview.texture != null, "saved original photo decodes after restart")
		check(shop.machine_input.text == "2008 Ford F250 • plate confirmed", "machine description persists after restart")
		check(shop.work_form["task"].text == "Ford brake part draft", "Parts task survives app restart")
		for mode in ["repair", "fabricate", "diagnose"]:
			shop.set_research_kind(mode)
			check(shop.work_form["task"].text == "Ford task for " + mode and work.notes.text == "Ford notes for " + mode, "section's own task and notes survive app/backend restart")
		shop.set_research_kind("parts")
	else:
		work.order_number.text = "HL-101"
		work.create_order("2008 Ford F250")
		await idle(work)
		var first: String = work.job["id"]
		check(shop.active_page == "saved" and "HL-101" in shop.order_heading.text, "new order opens helper with fixed order identity")
		var photos = shop.photo_workspace
		var fixture := Image.create(240, 180, false, Image.FORMAT_RGB8)
		fixture.fill(Color("ddaa44"))
		DirAccess.make_dir_recursive_absolute(photos.storage_root)
		var fixture_path: String = photos.storage_root.path_join("original.png")
		fixture.save_png(fixture_path)
		photos.choose_file(fixture_path)
		check(photos.attach_button.visible and photos.records.is_empty(), "chosen image is previewed before saving")
		photos.attach_photo()
		check(photos.records.size() == 1, "photo attaches to current order")
		check(FileAccess.get_file_as_bytes(photos.folder().path_join(photos.records[0])) == FileAccess.get_file_as_bytes(fixture_path), "original bytes are preserved")
		photos.choose_file(fixture_path)
		photos.choose_file(photos.storage_root.path_join("missing.png"))
		check(photos.pending_bytes.is_empty() and not photos.attach_button.visible, "bad selection cannot attach an earlier preview")
		work.question.text = "Unsubmitted draft for Ford"
		shop.reference_desk.query.text = "2008 Ford F250 manual draft"
		shop.show_page("parts")
		shop.work_form["task"].text = "Ford brake part draft"
		shop.work_form["task"].text_changed.emit("Ford brake part draft")
		shop.show_page("notes")
		work.notes.text = "12.6 V at battery"
		work.notes.text_changed.emit()
		for mode in ["repair", "fabricate", "diagnose"]:
			shop.set_research_kind(mode)
			check(shop.work_form["task"].text.is_empty() and work.notes.text.is_empty(), "unused " + mode + " starts empty")
			shop.work_form["task"].text = "Ford task for " + mode
			shop.work_form["task"].text_changed.emit(shop.work_form["task"].text)
			work.notes.text = "Ford notes for " + mode
			work.notes.text_changed.emit()
		shop.set_research_kind("photos")
		shop.set_research_kind("parts")
		check(shop.work_form["task"].text == "Ford brake part draft" and work.notes.text == "12.6 V at battery", "returning from other sections and Photos restores Parts entries")
		shop.set_research_kind("parts")
		check(work.notes.text == "12.6 V at battery", "tapping the active section preserves unsaved text")
		shop.machine_input.text = "2008 Ford F250 • plate confirmed"
		shop.machine_input.text_changed.emit(shop.machine_input.text)
		# A single tap creates the next order after flushing both debounce timers.
		work.order_number.text = "HL-102"
		work.create_order("Kubota tractor")
		await idle(work)
		var second: String = work.job["id"]
		check(first != second and work.job["work_order_number"] == "HL-102", "new order waits for previous notes and machine save")
		check(shop.reference_desk.query.text.is_empty(), "reference lookup never inherits another machine")
		check(shop.photo_workspace.records.is_empty(), "other work order does not inherit photos")
		check(work.question.text.is_empty() and work.notes.text.is_empty(), "second job never inherits question or notes")
		check(shop.work_form["task"].text.is_empty(), "second job never inherits research form")
		work.question.text = "Unsubmitted draft for Kubota"
		work.open_job(first)
		await idle(work)
		check(shop.reference_desk.query.text == "2008 Ford F250 manual draft", "reference lookup draft returns with its order")
		check(work.question.text == "Unsubmitted draft for Ford", "switching back restores original question draft")
		check(work.notes.text == "12.6 V at battery", "switching saves notes before leaving")
		check(shop.machine_input.text == "2008 Ford F250 • plate confirmed", "switching saves machine before leaving")
		check(shop.work_form["task"].text == "Ford brake part draft", "research draft restored to its own order")
		work.order_number.text = "UNSUBMITTED-NEW"
		work.new_order_row.visible = true
		# Simulate an open response arriving after an old-order note was edited.
		work.notes.text = "Ford inspection still being written"
		work.notes.text_changed.emit()
		var accepted: bool = work.apply_job({"id":second, "work_order_number":"HL-102", "machine_description":"Kubota tractor", "notes":"", "parts":[], "sources":[], "messages":[]})
		check(not accepted and work.job["id"] == first, "late open response cannot merge old-order edits into the next order")
		await idle(work)
		check(work.job["id"] == second and work.notes.text.is_empty(), "queued switch loads the other order's own notes")
		check(shop.machine_input.text == "Kubota tractor", "Ford details never carry into the other order")
		check(work.order_number.text.is_empty() and not work.new_order_row.visible, "new-order draft does not masquerade as the selected order")
		work.open_job(first)
		await idle(work)
		check(work.notes.text == "Ford inspection still being written", "late note is saved to its original Ford order")
		work.save_state({"notes":"12.6 V at battery"})
		await idle(work)
		work.open_job(second)
		await idle(work)
		check(work.question.text == "Unsubmitted draft for Kubota", "other question draft stays separate")
		shop.show_page("saved")
		await idle(work)
		work.order_search.text = "Ford"
		work.render_jobs()
		check(work.displayed_jobs.size() == 1 and work.displayed_jobs[0]["id"] == first, "search matches machine description")
		# Selecting an order during a list request must not create a phantom job.
		work.refresh_jobs()
		work.open_job(first)
		await idle(work)
		check(work.job["id"] == first, "queued opening reaches intended work order")
		work.refresh_jobs()
		await idle(work)
		check(work.jobs.size() == 2, "switching/list requests create no extra work orders")
		var real_api: String = work.api_url
		work.api_url = "http://127.0.0.1:1"
		work.save_state({"notes":"Temporary offline edit"})
		await process_frame
		var deadline := Time.get_ticks_msec() + 4000
		while work.busy and Time.get_ticks_msec() < deadline: await create_timer(0.05).timeout
		work.open_job(second)
		await process_frame
		while work.busy and Time.get_ticks_msec() < deadline: await create_timer(0.05).timeout
		check(work.job["id"] == first and work.pending_open == second, "failed save blocks the requested job switch")
		check(work.pending_state.get("notes") == "Temporary offline edit", "failed save preserves unsaved notes")
		work.api_url = real_api
		work.save_state({"notes":"12.6 V at battery"})
		await idle(work)
		check(work.job["id"] == second, "reconnect completes save then the queued switch")
		root.size = Vector2i(390, 844)
		shop.show_page("saved")
		await idle(work)
		await process_frame
		await process_frame
		shop.page_scroll.scroll_vertical = 30
		work.open_job(first)
		await idle(work)
		await process_frame
		shop.page_scroll.scroll_vertical = 80
		var first_scroll: int = shop.page_scroll.scroll_vertical
		check(first_scroll > 0, "portrait work area has scrollable content for the switching check")
		work.open_job(second)
		await idle(work)
		await process_frame
		check(shop.page_scroll.scroll_vertical == 30, "other order restores its own work-area position")
		work.open_job(first)
		await idle(work)
		await process_frame
		check(shop.page_scroll.scroll_vertical == first_scroll, "returning restores the original order's work-area position")
	# Verify each top-level screen is usable at tablet and narrow portrait widths.
	for viewport in [Vector2i(800, 1100), Vector2i(1100, 800), Vector2i(390, 844)]:
		root.size = viewport
		for destination in shop.navigation:
			shop.show_page(destination)
			await process_frame
			await process_frame
			check("HL-" in shop.order_heading.text, "active order remains visible on every screen")
			check(not shop.page_scroll.is_ancestor_of(shop.order_heading), "work order identity stays outside the scrolling workspace")
			check(shop.order_summary.text == shop.machine_input.text, "header shows the active machine on every screen")
			check(shop.nav_grid.get_child(0).size.y >= 44 and shop.nav_grid.get_child(0).size.y <= 50, "compact navigation keeps usable touch targets")
			check(shop.page_scroll.size.y >= viewport.y * 0.55, "compact header leaves most of the screen for work")
			check(shop.nav_grid.get_global_rect().end.x <= viewport.x, "navigation fits " + str(viewport))
			check(shop.page_scroll.size.y >= 120, "working area remains available " + str(viewport))
	shop.show_page("home")
	print("Work order ", "reopen" if OS.get_environment("GOPHERTECH_REOPEN") == "1" else "workflow", ": ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	shop.queue_free()
	quit(0 if failures == 0 else 1)
