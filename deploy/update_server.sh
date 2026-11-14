#!/usr/bin/env bash
# Atualiza o executavel do servidor para uma versao nova.
# Uso (na VM):  sudo bash update_server.sh ./echoes_server.arm64
# Para com seguranca (salva os personagens) e faz backup dos dados em
# /var/backups/echoes/ antes de trocar.
set -euo pipefail
BIN="${1:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
if [[ $EUID -ne 0 ]]; then echo "Rode com sudo."; exit 1; fi
if [[ -z "$BIN" || ! -f "$BIN" ]]; then echo "Informe o novo executavel."; exit 1; fi

systemctl stop echoes-server
if [[ -d /var/lib/echoes ]]; then
  mkdir -p /var/backups/echoes
  BK="/var/backups/echoes/dados-$(date +%Y%m%d-%H%M%S).tgz"
  tar czf "$BK" -C /var/lib echoes
  chmod 600 "$BK"
  echo ">> Backup dos dados: $BK"
fi
install -m 0755 -o echoes -g echoes "$BIN" /opt/echoes/echoes_server
[[ -f "$HERE/stop_server.sh" ]] && install -m 0755 "$HERE/stop_server.sh" /opt/echoes/stop_server.sh
# Servico novo junto com o script? Atualiza tambem.
if [[ -f "$HERE/echoes-server.service" ]]; then
  install -m 0644 "$HERE/echoes-server.service" /etc/systemd/system/echoes-server.service
  systemctl daemon-reload
fi
systemctl start echoes-server
sleep 2
journalctl -u echoes-server -n 10 --no-pager
