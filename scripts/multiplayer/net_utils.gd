class_name NetUtils
extends RefCounted
## Funcoes de rede reutilizadas pelo menu e pelo teste de rede.

const DEFAULT_PORT := 7777


## Lista os IPv4 desta maquina que outros PCs podem usar para conectar.
## Cada item: { "ip": String, "kind": "LAN" | "Tailscale" }.
static func local_ipv4() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for addr in IP.get_local_addresses():
		if not is_valid_ipv4(addr):
			continue
		if addr.begins_with("127.") or addr.begins_with("169.254."):
			continue
		out.append({"ip": addr, "kind": "Tailscale" if is_tailscale(addr) else "LAN"})
	# LAN primeiro, depois Tailscale
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.kind == "LAN" and b.kind != "LAN")
	return out


## Tailscale usa a faixa CGNAT 100.64.0.0/10 (100.64.x.x ate 100.127.x.x).
static func is_tailscale(ip: String) -> bool:
	var parts := ip.split(".")
	return parts.size() == 4 and parts[0] == "100" and int(parts[1]) >= 64 and int(parts[1]) <= 127


static func is_valid_ipv4(ip: String) -> bool:
	var parts := ip.strip_edges().split(".")
	if parts.size() != 4:
		return false
	for p in parts:
		if not p.is_valid_int() or int(p) < 0 or int(p) > 255:
			return false
	return true


## Aceita IPv4 ou "localhost".
static func is_valid_host(host: String) -> bool:
	host = host.strip_edges()
	return host == "localhost" or is_valid_ipv4(host)


static func is_valid_port(text: String) -> bool:
	return text.strip_edges().is_valid_int() and int(text) >= 1024 and int(text) <= 65535
