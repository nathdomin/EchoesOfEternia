class_name NetSecurity
extends RefCounted
## Criptografia da conexao (E7): ENet com DTLS.
##
## Servidor: na primeira vez gera uma chave RSA e um certificado proprio
## (autoassinado) em <dados>/tls/. Os mesmos arquivos sao usados depois.
##
## Cliente: tudo o que passa pela rede (inclusive a senha) e cifrado.
## - Para o servidor oficial (`Session.DEFAULT_HOST`), se existir o certificado
##   dele em `res://certs/server.crt`, o cliente so conecta num servidor com
##   aquela chave (protege contra alguem se passar pelo servidor).
## - Outros enderecos (servidor no proprio PC, rede local, plano B) e cliente
##   sem o arquivo: a conexao continua cifrada, mas aceita qualquer certificado.

const SERVER_CN := "echoes-server"
const PINNED_CERT := "res://certs/server.crt"


static func server_options(data_dir: String) -> TLSOptions:
	var dir := data_dir.path_join("tls")
	var key_path := dir.path_join("server.key")
	var cert_path := dir.path_join("server.crt")
	var key := CryptoKey.new()
	var cert := X509Certificate.new()
	if FileAccess.file_exists(key_path) and FileAccess.file_exists(cert_path) \
			and key.load(key_path) == OK and cert.load(cert_path) == OK:
		return TLSOptions.server(key, cert)

	print("[Seguranca] Gerando chave e certificado do servidor (so na primeira vez)...")
	JsonStore.ensure_dir(dir)
	var crypto := Crypto.new()
	key = crypto.generate_rsa(2048)
	cert = crypto.generate_self_signed_certificate(key,
			"CN=%s,O=Echoes of Eternia,C=BR" % SERVER_CN, "20260101000000", "20460101000000")
	if key.save(key_path) != OK or cert.save(cert_path) != OK:
		push_error("Nao foi possivel salvar a chave em %s" % dir)
	return TLSOptions.server(key, cert)


static func server_cert_path(data_dir: String) -> String:
	return ProjectSettings.globalize_path(data_dir.path_join("tls").path_join("server.crt"))


static func client_options(host: String) -> TLSOptions:
	if is_pinned(host):
		var cert := load(PINNED_CERT) as X509Certificate
		if cert:
			return TLSOptions.client(cert, SERVER_CN)
	return TLSOptions.client_unsafe()


static func is_pinned(host: String) -> bool:
	return host == Session.DEFAULT_HOST and ResourceLoader.exists(PINNED_CERT)
