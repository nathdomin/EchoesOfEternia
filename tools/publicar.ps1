# Publica uma versao nova do jogo no repositorio publico de downloads.
# Antes: aumente GameVersion.VERSION (scripts/systems/game_version.gd) e
# config/version no project.godot.
# Uso: powershell -ExecutionPolicy Bypass -File tools\publicar.ps1 [-Notas "o que mudou"] [-SemExportar]
# Depois: atualize o servidor (deploy/atualizar_servidor.ps1, no PC com a chave).
# Os jogadores recebem a versao nova sozinhos ao abrir o jogo (ClientUpdater).
param(
	[string]$Notas = "",
	[switch]$SemExportar,
	[string]$Godot = "C:\Users\natha\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe"
)
$ErrorActionPreference = "Stop"
$repo = "nathdomin/EchoesOfEternia-releases"
$raiz = Split-Path $PSScriptRoot -Parent
$exp = Join-Path $raiz "export"

$linha = Select-String -Path (Join-Path $raiz "scripts\systems\game_version.gd") -Pattern 'VERSION := "(.+)"'
$versao = $linha.Matches[0].Groups[1].Value
$tag = "v$versao"
Write-Host ">> Versao $versao"
$ErrorActionPreference = "Continue"  # no PowerShell 5 o stderr do gh viraria erro
gh release view $tag --repo $repo 2>&1 | Out-Null
$ErrorActionPreference = "Stop"
if ($LASTEXITCODE -eq 0) { throw "A $tag ja foi publicada. Aumente GameVersion.VERSION." }

if (-not $SemExportar) {
	foreach ($p in @("Cliente Windows", "Servidor Linux x86_64", "Servidor Linux ARM64 (Oracle Ampere)")) {
		Write-Host ">> Exportando: $p"
		& $Godot --headless --path $raiz --export-release $p | Out-Null
		if ($LASTEXITCODE -ne 0) { throw "Falha ao exportar $p" }
	}
}
& (Join-Path $PSScriptRoot "empacotar.ps1")

$zip = Join-Path $exp "EchoesOfEternia-cliente.zip"
$manifesto = [ordered]@{
	version = $versao
	zip     = "https://github.com/$repo/releases/download/$tag/EchoesOfEternia-cliente.zip"
	sha256  = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
	size    = (Get-Item $zip).Length
}
$json = Join-Path $exp "latest.json"
[IO.File]::WriteAllText($json, ($manifesto | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))

$ativos = @($zip, $json) + (@(
	"server\echoes_server.x86_64", "server\echoes_server.arm64") | ForEach-Object { Join-Path $exp $_ }) + (@(
	"update_server.sh", "stop_server.sh", "echoes-server.service") | ForEach-Object { Join-Path $raiz "deploy\$_" })
if ($Notas -eq "") { $Notas = "Echoes of Eternia $versao." }
$Notas += "`n`n**Primeira vez:** baixe o EchoesOfEternia-cliente.zip, descompacte e abra o EchoesOfEternia.exe. Depois disso o jogo se atualiza sozinho."
Write-Host ">> Publicando $tag em $repo"
gh release create $tag --repo $repo --title "Echoes of Eternia $versao" --notes $Notas --latest @ativos
if ($LASTEXITCODE -ne 0) { throw "Falha ao publicar" }
Write-Host "Publicado: https://github.com/$repo/releases/tag/$tag"
Write-Host "Agora atualize o servidor: deploy\atualizar_servidor.ps1 -Ip IP -Chave CHAVE (no PC com a chave)"
