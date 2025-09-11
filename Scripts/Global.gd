# Global.gd
# FINAL, DEFINITIVE VERSION - Uses the "Minimized State" window hiding technique.
extends Node

const LOCK_FILE_PATH = "user://lifewood_launcher.lock"

# --- State Variables ---
var process_monitor_timer: Timer
var monitored_game_pid: int = 0
# NEW: Variables to store the window's state before we hide it.
var _original_window_size: Vector2i
var _original_window_position: Vector2i

func _enter_tree():
	# --- NEW, ROBUST SINGLE INSTANCE LOCK ---
	# Declare the 'file' variable ONCE at the top of the function.
	var file: FileAccess 
	
	if FileAccess.file_exists(LOCK_FILE_PATH):
		# A lock file exists, so we must investigate.
		# Now we just ASSIGN to 'file', we don't declare it with 'var'.
		file = FileAccess.open(LOCK_FILE_PATH, FileAccess.READ)
		var locked_pid = file.get_as_text().to_int()
		file.close()
		
		if OS.is_process_running(locked_pid):
			OS.alert("Lifewood Game Collection is already running.", "Launcher Active")
			get_tree().quit()
			return
		else:
			print("Found stale lock file from a crashed instance. Overwriting.")
	
	var own_pid = OS.get_process_id()
	
	# Here too, we just ASSIGN to 'file'.
	file = FileAccess.open(LOCK_FILE_PATH, FileAccess.WRITE)
	file.store_string(str(own_pid))
	file.close()
	print("Launcher started with PID: ", own_pid, ". Lock file created.")
	
	
	
# --- This is the new, refactored monitoring function ---
func monitor_game_process(pid: int):
	if pid == 0:
		print("Invalid PID received. Cannot monitor process.")
		return
	
	monitored_game_pid = pid
	print("Game process started with PID: ", monitored_game_pid, ". Minimizing launcher.")
	
	# --- IMPLEMENTING YOUR "CHEAT" SOLUTION ---
	# 1. Store the current window state so we can restore it later.
	_original_window_size = get_window().size
	_original_window_position = get_window().position
	
	# 2. Make the window tiny and unresizable.
	get_window().set_flag(Window.FLAG_RESIZE_DISABLED,true)
	get_window().size = Vector2i(1, 1) # Set to a single pixel.
	
	# 3. Move it to the bottom-left corner of the primary screen.
	var primary_screen = DisplayServer.get_primary_screen()
	var screen_size = DisplayServer.screen_get_size(primary_screen)
	# Position is (X, Y). We want X=0 and Y at the very bottom.
	get_window().position = Vector2i(0, screen_size.y - 1)
	
	# Start the timer to check when the game closes.
	if process_monitor_timer == null:
		process_monitor_timer = Timer.new()
		process_monitor_timer.wait_time = 2.0
		process_monitor_timer.timeout.connect(_on_process_monitor_timeout)
		add_child(process_monitor_timer)
	
	process_monitor_timer.start()

# --- This is the new, refactored restore function ---
func _on_process_monitor_timeout():
	if OS.is_process_running(monitored_game_pid):
		return
	
	print("Game process with PID: ", monitored_game_pid, " has ended. Restoring launcher.")
	
	process_monitor_timer.stop()
	monitored_game_pid = 0
	
	# --- RESTORE THE WINDOW TO ITS ORIGINAL STATE ---
	# 1. Restore the original size and position we saved earlier.
	get_window().size = _original_window_size
	get_window().position = _original_window_position
	
	# 2. Return control of resizability to the project settings default.
	get_window().set_flag(Window.FLAG_RESIZE_DISABLED, false)
