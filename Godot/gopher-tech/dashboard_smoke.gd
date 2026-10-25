extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var dashboard = load("res://equipment_dashboard.tscn").instantiate()
	root.add_child(dashboard)
	dashboard.request_node.cancel_request()
	dashboard.set_busy(false)
	dashboard.on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"equipment":[]}'.to_utf8_buffer())
	check(dashboard.equipment.is_empty(), "empty inventory")
	check("first piece" in dashboard.details.text, "empty guidance")
	dashboard.fields["name"].text = "   "
	dashboard.add_equipment()
	check(not dashboard.busy, "blank name must not submit")
	check("Enter" in dashboard.form_message.text, "required field guidance")
	dashboard.on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"equipment":[{"id":1,"name":"Meter","manufacturer":"HawkLabs","model":null,"notes":"Bench A"},{"id":2,"name":"Drill"}]}'.to_utf8_buffer())
	check(dashboard.records.item_count == 2, "list renders records")
	check(dashboard.records.get_item_text(0).begins_with("#1   "), "integer record ID display")
	dashboard.search.text = "hawklabs"
	dashboard.search.text_changed.emit(dashboard.search.text)
	check(dashboard.records.item_count == 1, "manufacturer search")
	dashboard.show_details(0)
	check("Bench A" in dashboard.details.text, "selection shows notes")
	dashboard.search.text = "no matching record"
	dashboard.search.text_changed.emit(dashboard.search.text)
	check(dashboard.records.item_count == 0, "search empty result")
	dashboard.on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{}'.to_utf8_buffer())
	check("Unexpected" in dashboard.status.text, "malformed response")
	dashboard.on_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	check("Offline" in dashboard.status.text, "offline guidance")
	check(dashboard.equipment.size() == 2, "offline retains previous records")
	dashboard.operation = "create"
	dashboard.fields["name"].text = "Unsaved meter"
	dashboard.on_response(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
	check(dashboard.fields["name"].text == "Unsaved meter", "failed save preserves form")
	check("before retrying" in dashboard.form_message.text, "uncertain save guidance")
	print("Dashboard smoke: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	dashboard.queue_free()
	quit(0 if failures == 0 else 1)
