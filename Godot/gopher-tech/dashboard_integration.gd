extends SceneTree

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func wait_idle(dashboard: Control) -> void:
	var deadline := Time.get_ticks_msec() + 12000
	while dashboard.busy and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	check(not dashboard.busy, "request finished within deadline")

func run() -> void:
	var dashboard = load("res://equipment_dashboard.tscn").instantiate()
	root.add_child(dashboard)
	await wait_idle(dashboard)
	check("Connected" in dashboard.status.text, "connect to temporary API")
	check(dashboard.equipment.size() == 0, "temporary API starts empty")
	dashboard.fields["name"].text = "Integration test meter"
	dashboard.fields["manufacturer"].text = "HawkLabs"
	dashboard.fields["notes"].text = "Disposable test record"
	dashboard.save.pressed.emit()
	await wait_idle(dashboard)
	check(dashboard.equipment.size() == 1, "POST followed by GET refresh")
	check(dashboard.fields["name"].text.is_empty(), "confirmed save clears form")
	check("successfully" in dashboard.form_message.text, "save success guidance")
	if dashboard.equipment.size() == 1:
		dashboard.records.item_selected.emit(0)
		check("Disposable test record" in dashboard.details.text, "saved notes shown")
	dashboard.show_details(0)
	check(not dashboard.checkout.disabled, "available equipment can be taken")
	check(dashboard.checkin.disabled, "available equipment cannot be returned")
	dashboard.borrower.text = "  "
	dashboard.checkout.pressed.emit()
	check(not dashboard.busy, "blank borrower blocked locally")
	dashboard.borrower.text = "Sam"
	dashboard.checkout.pressed.emit()
	await wait_idle(dashboard)
	check(dashboard.equipment[0].get("borrower") == "Sam", "borrower saved and displayed")
	check(dashboard.checkout.disabled, "checked-out equipment cannot be taken again")
	check(not dashboard.checkin.disabled, "checked-out equipment can be returned")
	dashboard.checkin.pressed.emit()
	await wait_idle(dashboard)
	check(dashboard.equipment[0].get("status") == "available", "return refreshes available state")
	check(dashboard.checkin.disabled, "return button disabled after return")
	check(not dashboard.checkout.disabled, "equipment ready for next person")
	dashboard.api_url = "http://127.0.0.1:1"
	dashboard.load_equipment()
	await wait_idle(dashboard)
	check("Offline" in dashboard.status.text, "connection loss handled")
	check(dashboard.equipment.size() == 1, "connection loss retains inventory")
	check(dashboard.checkout.disabled and dashboard.checkin.disabled, "offline changes disabled")
	print("Dashboard integration: ", "FAIL" if failed else "PASS")
	dashboard.queue_free()
	quit(1 if failed else 0)
