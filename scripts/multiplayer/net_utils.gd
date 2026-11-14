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


## Aceita IPv4 ou nome de dominio (ex.: localhost, meuservidor.duckdns.org).
static func is_valid_host(host: String) -> bool:
	host = host.strip_edges()
	if is_valid_ipv4(host):
		return true
	var re := RegEx.create_from_string("^(?=.{1,253}$)([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)([.][A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$")
	return re.search(host) != null and not host.replace(".", "").is_valid_int()


static func is_valid_port(text: String) -> bool:
	return text.strip_edges().is_valid_int() and int(text) >= 1024 and int(text) <= 65535
