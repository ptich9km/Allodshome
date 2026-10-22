extends RefCounted
## Sandbox for save tests (22.10).
##
## Player complaint: «saved games disappear — they are visible until the game
## is closed». The cause was that every headless run of the project shares one
## `user://` (`%APPDATA%/Godot/app_userdata/<config/name>`), so a test that
## wiped or wrote the slots destroyed the real saves of the player.
##
## Any test that touches saved slots MUST call `use_test_dir(...)` first: after
## that `SaveSystem.slot_path()` and friends point to the test directory and the
## player's `user://saves/` is never opened, never wiped and never written.

const TEST_DIR := "user://test_saves/"


## Switch SaveSystem to a scratch directory and clean it.
static func use_test_dir(path: String = TEST_DIR) -> String:
	SaveSystem.use_test_dir(path)
	wipe(path)
	return path


## Remove every slot of a directory: the slot folders (22.10: a slot is a
## directory with hero/map/process and the world files) and the flat files
## of the previous one-file format, if an old test run left them.
static func wipe(path: String = TEST_DIR) -> void:
	var dir := path if path.ends_with("/") else path + "/"
	for raw_slot in SaveSystem.PLAYER_SLOTS + [SaveSystem.AUTOSAVE_SLOT]:
		var slot := str(raw_slot)
		_remove_tree(dir + slot)
		for raw_suffix in [".json", ".json.bak", ".json.tmp"]:
			var p: String = dir + slot + str(raw_suffix)
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## Delete a directory with everything inside it.
static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d != null:
		d.list_dir_begin()
		var fn := d.get_next()
		while fn != "":
			var child := path + "/" + fn
			if d.current_is_dir():
				_remove_tree(child)
			else:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
			fn = d.get_next()
		d.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## True when the saves are kept in the test directory, not in user://saves/.
static func is_sandboxed() -> bool:
	return SaveSystem.dir() != SaveSystem.DIR
