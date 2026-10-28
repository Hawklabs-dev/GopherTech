extends VBoxContainer
## Original image files remain local to this device; no upload or AI call occurs.
const MAX_BYTES := 12 * 1024 * 1024
var job_id := ""
var storage_root := "user://work-order-photos"
var pending_bytes := PackedByteArray()
var pending_extension := ""
var pending_name := ""
var message: Label
var preview: TextureRect
var photo_list: ItemList
var chooser: FileDialog
var attach_button: Button
var choose_button: Button
var records: Array[String] = []

func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var configured := OS.get_environment("GOPHERTECH_PHOTO_ROOT")
	if not configured.is_empty(): storage_root = configured
	var title := Label.new()
	title.text = "Pictures stay with this work order on this device."
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title)
	choose_button = Button.new()
	choose_button.text = "Choose Photo"
	choose_button.custom_minimum_size.y = 56
	choose_button.pressed.connect(func(): chooser.popup_centered_ratio(0.8))
	add_child(choose_button)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)
	photo_list = ItemList.new()
	photo_list.custom_minimum_size.y = 140
	photo_list.fixed_icon_size = Vector2i(64, 64)
	photo_list.item_selected.connect(show_photo)
	add_child(photo_list)
	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size.y = 300
	preview.visible = false
	add_child(preview)
	attach_button = Button.new()
	attach_button.text = "Keep Photo With This Work Order"
	attach_button.custom_minimum_size.y = 56
	attach_button.visible = false
	attach_button.pressed.connect(attach_photo)
	add_child(attach_button)
	var notice := Label.new()
	notice.text = "Camera capture and AI label reading are not connected yet. Choose JPEG, PNG or WebP pictures, up to 12 MiB each."
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(notice)
	chooser = FileDialog.new()
	chooser.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	chooser.access = FileDialog.ACCESS_FILESYSTEM
	chooser.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Pictures"])
	chooser.file_selected.connect(choose_file)
	add_child(chooser)
	bind_job("")

func valid_id(value: String) -> bool:
	if value.length() != 36: return false
	for character in value:
		if not character in "0123456789abcdefABCDEF-": return false
	return true

func bind_job(value: String) -> void:
	if value == job_id and not value.is_empty(): return
	job_id = value if valid_id(value) else ""
	pending_bytes.clear()
	pending_extension = ""
	if chooser != null: chooser.hide()
	if preview != null:
		preview.texture = null
		preview.visible = false
	if attach_button != null: attach_button.visible = false
	if choose_button != null: choose_button.disabled = job_id.is_empty()
	refresh()

func folder() -> String:
	return storage_root.path_join(job_id)

func decode(bytes: PackedByteArray) -> Image:
	var picture := Image.new()
	var result := ERR_FILE_UNRECOGNIZED
	if bytes.size() >= 8 and bytes.slice(0, 8).hex_encode() == "89504e470d0a1a0a":
		result = picture.load_png_from_buffer(bytes)
	elif bytes.size() >= 3 and bytes[0] == 255 and bytes[1] == 216 and bytes[2] == 255:
		result = picture.load_jpg_from_buffer(bytes)
	elif bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		result = picture.load_webp_from_buffer(bytes)
	if result != OK or picture.is_empty(): return null
	if picture.get_width() * picture.get_height() > 40000000: return null
	return picture

func choose_file(path: String) -> void:
	if job_id.is_empty(): return
	pending_bytes.clear()
	attach_button.visible = false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		message.text = "Could not open that picture. Try another file."
		return
	if file.get_length() > MAX_BYTES:
		message.text = "That picture exceeds 12 MiB. Choose a smaller copy."
		return
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var picture := decode(bytes)
	if picture == null:
		message.text = "Could not read that picture. Choose a JPEG, PNG or WebP image under 40 megapixels."
		return
	pending_bytes = bytes
	pending_extension = "png" if bytes[0] == 137 else "jpg" if bytes[0] == 255 else "webp"
	pending_name = path.get_file().get_basename().validate_filename().left(80)
	preview.texture = ImageTexture.create_from_image(picture)
	preview.visible = true
	attach_button.visible = true
	message.text = "Preview only — tap Keep Photo to save it with this work order."

func attach_photo() -> void:
	if job_id.is_empty() or pending_bytes.is_empty(): return
	var directory := ProjectSettings.globalize_path(folder())
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		message.text = "Photo not saved. Could not create the local photo folder."
		return
	var filename := Crypto.new().generate_random_bytes(12).hex_encode() + "_" + pending_name + "." + pending_extension
	var destination := directory.path_join(filename)
	var temporary := destination + ".part"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		message.text = "Photo not saved. Check free space and try again."
		return
	file.store_buffer(pending_bytes)
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK or DirAccess.rename_absolute(temporary, destination) != OK:
		DirAccess.remove_absolute(temporary)
		message.text = "Photo not saved. Check free space and retry before leaving this screen."
		return
	pending_bytes.clear()
	attach_button.visible = false
	refresh()
	message.text = "Photo saved on this device with this work order."

func refresh() -> void:
	if photo_list == null: return
	photo_list.clear()
	records.clear()
	if job_id.is_empty():
		message.text = "Open or create a work order before adding photos."
		return
	var directory := DirAccess.open(folder())
	if directory != null:
		for filename in directory.get_files():
			if filename.get_extension().to_lower() in ["png", "jpg", "webp"]: records.append(filename)
	records.sort()
	for filename in records: photo_list.add_item(filename.substr(25).get_basename())
	message.text = "%d saved photo(s) on this device." % records.size()

func show_photo(index: int) -> void:
	if index < 0 or index >= records.size(): return
	var file := FileAccess.open(folder().path_join(records[index]), FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		message.text = "This photo could not be opened."
		return
	var picture := decode(file.get_buffer(file.get_length()))
	file.close()
	if picture == null:
		message.text = "This saved photo could not be decoded. The file has been kept."
		return
	pending_bytes.clear()
	preview.texture = ImageTexture.create_from_image(picture)
	preview.visible = true
	attach_button.visible = false
	message.text = "Saved photo · " + records[index].substr(25)
