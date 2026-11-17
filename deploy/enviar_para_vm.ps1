# Envia o servidor para a VM e instala (rodar no PC Windows que tem a chave SSH).
# Uso (PowerShell, dentro da pasta do pacote):
#   .\enviar_para_vm.ps1 -Ip 123.45.67.89 -Chave C:\caminho\ssh-key.key
#   .\enviar_para_vm.ps1 -Ip ... -Chave ... -Atualizar   (versao nova, faz backup antes)
# Usa o ssh/scp que ja vem no Windows 10/11. Escolhe ARM64 ou x86_64 sozinho.
param(
	[Parameter(Mandatory = $true)][string]$Ip,
	[Parameter(Mandatory = $true)][string]$Chave,
	[string]$Usuario = "ubuntu",
	[switch]$Atualizar
)
$ErrorActionPreference = "Stop"
$aqui = $PSScriptRoot
$destino = "$Usuario@$Ip"
$ssh = @("-i", $Chave, "-o", "StrictHostKeyChecking=accept-new")

# O ssh do Windows recusa chave que outros usuarios podem ler.
icacls $Chave /inheritance:r /grant:r "$($env:USERNAME):R" | Out-Null

Write-Host ">> Conferindo a arquitetura da VM"
$arch = (ssh @ssh $destino "uname -m").Trim()
$bin = if ($arch -eq "aarch64") { "echoes_server.arm64" } else { "echoes_server.x86_64" }
Write-Host "   $arch -> $bin"

Write-Host ">> Enviando os arquivos"
$arquivos = @($bin, "install_server.sh", "update_server.sh", "stop_server.sh", "echoes-server.service", "configurar_vm.sh") |
	ForEach-Object { Join-Path $aqui $_ }
scp @ssh @arquivos "${destino}:~/"

$script = if ($Atualizar) { "update_server.sh" } else { "install_server.sh" }
Write-Host ">> Rodando $script na VM"
ssh @ssh $destino "sudo bash ~/$script ~/$bin"

Write-Host ""
Write-Host "Pronto. No jogo: Entrar no mundo -> IP $Ip, porta 7777."
Write-Host "Logs: ssh -i $Chave $destino `"sudo journalctl -u echoes-server -f`""
