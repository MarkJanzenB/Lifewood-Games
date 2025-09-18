# res://scripts/dev/diagnostics_panel.gd
extends Panel

@onready var ip_label: Label = $Margin/VBox/IP
@onready var ports_label: Label = $Margin/VBox/Ports
@onready var discovery_label: Label = $Margin/VBox/Discovery
@onready var peers_label: Label = $Margin/VBox/Peers

var _timer: Timer

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.one_shot = false
	add_child(_timer)
	_timer.timeout.connect(_refresh)
	_timer.start()
	_refresh()

func _refresh() -> void:
	var ip: String = NetworkManager.get_local_ipv4()
	if ip == "":
		ip = "(unknown)"
	var port_info: String = "Game: %d, Discovery: %d" % [NetworkManager.DEFAULT_PORT, NetworkManager.DISCOVERY_PORT]
	var disc: Dictionary = NetworkManager.discovery.get_stats() if NetworkManager.discovery != null else {}
	var disc_txt: String = "listening=%s, found=%s, pkts=%s, last_ms=%s" % [
		str(disc.get("listening", false)),
		str(disc.get("discovered_count", 0)),
		str(disc.get("packets", 0)),
		str(disc.get("last_packet_ms", 0))
	]
	var peers_arr: Array = NetworkManager.players.keys()
	var peers_txt: String = ""
	for i in range(peers_arr.size()):
		peers_txt += str(peers_arr[i])
		if i < peers_arr.size() - 1:
			peers_txt += ", "
	ip_label.text = "Local IP: %s" % ip
	ports_label.text = port_info
	discovery_label.text = "Discovery: %s" % disc_txt
	peers_label.text = "Peers: %s" % peers_txt
