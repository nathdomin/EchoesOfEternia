#!/usr/bin/env bash
# Configuracoes da VM para o servidor do jogo. Pode rodar quantas vezes quiser.
# Chamado por install_server.sh e update_server.sh (ou: sudo bash configurar_vm.sh).
#  1. Porta alternativa: a UDP 443 e redirecionada para a porta do jogo.
#     Redes de faculdade e empresa costumam bloquear a 7777, mas liberam a 443
#     (HTTP/3); o cliente tenta a 443 sozinho. No painel da Oracle, a Security
#     List tambem precisa liberar UDP 443.
#  2. Atualizacoes automaticas do Ubuntu sempre as 04:00 de Brasilia: elas
#     reiniciam o servidor (salva todos e volta em segundos).
#  3. Backup diario dos dados (contas e personagens) as 03:30 de Brasilia em
#     /var/backups/echoes/diario-AAAA-MM-DD.tgz; guarda os dos ultimos 7 dias
#     (os de antes de cada atualizacao, "dados-*.tgz", ficam ate 30 dias).
set -euo pipefail
PORT="${ECHOES_PORT:-${PORT:-7777}}"
[[ -f /etc/default/echoes-server ]] && . /etc/default/echoes-server && PORT="${ECHOES_PORT:-$PORT}"
ALT_PORT="${ALT_PORT:-443}"
if [[ $EUID -ne 0 ]]; then echo "Rode com sudo."; exit 1; fi

if [[ "$ALT_PORT" != "0" && "$ALT_PORT" != "$PORT" ]]; then
  echo ">> Porta alternativa: UDP $ALT_PORT -> $PORT"
  if ! iptables -t nat -C PREROUTING -p udp --dport "$ALT_PORT" -j REDIRECT --to-ports "$PORT" 2>/dev/null; then
    iptables -t nat -A PREROUTING -p udp --dport "$ALT_PORT" -j REDIRECT --to-ports "$PORT"
  fi
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
  fi
fi

echo ">> Atualizacoes automaticas do Ubuntu: todo dia as 04:00 de Brasilia (07:00 UTC)"
mkdir -p /etc/systemd/system/apt-daily-upgrade.timer.d
cat > /etc/systemd/system/apt-daily-upgrade.timer.d/echoes.conf <<'CFG'
[Timer]
OnCalendar=
OnCalendar=*-*-* 07:00:00 UTC
RandomizedDelaySec=0
CFG
systemctl daemon-reload
systemctl restart apt-daily-upgrade.timer

echo ">> Backup diario: 03:30 de Brasilia (06:30 UTC) em /var/backups/echoes, 7 dias"
mkdir -p /var/backups/echoes
chmod 700 /var/backups/echoes
cat > /etc/cron.d/echoes-backup <<CFG
# Echoes of Eternia: backup diario dos dados do servidor (gerado por configurar_vm.sh)
SHELL=/bin/bash
30 6 * * * root [ -d /var/lib/echoes ] && tar czf /var/backups/echoes/diario-\$(date +\%F).tgz -C /var/lib echoes && find /var/backups/echoes -name 'diario-*.tgz' -mtime +7 -delete && find /var/backups/echoes -name 'dados-*.tgz' -mtime +30 -delete
CFG
chmod 644 /etc/cron.d/echoes-backup
