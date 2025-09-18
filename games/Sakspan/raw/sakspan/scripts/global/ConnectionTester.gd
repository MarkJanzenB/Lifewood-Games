# res://scripts/global/ConnectionTester.gd
extends Node

# Simple TCP connection tester
func test_tcp_connection(ip: String, port: int) -> bool:
	print("[ConnectionTest] Testing TCP connection to ", ip, ":", port)
	
	var tcp = StreamPeerTCP.new()
	var err = tcp.connect_to_host(ip, port)
	
	if err != OK:
		print("[ConnectionTest] Failed to initiate connection: ", err)
		return false
	
	# Wait up to 5 seconds for connection
	var timeout = 5.0
	var elapsed = 0.0
	
	while elapsed < timeout:
		tcp.poll()
		var status = tcp.get_status()
		
		if status == StreamPeerTCP.STATUS_CONNECTED:
			print("[ConnectionTest] TCP connection successful!")
			tcp.disconnect_from_host()
			return true
		elif status == StreamPeerTCP.STATUS_ERROR:
			print("[ConnectionTest] TCP connection failed with error")
			tcp.disconnect_from_host()
			return false
		
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	
	print("[ConnectionTest] TCP connection timed out")
	tcp.disconnect_from_host()
	return false

# Test if a host is reachable at all
func ping_test(ip: String) -> bool:
	print("[ConnectionTest] Testing basic connectivity to ", ip)
	
	# Try to resolve the IP (basic connectivity test)
	var addresses = IP.resolve_hostname(ip)
	if addresses.is_empty():
		print("[ConnectionTest] Cannot resolve IP: ", ip)
		return false
	
	print("[ConnectionTest] IP is resolvable: ", addresses[0])
	return true

# Comprehensive network test
func full_network_test(target_ip: String) -> Dictionary:
	var results = {
		"ip_valid": false,
		"ping_success": false,
		"tcp_8080": false,
		"udp_9001": false
	}
	
	# Test IP validity
	results.ip_valid = _is_valid_ip(target_ip)
	if not results.ip_valid:
		print("[ConnectionTest] Invalid IP format: ", target_ip)
		return results
	
	# Test basic connectivity
	results.ping_success = ping_test(target_ip)
	
	# Test TCP port 8080 (game connection)
	results.tcp_8080 = await test_tcp_connection(target_ip, 8080)
	
	# Test UDP port 9001 (discovery)
	var diag = preload("res://scripts/global/NetworkDiagnostics.gd").new()
	results.udp_9001 = diag.test_udp_connection(target_ip, 9001)
	
	print("[ConnectionTest] Full test results: ", results)
	return results

func _is_valid_ip(ip: String) -> bool:
	var parts = ip.split(".")
	if parts.size() != 4:
		return false
	
	for part in parts:
		var num = part.to_int()
		if num < 0 or num > 255:
			return false
		if str(num) != part:
			return false
	
	return true
