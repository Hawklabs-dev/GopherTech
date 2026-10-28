extends Button
## Explicit tap-to-record local dictation; no background listening or audio files.
signal transcript_ready(value: String)
signal notice(value: String)
signal activity_changed(active: bool)

var api_url := "http://127.0.0.1:8000"
var request_node: HTTPRequest
var player: AudioStreamPlayer
var effect: AudioEffectRecord
var timer: Timer
var bus_name := ""
var phase := ""
var active := false

func _ready() -> void:
	text = "Speak"
	custom_minimum_size.y = 44
	tooltip_text = "Tap to dictate locally, then Stop. Review the words before asking."
	request_node = HTTPRequest.new()
	request_node.timeout = 45.0
	add_child(request_node)
	request_node.request_completed.connect(on_response)
	timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = 30.0
	timer.timeout.connect(stop_recording)
	add_child(timer)
	pressed.connect(toggle)

func toggle() -> void:
	if phase == "record":
		stop_recording()
		return
	if active: return
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy":
		notice.emit("Microphone input needs the desktop app and an available audio device.")
		return
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		notice.emit("Restart GopherTech to enable microphone input.")
		return
	phase = "check"
	set_active(true)
	text = "Checking voice…"
	disabled = true
	if request_node.request(api_url + "/voice/status") != OK:
		finish("Voice could not reach the backend. Restart it and retry.")

func set_active(value: bool) -> void:
	active = value
	activity_changed.emit(value)

func begin_recording() -> void:
	if bus_name.is_empty():
		bus_name = "GopherVoice_" + str(get_instance_id())
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_mute(index, true)
		effect = AudioEffectRecord.new()
		effect.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(index, effect)
		player = AudioStreamPlayer.new()
		player.stream = AudioStreamMicrophone.new()
		player.bus = bus_name
		add_child(player)
	phase = "record"
	effect.set_recording_active(true)
	player.play()
	text = "Stop recording"
	disabled = false
	timer.start()
	notice.emit("Listening locally… Tap Stop when finished (30 seconds maximum).")

func stop_recording() -> void:
	if phase != "record": return
	timer.stop()
	effect.set_recording_active(false)
	var recording := effect.get_recording()
	player.stop()
	if recording == null or recording.data.is_empty():
		finish("No microphone audio captured. Check your input device and try again.")
		return
	var audio := wav_bytes(recording)
	phase = "transcribe"
	text = "Transcribing…"
	disabled = true
	notice.emit("Turning your recording into words locally…")
	if request_node.request_raw(api_url + "/voice/transcribe", ["Content-Type: audio/wav"], HTTPClient.METHOD_POST, audio) != OK:
		finish("Voice could not reach the backend. Your typed question is unchanged.")

static func wav_bytes(recording: AudioStreamWAV) -> PackedByteArray:
	# Downmix the 16-bit recording in memory; keep all raw audio off disk.
	var source := recording.data
	var channels := 2 if recording.stereo else 1
	var frames := mini(source.size() / (channels * 2), recording.mix_rate * 30)
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	for index in range(frames):
		var sample := source.decode_s16(index * channels * 2)
		if channels == 2:
			sample = (sample + source.decode_s16(index * 4 + 2)) / 2
		pcm.encode_s16(index * 2, sample)
	var header := PackedByteArray()
	header.resize(44)
	for index in range(4):
		header[index] = "RIFF".unicode_at(index)
		header[8 + index] = "WAVE".unicode_at(index)
		header[12 + index] = "fmt ".unicode_at(index)
		header[36 + index] = "data".unicode_at(index)
	header.encode_u32(4, 36 + pcm.size())
	header.encode_u32(16, 16)
	header.encode_u16(20, 1)
	header.encode_u16(22, 1)
	header.encode_u32(24, recording.mix_rate)
	header.encode_u32(28, recording.mix_rate * 2)
	header.encode_u16(32, 2)
	header.encode_u16(34, 16)
	header.encode_u32(40, pcm.size())
	header.append_array(pcm)
	return header

func on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not active: return
	var value: Variant = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300 or not value is Dictionary:
		var message := "Voice request failed. Check the backend and microphone, then retry."
		if value is Dictionary and value.get("detail") is String: message = value["detail"]
		if code == 404: message = "Restart the backend to load local voice support."
		finish(message)
		return
	if phase == "check":
		if value.get("available", false): begin_recording()
		else: finish(value.get("message", "Local voice setup is unavailable."))
	elif phase == "transcribe":
		var transcript: String = value.get("text", "")
		finish(value.get("message", "Review the words before asking."))
		if not transcript.is_empty(): transcript_ready.emit(transcript)

func finish(message: String) -> void:
	phase = ""
	text = "Speak"
	disabled = false
	set_active(false)
	if not message.is_empty(): notice.emit(message)

func cancel() -> void:
	if request_node != null: request_node.cancel_request()
	if timer != null: timer.stop()
	if effect != null: effect.set_recording_active(false)
	if player != null: player.stop()
	finish("")

func _exit_tree() -> void:
	cancel()
	if not bus_name.is_empty():
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0: AudioServer.remove_bus(index)
