extends SceneTree
## Clear/history isolation and dictation lifecycle without recording the owner.
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var shop = load("res://shop_dashboard.tscn").instantiate()
	root.add_child(shop)
	var work = shop.job_workspace
	work.request_node.cancel_request()
	work.busy = false
	var record := {"id":"quick-fixture", "notes":"Keep notes", "section_drafts":{}, "parts":[{"name":"Keep part"}], "sources":[], "messages":[{"id":1,"role":"user","content":"Old question"},{"id":2,"role":"assistant","content":"Old answer"}], "research":{"plan":{"browser_url":"https://www.google.com/search?q=old"}}}
	work.apply_job(record.duplicate(true))
	work.question.text = "Keep draft"
	work.show_document({"url":"https://engines.honda.com/fixture.pdf", "format":"pdf", "text":"Old document", "links":[]})
	work.clear_button.pressed.emit()
	check(not "Old answer" in work.conversation.text and not "websearch" in work.conversation.text, "clear hides previous replies and search action")
	check(not work.document_panel.visible and work.document_reader.text.is_empty() and work.live_browser.current_url.is_empty(), "clear dismisses document and browser content")
	check(work.job["messages"].size() == 2 and work.job["parts"].size() == 1 and work.notes.text == "Keep notes", "clear preserves saved conversation, parts and notes")
	check(work.question.text == "Keep draft" and work.restore_button.visible, "clear preserves the current draft and offers history")
	work.apply_job(record.duplicate(true))
	check(not "Old answer" in work.conversation.text, "background save does not restore cleared replies")
	var followup := record.duplicate(true)
	followup["messages"].append({"id":3,"role":"assistant","content":"New answer"})
	work.apply_job(followup)
	check("New answer" in work.conversation.text and not "Old answer" in work.conversation.text, "later answers appear without cleared history")
	work.restore_button.pressed.emit()
	check("Old answer" in work.conversation.text and not work.restore_button.visible, "saved history can be restored")
	work.operation = "reference"
	work.request_results_generation = work.results_generation
	work.clear_results()
	work.on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"job":record, "document":{"url":"https://engines.honda.com/fixture.pdf", "format":"pdf", "text":"Late reference", "links":[]}}).to_utf8_buffer())
	check(not work.document_panel.visible, "late reference does not reopen after clear")
	work.operation = "question"
	work.request_results_generation = work.results_generation
	work.clear_results()
	work.on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(followup).to_utf8_buffer())
	check(not "New answer" in work.conversation.text, "clear dismisses an in-flight answer while preserving its save")
	work.voice_input.transcript_ready.emit("honda engine")
	check(work.question.text == "Keep draft honda engine", "dictation preserves the typed draft")
	work.voice_input.phase = "transcribe"
	work.voice_input.set_active(true)
	work.before_switch.emit()
	work.voice_input.on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"text":"late words"}).to_utf8_buffer())
	check(not work.voice_input.active and not "late words" in work.question.text, "switching cancels voice and ignores late recognition")
	work.voice_input.phase = "record"
	work.voice_input.set_active(true)
	shop.show_page("tools", false)
	check(not work.voice_input.active, "leaving quick search cancels recording")
	# Exact stereo PCM downmix, 16-bit WAV header and size.
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 16000
	audio.stereo = true
	var pcm := PackedByteArray()
	pcm.resize(4)
	pcm.encode_s16(0, 1000)
	pcm.encode_s16(2, 3000)
	audio.data = pcm
	var encoded: PackedByteArray = work.voice_input.wav_bytes(audio)
	check(encoded.size() == 46 and encoded.decode_u16(22) == 1 and encoded.decode_s16(44) == 2000, "microphone audio becomes mono PCM WAV in memory")
	root.size = Vector2i(360, 800)
	shop.show_page("home", false)
	await process_frame
	await process_frame
	check(work.clear_button.get_global_rect().end.x <= 360 and work.voice_input.size.y >= 44, "voice and clear controls fit narrow touch layout")
	print("Quick input: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	shop.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
