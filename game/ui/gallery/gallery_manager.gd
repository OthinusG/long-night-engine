class_name GalleryManager
extends RefCounted

## Persistent gallery unlocks across saves and playthroughs.
## Tracks seen CGs and heard BGMs so they can be unlocked in the title Gallery.

signal unlock_changed

const DEFAULT_SAVE_PATH: String = "user://gallery_unlocks.json"

var save_path: String = DEFAULT_SAVE_PATH
var unlocked_cgs: Dictionary = {}  # Dictionary[String, bool]
var unlocked_bgms: Dictionary = {} # Dictionary[String, bool]


func _init(custom_path: String = DEFAULT_SAVE_PATH) -> void:
	save_path = custom_path
	load_unlocks()


func load_unlocks() -> bool:
	if not FileAccess.file_exists(save_path):
		unlocked_cgs.clear()
		unlocked_bgms.clear()
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var content := file.get_as_text()
	var json: Variant = JSON.parse_string(content)
	if not (json is Dictionary):
		return false
	var dict := json as Dictionary
	var cgs: Variant = dict.get("cgs", {})
	if cgs is Dictionary:
		unlocked_cgs = (cgs as Dictionary).duplicate()
	var bgms: Variant = dict.get("bgms", {})
	if bgms is Dictionary:
		unlocked_bgms = (bgms as Dictionary).duplicate()
	return true


func save_unlocks() -> bool:
	var dir := save_path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	var data := {
		"format_version": 1,
		"cgs": unlocked_cgs,
		"bgms": unlocked_bgms,
	}
	file.store_string(JSON.stringify(data, "  ") + "\n")
	return true


func is_cg_unlocked(cg_id: String) -> bool:
	return unlocked_cgs.get(cg_id, false) == true


func is_bgm_unlocked(bgm_id: String) -> bool:
	return unlocked_bgms.get(bgm_id, false) == true


func unlock_cg(cg_id: String) -> bool:
	if cg_id.is_empty():
		return false
	if unlocked_cgs.get(cg_id, false) == true:
		return false
	unlocked_cgs[cg_id] = true
	save_unlocks()
	unlock_changed.emit()
	return true


func unlock_bgm(bgm_id: String) -> bool:
	if bgm_id.is_empty():
		return false
	if unlocked_bgms.get(bgm_id, false) == true:
		return false
	unlocked_bgms[bgm_id] = true
	save_unlocks()
	unlock_changed.emit()
	return true


func unlock_all(cg_list: Array[Dictionary], bgm_list: Array[Dictionary]) -> void:
	for item: Dictionary in cg_list:
		unlocked_cgs[item["id"]] = true
	for item: Dictionary in bgm_list:
		unlocked_bgms[item["id"]] = true
	save_unlocks()
	unlock_changed.emit()
