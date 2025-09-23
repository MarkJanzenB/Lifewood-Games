# dev_world.gd - DEFINITIVE SYNCHRONIZATION BARRIER
# This scene's ONLY job is to report when it's ready to the server
# CRITICAL: This scene must NEVER be run directly from the editor (F5/Play Scene)
# It has hard dependencies on NetworkManager's multiplayer session and player data
# All testing must begin from main menu -> lobby -> "Start Game" button

extends Node2D

# This function runs the moment this scene becomes ready on any machine (client or server)
func _ready():
	print("[DevWorld] Scene loaded for peer ", multiplayer.get_unique_id(), ". Reporting readiness to server.")
	
	# Immediately send a message to the SERVER ONLY (peer_id = 1)
	# This RPC says: "I, [my_unique_id], have successfully loaded and am ready."
	NetworkManager.report_readiness.rpc_id(1, multiplayer.get_unique_id())
