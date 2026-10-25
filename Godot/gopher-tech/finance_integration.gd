extends SceneTree

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func wait_idle(page: Control) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while page.busy and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	check(not page.busy, "request finished")

func run() -> void:
	for kind in ["payable", "receivable"]:
		var page = load("res://finance_dashboard.gd").new()
		page.kind = kind
		root.add_child(page)
		await wait_idle(page)
		check(page.online, kind + " page connects")
		page.create_document()
		check(not page.busy and "Enter the name" in page.message.text, "missing fields blocked")
		page.inputs["party"].text = "Test Supplier" if kind == "payable" else "Test Customer"
		page.inputs["reference"].text = "TEST-" + kind
		page.inputs["amount"].text = "0.30"
		page.inputs["issue_date"].text = page.today()
		page.inputs["due_date"].text = page.today()
		page.create_document()
		check("currency" in page.message.text, "currency must be chosen")
		page.currency.select(1)
		page.create_document()
		await wait_idle(page)
		check(page.documents.size() == 1, "saved document appears in correct side")
		check(page.selected_id > 0, "saved document selected")
		check(not page.payment_save.disabled, "can record payment on open document")
		page.payment_inputs["amount"].text = "0.10"
		page.payment_save.pressed.emit()
		await wait_idle(page)
		check(page.documents[0]["balance"] == "0.20", "exact partial balance")
		check("0.10" in page.details.text, "payment history displayed")
		page.payment_inputs["amount"].text = "0.21"
		page.record_payment()
		await wait_idle(page)
		check(not page.online, "conflict blocks stale payment actions")
		check(page.payment_inputs["amount"].text == "0.21", "failed payment keeps entry")
		page.load_documents()
		await wait_idle(page)
		page.payment_inputs["amount"].text = "0.20"
		page.record_payment()
		await wait_idle(page)
		check(page.documents[0]["status"] == "paid", "full settlement marked paid")
		check(page.payment_save.disabled, "paid record cannot be paid again")
		var first_id: int = page.selected_id
		page.payment_inputs["amount"].text = "3.00"
		page.inputs["party"].text = "Second test account"
		page.inputs["reference"].text = "DRAFT-" + kind
		page.inputs["amount"].text = "10.00"
		page.inputs["due_date"].text = page.today()
		page.create_document()
		await wait_idle(page)
		check(page.payment_inputs["amount"].text.is_empty(), "new record has no other record's payment draft")
		var second_id: int = page.selected_id
		page.payment_inputs["amount"].text = "2.00"
		for i in range(page.visible_documents.size()):
			if int(page.visible_documents[i]["id"]) == first_id:
				page.show_details(i)
				break
		await wait_idle(page)
		check(page.payment_inputs["amount"].text == "3.00", "first document draft restored")
		for i in range(page.visible_documents.size()):
			if int(page.visible_documents[i]["id"]) == second_id:
				page.show_details(i)
				break
		await wait_idle(page)
		check(page.payment_inputs["amount"].text == "2.00", "second document draft restored")
		page.search.text = "not found"
		page.search.text_changed.emit(page.search.text)
		check(page.records.item_count == 0 and page.payment_save.disabled, "filtered selection cannot receive payment")
		page.api_url = "http://127.0.0.1:1"
		page.load_documents()
		await wait_idle(page)
		check(not page.online and page.payment_save.disabled, "offline payment disabled")
		page.queue_free()
		await process_frame
	print("Finance integration: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
