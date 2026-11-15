# Monta os pacotes da entrega a partir do que ja foi exportado (export/).
# Uso: powershell -ExecutionPolicy Bypass -File tools\empacotar.ps1
# Saida:
#   export/EchoesOfEternia-servidor.zip  servidores Linux + scripts + passo a passo (para o PC que administra a VM)
#   export/EchoesOfEternia-cliente.zip   jogo + como jogar (para os jogadores)
$ErrorActionPreference = "Stop"
$raiz = Split-Path $PSScriptRoot -Parent
$exp = Join-Path $raiz "export"
$tmp = Join-Path $exp "_pacote"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }

# Servidor
$srv = Join-Path $tmp "servidor"
New-Item -ItemType Directory -Force $srv | Out-Null
Copy-Item (Join-Path $exp "server\echoes_server.arm64"), (Join-Path $exp "server\echoes_server.x86_64") $srv
Get-ChildItem (Join-Path $raiz "deploy") -File | Copy-Item -Destination $srv
Compress-Archive -Path (Join-Path $srv "*") -DestinationPath (Join-Path $exp "EchoesOfEternia-servidor.zip") -Force

# Cliente
$cli = Join-Path $tmp "cliente"
New-Item -ItemType Directory -Force $cli | Out-Null
Copy-Item (Join-Path $exp "windows\EchoesOfEternia.exe") $cli
Copy-Item (Join-Path $raiz "docs\COMO_JOGAR.txt") $cli
Compress-Archive -Path (Join-Path $cli "*") -DestinationPath (Join-Path $exp "EchoesOfEternia-cliente.zip") -Force

Remove-Item $tmp -Recurse -Force
Get-ChildItem $exp -Filter *.zip | ForEach-Object { "{0}  {1:N1} MB" -f $_.Name, ($_.Length / 1MB) }
