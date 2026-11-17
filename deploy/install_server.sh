#!/usr/bin/env bash
# Instala o servidor dedicado do Echoes of Eternia numa VM Ubuntu.
# Uso (na VM):  sudo bash install_server.sh ./echoes_server.arm64   (ou .x86_64)
# Opcional:     sudo PORT=7777 MAX_PLAYERS=16 bash install_server.sh ./echoes_server.x86_64
set -euo pipefail

BIN="${1:-}"
PORT="${PORT:-7777}"
MAX_PLAYERS="${MAX_PLAYERS:-16}"
DIR=/opt/echoes
HERE="$(cd "$(dirname "$0")" && pwd)"

if [[ $EUID -ne 0 ]]; then echo "Rode com sudo."; exit 1; fi
if [[ -z "$BIN" || ! -f "$BIN" ]]; then
  echo "Informe o executavel do servidor exportado pelo Godot."
  echo "Ex.: sudo bash install_server.sh ./echoes_server.arm64"
  exit 1
fi

echo ">> Arquitetura da VM: $(uname -m)"

echo ">> Criando usuario 'echoes' e a pasta $DIR"
id echoes >/dev/null 2>&1 || useradd --system --create-home --shell /usr/sbin/nologin echoes
mkdir -p "$DIR"
install -m 0755 -o echoes -g echoes "$BIN" "$DIR/echoes_server"
install -m 0755 "$HERE/stop_server.sh" "$DIR/stop_server.sh"

echo ">> Configuracao em /etc/default/echoes-server"
cat > /etc/default/echoes-server <<CFG
ECHOES_PORT=$PORT
ECHOES_MAX_PLAYERS=$MAX_PLAYERS
CFG

echo ">> Abrindo a porta UDP $PORT no firewall da VM"
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow "$PORT"/udp
else
  # Imagens Ubuntu da Oracle usam iptables com REJECT no fim da cadeia INPUT
  if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null; then
    iptables -I INPUT 1 -p udp --dport "$PORT" -j ACCEPT
  fi
  if ! command -v netfilter-persistent >/dev/null 2>&1; then
    echo "   Instalando iptables-persistent (a regra continua depois de reiniciar a VM)"
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent >/dev/null \
      || echo "   (aviso) nao deu para instalar: a regra some ao reiniciar a VM."
  fi
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
  fi
fi

[[ -f "$HERE/configurar_vm.sh" ]] && PORT="$PORT" bash "$HERE/configurar_vm.sh"

echo ">> Instalando o servico systemd"
install -m 0644 "$HERE/echoes-server.service" /etc/systemd/system/echoes-server.service
systemctl daemon-reload
systemctl enable --now echoes-server

sleep 2
systemctl --no-pager --lines=15 status echoes-server || true
echo
echo "Pronto. Logs ao vivo:   sudo journalctl -u echoes-server -f"
echo "Dados (contas e chave): /var/lib/echoes   Certificado: /var/lib/echoes/tls/server.crt"
echo "Lembre de liberar a porta UDP $PORT tambem no painel do provedor (Security List / NSG)."
