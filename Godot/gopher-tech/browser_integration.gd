extends SceneTree
## Real browser test: no backend, database, credentials or paid calls.
var failures := 0
var loaded := false
var clicked := false
var scrolled := false

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1000, 800)
	root.always_on_top = true
	OS.set_environment("GOPHERTECH_API_URL", "http://127.0.0.1:1")
	var shop = load("res://shop_dashboard.tscn").instantiate()
	root.add_child(shop)
	var work = shop.job_workspace
	if OS.get_environment("GOPHERTECH_BROWSER_SEARCH_TEST") == "1":
		await search_link_test(work, shop)
		return
	work.show_document({"url":"https://engines.honda.com/support-and-service/owners-manuals", "format":"html", "text":"Saved Honda reference fixture", "links":[]})
	var panel = work.live_browser
	check(panel.browser != null, "native Chromium runtime available")
	if panel.browser == null:
		quit(1)
		return
	panel.browser.connect("load_finished", func(_url: String, code: int): loaded = code == 200)
	var deadline := Time.get_ticks_msec() + 40000
	while not loaded and Time.get_ticks_msec() < deadline:
		await create_timer(.1).timeout
	check(loaded, "live Honda page loaded inside app")
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/gophertech-browser-live.png")
	# Replace DOM only in this disposable browser to exercise real pointer input.
	panel.browser.connect("ipc_message", func(message: String):
		if message == "clicked": clicked = true
		if message == "scrolled": scrolled = true
	)
	panel.browser.call("eval", "document.head.innerHTML='<style>html,body{margin:0;padding:0;background:white}body{height:2400px}</style>';document.body.innerHTML='<button id=probe style=\"position:fixed;left:20px;top:20px;width:180px;height:70px\">Click test</button>';document.getElementById('probe').onclick=()=>window.sendIpcMessage('clicked');window.addEventListener('scroll',()=>window.sendIpcMessage('scrolled'));")
	await create_timer(.5).timeout
	root.grab_focus()
	panel.browser.grab_focus()
	var focus_deadline := Time.get_ticks_msec() + 5000
	while not root.has_focus() and Time.get_ticks_msec() < focus_deadline:
		root.grab_focus()
		await create_timer(.2).timeout
	check(root.has_focus(), "test window has focus for Chromium input")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/gophertech-browser-click.png")
	var point: Vector2 = panel.browser.global_position + Vector2(90, 50)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await create_timer(.05).timeout
	await create_timer(.5).timeout
	check(clicked, "clicks reach interactive webpage")
	var outer_scroll: int = shop.page_scroll.scroll_vertical
	var wheel := InputEventMouseButton.new()
	wheel.position = point
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.factor = 3.0
	wheel.pressed = true
	root.push_input(wheel, true)
	await create_timer(.5).timeout
	check(scrolled, "mouse wheel scrolls webpage")
	check(shop.page_scroll.scroll_vertical == outer_scroll, "webpage scrolling does not move outer conversation")
	panel.saved_text_requested.emit()
	check(work.document_reader.visible and not panel.visible and "Saved Honda" in work.document_reader.text, "saved text remains available beside live webpage")
	work.on_link("livepage")
	check(panel.visible and not work.document_reader.visible, "return to live webpage")
	# Exercise the actual conversation search link, not a direct browser API call.
	work.job["research"] = {"plan":{"browser_url":"https://www.google.com/search?q=Honda+GX160+manual"}}
	work.render_conversation()
	check("Browse results inside GopherTech" in work.conversation.text, "search link describes in-app browsing")
	work.on_link("websearch")
	check(panel.current_url == "https://www.google.com/search?q=Honda+GX160+manual" and panel.visible, "conversation web search stays in app")
	check("inside GopherTech" in work.status.text, "search status explains current action")
	panel.reset()
	check(panel.browser == null and not panel.visible, "browser clears on reset")
	print("Embedded browser: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	shop.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func search_link_test(work: Node, shop: Node) -> void:
	var url := "https://www.google.com/search?q=Honda+GX160+manual"
	work.job["research"] = {"plan":{"browser_url":url}}
	work.render_conversation()
	work.on_link("websearch")
	var panel = work.live_browser
	check(panel.visible and panel.current_url == url, "search link opens embedded browser")
	check("inside GopherTech" in work.status.text, "search status describes in-app action")
	if panel.browser != null:
		panel.browser.connect("load_finished", func(_url: String, code: int): loaded = code == 200)
		var deadline := Time.get_ticks_msec() + 30000
		while not loaded and Time.get_ticks_msec() < deadline:
			await create_timer(.1).timeout
		check(loaded, "live search page loads inside GopherTech")
		await create_timer(.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/gophertech-search-in-app.png")
	else:
		check(false, "native browser installed")
	print("In-app search link: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	shop.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
