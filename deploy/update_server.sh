#!/usr/bin/env bash
# Atualiza o executavel do servidor para uma versao nova.
# Uso (na VM):  sudo bash update_server.sh ./echoes_server.arm64
set -euo pipefail
BIN="${1:-}"
if [[ $EUID -ne 0 ]]; then echo "Rode com sudo."; exit 1; fi
if [[ -z "$BIN" || ! -f "$BIN" ]]; then echo "Informe o novo executavel."; exit 1; fi

systemctl stop echoes-server
install -m 0755 -o echoes -g echoes "$BIN" /opt/echoes/echoes_server
systemctl start echoes-server
sleep 2
journalctl -u echoes-server -n 8 --no-pager
