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


## Remove every slot file (.json, .json.bak, .json.tmp) of a directory.
static func wipe(path: String = TEST_DIR) -> void:
	var dir := path if path.ends_with("/") else path + "/"
	for raw_slot in SaveSystem.PLAYER_SLOTS + [SaveSystem.AUTOSAVE_SLOT]:
		var slot := str(raw_slot)
		for raw_suffix in [".json", ".json.bak", ".json.tmp"]:
			var p: String = dir + slot + str(raw_suffix)
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## True when the saves are kept in the test directory, not in user://saves/.
static func is_sandboxed() -> bool:
	return SaveSystem.dir() != SaveSystem.DIR
