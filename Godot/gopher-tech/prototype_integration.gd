extends SceneTree

var failures := 0

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func idle(workspace: Node) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	await process_frame
	while (workspace.busy or not workspace.pending_state.is_empty() or not workspace.pending_reference.is_empty()) and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	check(not workspace.busy, "request completed")

func run() -> void:
	var shop = load("res://shop_dashboard.tscn").instantiate()
	root.add_child(shop)
	var work = shop.job_workspace
	await idle(work)
	check(shop.navigation.size() == 3, "only three main navigation choices")
	if OS.get_environment("GOPHERTECH_REOPEN") == "1":
		check(work.job.get("context", {}).get("model") == "GX160", "context survives app and backend restart")
		check(work.job.get("notes") == "Measured mounting holes in mm", "notes survive restart")
		check(work.job.get("parts", []).size() == 2 and "Fixture gasket" in str(work.job.get("parts")), "tool-added parts survive restart")
		check(work.job.get("messages", []).size() == 6, "complete conversation survives restart")
		if not work.source_records.is_empty():
			work.open_reference(work.source_records[0]["url"])
			await idle(work)
			check("Original manual fixture" in work.document_reader.text, "saved document reopens without a website fetch")
		for source in work.source_records:
			if source["url"].ends_with("fixture.pdf"):
				work.open_reference(source["url"])
				await idle(work)
				check("GopherTech test diagram" in work.document_reader.text, "PDF text snapshot survives backend restart without fetching")
				break
	else:
		check(work.question != null and work.ask_button.text == "Ask GopherTech", "question is the main workflow")
		work.question.text = "My tractor turns over but won't start."
		work.ask_button.pressed.emit()
		await idle(work)
		check(work.job.has("id"), "question creates a saved job")
		check("petrol or diesel" in work.conversation.text, "relevant follow-up appears inside app")
		work.question.text = "Honda GX160 petrol in Canada"
		work.ask_button.pressed.emit()
		await idle(work)
		check(work.job.get("context", {}).get("intent") == "troubleshoot", "follow-up keeps job intent")
		check(work.job.get("context", {}).get("model") == "GX160", "follow-up keeps engine identity")
		work.save_state({"notes":"Measured mounting holes in mm", "parts":["Qty 2: bracket blanks"]})
		await idle(work)
		shop.show_page("parts")
		shop.research_forms["parts"]["inputs"]["task"].text = "Fixture gasket"
		shop.add_part()
		await idle(work)
		check(work.job.get("parts", []).size() == 2, "parts tool saves into the active job")
		shop.show_page("home")
		work.question.text = "Find the manual"
		work.ask_button.pressed.emit()
		await idle(work)
		check(work.source_records.size() > 0, "manual request uses the remembered model")
		if not work.source_records.is_empty():
			check("gx160" in work.source_records[0]["url"], "best model source appears first")
			work.on_link("source:0")
			await idle(work)
			check("Original manual fixture" in work.document_reader.text, "matching reference reads inside conversation screen")
			work.on_link("document:0")
			await idle(work)
			check("GopherTech test diagram" in work.document_reader.text, "linked PDF reads inside the question workflow")
			work.send("pdf", "/research/pdf-page", {"url":work.document["url"],"page":1})
			await idle(work)
			check(work.pdf_image.visible and work.pdf_image.texture != null, "original PDF diagram layout is displayed in the question workflow")
			var previous: String = work.document_reader.text
			work.open_reference("https://engines.honda.com/missing.pdf")
			await idle(work)
			check(work.document_reader.text == previous, "missing document preserves previous readable content")
			check("unavailable" in work.status.text, "missing document is explicit")
		check(not work.job.get("ai_enabled", true), "unavailable AI is never represented as enabled")
		for choice in shop.TOOL_CHOICES:
			shop.show_page(choice[0])
			check(shop.pages[choice[0]].is_visible_in_tree(), "existing tool remains reachable")
			if choice[0] in ["bills", "invoices"]:
				var finance = shop.pages[choice[0]].get_child(0)
				var deadline := Time.get_ticks_msec() + 10000
				while finance.busy and Time.get_ticks_msec() < deadline:
					await create_timer(0.05).timeout
				check(finance.online, "existing finance records load inside Tools")
		check(not shop.equipment_workspace.busy and shop.equipment_workspace.online, "embedded equipment HTTP requests survive the simplified shell")
		shop.show_page("home")
	print("Prototype ", "reopen" if OS.get_environment("GOPHERTECH_REOPEN") == "1" else "workflow", ": ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	shop.queue_free()
	quit(0 if failures == 0 else 1)
