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
	check(dashboard.pages.size() == 10, "all shop and legacy pages exist")
	check(dashboard.pages["home"].visible, "home starts visible")
	check(not dashboard.pages["equipment"].visible, "equipment registration is optional")
	for key in dashboard.navigation:
		dashboard.navigation[key].pressed.emit()
		check(dashboard.active_page == key, "navigation opens " + key)
		var visible_pages := 0
		for page in dashboard.pages.values():
			visible_pages += int(page.visible)
		check(visible_pages == 1, "only one page visible")
	for key in ["parts", "diagnose", "repair", "fabricate"]:
		check(not dashboard.prepare_research(key), "blank request blocked")
		dashboard.research_forms[key]["inputs"]["task"].text = "Carburetor & gasket #123"
		check(dashboard.prepare_research(key), "standalone request needs no model/profile")
		check("Carburetor & gasket #123" in dashboard.research_forms[key]["output"].text, "brief retains request")
		var url: String = dashboard.research_url(key, dashboard.form_values(key))
		check(url.begins_with("https://www.google.com/search?q="), "search uses a fixed HTTPS destination")
		check("%26" in url and "%23" in url, "query characters are encoded")
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
	dashboard.size.x = 800
	dashboard.adapt_layout()
	check(dashboard.tile_grid.columns == 1, "narrow layout stacks actions")
	dashboard.size.x = 1100
	dashboard.adapt_layout()
	check(dashboard.tile_grid.columns == 2, "wide layout uses two columns")
	dashboard.show_page("home")
	var screenshot := OS.get_environment("GOPHERTECH_SCREENSHOT")
	if not screenshot.is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(screenshot) == OK, "screenshot saved")
	print("Shop smoke: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	dashboard.queue_free()
	quit(0 if failures == 0 else 1)
