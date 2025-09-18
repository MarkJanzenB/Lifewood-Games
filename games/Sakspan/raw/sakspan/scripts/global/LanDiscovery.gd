# res://scripts/global/LanDiscovery.gd
extends Node
class_name LanDiscovery

signal lobby_found(lobby_info: Dictionary)
signal started
signal stopped

var discovery_port: int = 9001
var discovery_magic: String = "SAKSPAN_V1"
var debug: bool = false

var _udp_listener: PacketPeerUDP = PacketPeerUDP.new()
var _udp_broadcaster: PacketPeerUDP = PacketPeerUDP.new()
var _poll_timer: Timer
var _broadcast_timer: Timer
var _listening: bool = false
var _discovered_lobbies: Dictionary = {}
var _pkts_received: int = 0
var _last_pkt_ms: int = 0

func _ready() -> void:
	_poll_timer = Timer.new()
	_poll_timer.one_shot = false
	_poll_timer.wait_time = 0.2
	add_child(_poll_timer)
	_poll_timer.timeout.connect(_poll)
	
	_broadcast_timer = Timer.new()
	_broadcast_timer.one_shot = false
	_broadcast_timer.wait_time = 1.0
	add_child(_broadcast_timer)
	_broadcast_timer.timeout.connect(_on_broadcast_tick)

func configure(port: int, magic: String) -> void:
	discovery_port = port
	discovery_magic = magic

func start_listening() -> void:
	if _listening:
		return
	_udp_listener = PacketPeerUDP.new()
	var err: int = _udp_listener.bind(discovery_port, "0.0.0.0")
	if err != OK:
		push_error("[Discovery] Failed to bind UDP listener: " + str(err))
		return
	_listening = true
	_discovered_lobbies.clear()
	_poll_timer.start()
	var local_ip = _get_lan_ipv4()
	print("[Discovery] Listening on UDP:", discovery_port, " from IP:", local_ip)
	started.emit()
	emit_signal("started")

func stop_listening() -> void:
	if _poll_timer:
		_poll_timer.stop()
	_listening = false
	_udp_listener = PacketPeerUDP.new()
	_discovered_lobbies.clear()
	if debug:
		print("[Discovery] Stopped listening")
	emit_signal("stopped")

func _poll() -> void:
	if not _listening:
		return
	while _udp_listener.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _udp_listener.get_packet()
		var text: String = pkt.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = parsed
		if data.get("magic", "") != discovery_magic:
			continue
		# Normalize IP field
		var ip: String = String(data.get("host_ip", data.get("ip", "")))
		data["ip"] = ip
		_discovered_lobbies[ip] = data
		_pkts_received += 1
		_last_pkt_ms = Time.get_ticks_msec()
		lobby_found.emit(data)

# --- Broadcast (host side) ---
var _payload_provider: Callable

func set_payload_provider(callable: Callable) -> void:
	_payload_provider = callable

func start_broadcasting() -> void:
	_udp_broadcaster = PacketPeerUDP.new()
	_udp_broadcaster.set_broadcast_enabled(true)
	_broadcast_timer.start()
	if debug:
		print("[Discovery] Broadcasting on UDP:", discovery_port, " targets:", _get_broadcast_candidates_ipv4())

func stop_broadcasting() -> void:
	if _broadcast_timer:
		_broadcast_timer.stop()
	_udp_broadcaster = PacketPeerUDP.new()
	if debug:
		print("[Discovery] Stopped broadcasting")

func _on_broadcast_tick() -> void:
	if _payload_provider == null:
		return
	var info: Dictionary = _payload_provider.call()
	if info.is_empty():
		return
	var bytes: PackedByteArray = JSON.stringify(info).to_utf8_buffer()
	var targets := _get_broadcast_candidates_ipv4()
	for b in targets:
		_udp_broadcaster.set_dest_address(b, discovery_port)
		var err = _udp_broadcaster.put_packet(bytes)
		if err != OK and debug:
			print("[Discovery] Failed to send to ", b, " error: ", err)
	if debug:
		print("[Discovery] Broadcast tick to", targets.size(), "targets:", targets)

# --- Helpers ---
func _get_lan_ipv4() -> String:
	var addrs: PackedStringArray = IP.get_local_addresses()
	for a in addrs:
		# Skip loopback/APIPA/virtual adapters commonly seen on Windows
		if a.begins_with("127.") or a.begins_with("0.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.56."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10."):
			return a
		if a.begins_with("172."):
			var parts := a.split(".")
			if parts.size() >= 2:
				var s := int(parts[1])
				if s >= 16 and s <= 31:
					return a
	return ""

func _get_subnet_broadcast_ipv4() -> String:
	var ip := _get_lan_ipv4()
	if ip == "":
		return ""
	var parts: PackedStringArray = ip.split(".")
	if parts.size() == 4:
		parts[3] = "255"
		return ".".join(parts)
	return ""

func _get_broadcast_candidates_ipv4() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var ip := _get_lan_ipv4()
	if ip == "":
		out.append("255.255.255.255")
		return out
	var parts: PackedStringArray = ip.split(".")
	if parts.size() != 4:
		out.append("255.255.255.255")
		return out
	var A: int = int(parts[0])
	var B: int = int(parts[1])
	var C: int = int(parts[2])
	var base: int = max(0, C & ~3)
	for i in range(base, min(base + 4, 256)):
		out.append("%d.%d.%d.255" % [A, B, i])
	var immediate: String = _get_subnet_broadcast_ipv4()
	if immediate != "":
		out.append(immediate)
	out.append("255.255.255.255")
	var seen: Dictionary = {}
	var dedup: PackedStringArray = PackedStringArray()
	for b in out:
		if not seen.has(b):
			seen[b] = true
			dedup.append(b)
	return dedup

# --- Public diagnostics ---
func is_listening() -> bool:
	return _listening

func get_discovered_count() -> int:
	return _discovered_lobbies.size()

func get_total_packets() -> int:
	return _pkts_received

func get_last_packet_ms() -> int:
	return _last_pkt_ms

func get_stats() -> Dictionary:
	return {
		"listening": _listening,
		"port": discovery_port,
		"discovered_count": _discovered_lobbies.size(),
		"packets": _pkts_received,
		"last_packet_ms": _last_pkt_ms
	}
