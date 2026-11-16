# Atualiza o servidor da VM para a ultima versao publicada (rodar no PC com a chave SSH).
# A propria VM baixa os arquivos do repositorio publico de downloads; nada
# precisa ser copiado para este PC. Salva os personagens e faz backup antes.
# Uso: powershell -ExecutionPolicy Bypass -File .\atualizar_servidor.ps1 -Ip 152.67.51.151 -Chave "C:\caminho\chave.key"
param(
	[Parameter(Mandatory = $true)][string]$Ip,
	[Parameter(Mandatory = $true)][string]$Chave,
	[string]$Usuario = "ubuntu"
)
$ErrorActionPreference = "Stop"
$base = "https://github.com/nathdomin/EchoesOfEternia-releases/releases/latest/download"
# Uma linha so (sem aspas duplas): o PowerShell 5 estraga aspas passadas ao ssh.
$cmd = 'set -e; d=$(mktemp -d); cd $d; b=echoes_server.x86_64; if [ $(uname -m) = aarch64 ]; then b=echoes_server.arm64; fi; ' +
	'for f in $b update_server.sh stop_server.sh echoes-server.service; do curl -fsSL -o $f ' + $base + '/$f; done; ' +
	'echo Baixado: $b; sudo bash update_server.sh ./$b; cd /; rm -rf $d'
ssh -i $Chave -o StrictHostKeyChecking=accept-new "$Usuario@$Ip" $cmd
if ($LASTEXITCODE -ne 0) { throw "A atualizacao falhou (veja as mensagens acima)." }
Write-Host ""
Write-Host "Servidor atualizado. Os jogadores recebem a versao nova sozinhos ao abrir o jogo."
