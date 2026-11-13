# Echoes of Eternia

RPG de ação multiplayer em pixel art — demo acadêmica em Godot 4.

📄 **Plano de trabalho da equipe:** [docs/Echoes_of_Eternia_Plano_de_Trabalho.pdf](docs/Echoes_of_Eternia_Plano_de_Trabalho.pdf) (também em `.docx`). Leia antes de começar.

## Versão do Godot

**Godot 4.7.2 standard** (não .NET)

Todos os PCs precisam da **mesma versão** e dos **Export Templates** dessa versão.

## Equipe e donos

Só o dono edita as cenas `.tscn` da sua área.

| Papel | Responsável | Áreas |
|---|---|---|
| A — Rede e menus | | `scripts/multiplayer/`, NetworkManager, menus, `net_test`, overlay F3 |
| B — Player e combate | | `scenes/characters/`, `scripts/player/`, `scripts/combat/`, ClassData |
| C — Mundo e inimigos | | `scenes/maps/`, `scenes/enemies/`, `scenes/npcs/`, `scripts/enemies/`, `scripts/quests/` |
| D — UI, polimento e entrega | | `scenes/ui/`, efeitos, áudio, exportação |

## Primeiros passos

1. Clone **fora** do OneDrive/Google Drive (ex.: `C:\Dev\EchoesOfEternia`).
2. Abra o `project.godot` no Godot.
3. Rode o teste de rede (Gate 0) — veja abaixo.

## Rodar o jogo

**F5** abre o **menu**: digite seu nome e escolha **Hospedar partida** (mostra seus IPs — clique para copiar — e a porta) ou **Entrar em partida** (IP e porta do host). Por enquanto os dois botões só abrem o jogo local; a conexão real chega na E5.

No jogo, controles: **WASD** ou **setas**.

**Mapa da vila:** `scenes/maps/village.tscn`. Para editar, abra a cena e pinte com o painel TileMap: `Ground` (chão, terra, água), `GroundDetail` (flores pequenas) ou `Objects` (árvores, casas, barracas — com colisão). Mantenha as saídas norte e leste livres: elas levam às futuras áreas.

**Arte:** pacote Ninja Adventure (CC0). Veja `assets/LICENSES.md` antes de adicionar qualquer asset.

## Teste de rede (Gate 0)

A cena de teste fica em `scenes/debug/net_test.tscn` (não é a cena principal: abra-a e rode com **F6**, "Run Current Scene").

**No editor (mesmo PC):** Debug → Customize Run Instances → ative *Enable Multiple Instances*, quantidade 2.
Na instância 1 clique **Hospedar**; na 2, **Entrar** com `127.0.0.1`. O log deve mostrar `pong ... ms` nas duas.
Atalho: nos argumentos de cada instância use `--host` ou `--join=127.0.0.1`.

**Entre PCs (LAN):** PC A clica **Hospedar** e lê o IPv4 mostrado na tela. PC B digita esse IP e clica **Entrar**.
Na primeira execução o Windows pergunta sobre o firewall: permita em **redes privadas** (porta UDP 7777).

**Entre PCs (Tailscale):** igual, usando o IP `100.x.y.z` do host mostrado no app do Tailscale.

**Pelo .exe:** `EchoesOfEternia.exe res://scenes/debug/net_test.tscn -- --host` (ou `-- --join=192.168.0.10`).

## Exportar para Windows

Project → Export → *Windows Desktop* → Export Project. Saída em `export/windows/` (ignorada pelo git).
Executáveis são distribuídos pela **Release** do GitHub, nunca commitados.
O `.exe` não é assinado: no aviso do Windows clique em **Mais informações → Executar assim mesmo**.

## Fluxo de trabalho

`git pull` na `main` → branch `feat/<assunto>` → commits pequenos → PR testado → outra pessoa aprova → merge.
Detalhes na seção 7 do plano de trabalho.
