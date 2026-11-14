#!/bin/sh
# Chamado pelo systemd ao parar/reiniciar o servico (ExecStop).
# Pede a parada segura (o servidor salva todos os personagens, avisa os
# jogadores e fecha sozinho) e espera ate 10 s. Se nao fechar, o systemd
# encerra o processo depois disso.
touch /var/lib/echoes/stop.request
i=0
while [ -n "$MAINPID" ] && kill -0 "$MAINPID" 2>/dev/null && [ "$i" -lt 20 ]; do
  sleep 0.5
  i=$((i + 1))
done
