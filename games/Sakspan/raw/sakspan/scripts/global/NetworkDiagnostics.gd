# res://scripts/global/NetworkDiagnostics.gd
extends Node

# Network diagnostic tool for LAN multiplayer troubleshooting
func print_network_info():
	print("=== NETWORK DIAGNOSTICS ===")
	
	# Get all local IP addresses
	var addresses = IP.get_local_addresses()
	print("Local IP Addresses:")
	for addr in addresses:
		print("  - ", addr)
	
	# Get the primary LAN IP
	var lan_ip = _get_primary_lan_ip()
	print("Primary LAN IP: ", lan_ip)
	
	# Calculate broadcast addresses
	var broadcast_candidates = _get_broadcast_candidates(lan_ip)
	print("Broadcast candidates:")
	for bc in broadcast_candidates:
		print("  - ", bc)
	
	print("=== END DIAGNOSTICS ===")

func _get_primary_lan_ip() -> String:
	var addrs: PackedStringArray = IP.get_local_addresses()
	for a in addrs:
		# Skip loopback/APIPA/virtual adapters
		if a.begins_with("127.") or a.begins_with("0.") or a.begins_with("169.254."):
			continue
		# Skip VirtualBox adapters
		if a.begins_with("192.168.56."):
			continue
		# Prefer common LAN ranges
		if a.begins_with("192.168.") or a.begins_with("10."):
			return a
		if a.begins_with("172."):
			var parts := a.split(".")
			if parts.size() >= 2:
				var s := int(parts[1])
				if s >= 16 and s <= 31:
					return a
	return ""

func _get_broadcast_candidates(ip: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if ip == "":
		out.append("255.255.255.255")
		return out
	
	var parts: PackedStringArray = ip.split(".")
	if parts.size() != 4:
		out.append("255.255.255.255")
		return out
	
	# Add subnet broadcast
	var subnet_broadcast = parts[0] + "." + parts[1] + "." + parts[2] + ".255"
	out.append(subnet_broadcast)
	
	# Add global broadcast
	out.append("255.255.255.255")
	
	return out

# Test UDP connectivity between two IPs
func test_udp_connection(target_ip: String, port: int = 9001) -> bool:
	var udp = PacketPeerUDP.new()
	udp.set_dest_address(target_ip, port)
	
	var test_message = "SAKSPAN_TEST"
	var bytes = test_message.to_utf8_buffer()
	
	var err = udp.put_packet(bytes)
	if err != OK:
		print("[NetworkTest] Failed to send UDP packet to ", target_ip, ":", port, " Error: ", err)
		return false
	
	print("[NetworkTest] UDP packet sent to ", target_ip, ":", port)
	return true

# Get network adapter information (Windows specific)
func get_network_adapters_info():
	print("=== NETWORK ADAPTERS INFO ===")
	var addresses = IP.get_local_addresses()
	for i in range(addresses.size()):
		var addr = addresses[i]
		var adapter_type = "Unknown"
		
		if addr.begins_with("127."):
			adapter_type = "Loopback"
		elif addr.begins_with("169.254."):
			adapter_type = "APIPA (No DHCP)"
		elif addr.begins_with("192.168.56."):
			adapter_type = "VirtualBox Host-Only"
		elif addr.begins_with("192.168."):
			adapter_type = "Private Network (Class C)"
		elif addr.begins_with("10."):
			adapter_type = "Private Network (Class A)"
		elif addr.begins_with("172."):
			adapter_type = "Private Network (Class B)"
		else:
			adapter_type = "Public/Other"
		
		print("Adapter ", i, ": ", addr, " (", adapter_type, ")")
	print("=== END ADAPTERS INFO ===")
