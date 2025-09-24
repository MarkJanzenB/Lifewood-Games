# res://scripts/dev/dev_world_CLEAN.gd
# CLEAN ARCHITECTURE: dev_world is ONLY a scene trigger
# NO game logic, NO spawning, NO UI management
extends Node2D

func _ready():
	"""Minimal scene trigger - reports readiness to NetworkManager"""
	await get_tree().process_frame
	
	# Safety guard
	if not multiplayer.has_multiplayer_peer():
		print("[DevWorld] ⚠️ No multiplayer peer - aborting")
		return
	
	print("[DevWorld] Scene loaded for peer ", multiplayer.get_unique_id())
	
	# Verify GameUI is present
	var game_ui = get_node_or_null("GameUI")
	if game_ui:
		print("[DevWorld] ✅ GameUI found and ready")
	else:
		print("[DevWorld] ❌ GameUI not found!")
	
	# Report readiness to NetworkManager (synchronization barrier)
	if NetworkManager and NetworkManager.has_method("report_readiness"):
		NetworkManager.report_readiness.rpc_id(1, multiplayer.get_unique_id())
		print("[DevWorld] ✅ Reported readiness to NetworkManager")
	else:
		print("[DevWorld] ❌ NetworkManager not found!")
