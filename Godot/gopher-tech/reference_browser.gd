extends VBoxContainer
## A real webpage rendered inside the reference area, with saved-text fallback.

signal saved_text_requested
var browser: Control
var address: LineEdit
var notice: Label
var current_url := ""
var back_button: Button
var forward_button: Button

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var toolbar := HFlowContainer.new()
	add_child(toolbar)
	back_button = action(toolbar, "Back", func(): browser.call("go_back"))
	forward_button = action(toolbar, "Forward", func(): browser.call("go_forward"))
	action(toolbar, "Reload", func():
		if browser != null: browser.call("reload")
	)
	action(toolbar, "Stop", func():
		if browser != null: browser.call("stop_loading")
	)
	action(toolbar, "Saved text", func(): saved_text_requested.emit())
	action(toolbar, "Open externally", func():
		if current_url.begins_with("https://"): OS.shell_open(current_url)
	)
	address = LineEdit.new()
	address.editable = false
	address.custom_minimum_size.x = 0
	add_child(address)
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(notice)
	back_button.disabled = true
	forward_button.disabled = true

func action(parent: Node, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 40
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func open_url(url: String) -> bool:
	if not url.begins_with("https://"): return false
	current_url = url
	address.text = url
	visible = true
	if not ClassDB.class_exists("CefTexture"):
		notice.text = "Interactive browser runtime is unavailable. Use Saved text or Open externally."
		return false
	if browser == null:
		browser = ClassDB.instantiate("CefTexture")
		# Software rendering avoids driver-specific Vulkan interop requirements.
		browser.set("enable_accelerated_osr", false)
		browser.set("url", url)
		browser.set("popup_policy", 2)
		browser.set("permission_policy", 0)
		browser.set("dialog_policy", 2)
		browser.set("pause_rendering_when_hidden", true)
		browser.custom_minimum_size = Vector2(0, 560)
		browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		browser.focus_mode = Control.FOCUS_ALL
		browser.connect("url_changed", func(value: String):
			current_url = value
			address.text = value
			update_navigation()
		)
		browser.connect("load_started", func(_value: String): notice.text = "Loading webpage…")
		browser.connect("load_finished", func(_value: String, code: int):
			notice.text = "Live webpage · Browsing does not verify an answer or save this page to the conversation." if code < 400 else "The website returned HTTP %d. Try Reload or Saved text." % code
			update_navigation()
		)
		browser.connect("load_error", func(_value: String, code: int, _message: String):
			if code != -3: notice.text = "This webpage could not load. Try Reload, Saved text or Open externally."
		)
		browser.connect("popup_requested", func(value: String, _disposition: int, gesture: bool):
			if gesture and value.begins_with("https://"): browser.set("url", value)
		)
		add_child(browser)
	else:
		if browser.get("url") == url:
			notice.text = "Loading webpage…" if browser.call("is_loading") else "Live webpage · Browsing does not verify an answer or save this page to the conversation."
			return true
		browser.set("url", url)
	notice.text = "Loading webpage…"
	return true

func update_navigation() -> void:
	if browser == null: return
	back_button.disabled = not browser.call("can_go_back")
	forward_button.disabled = not browser.call("can_go_forward")

func reset() -> void:
	if browser != null:
		remove_child(browser)
		browser.queue_free()
		browser = null
	current_url = ""
	visible = false
