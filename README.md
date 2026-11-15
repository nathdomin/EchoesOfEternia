# Echoes of Eternia

MMORPG em pixel art feito em Godot 4 — servidor dedicado, contas e personagens salvos.

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

O jogo é um **MMORPG com servidor dedicado**: o servidor roda separado (na nuvem ou no seu PC) e os jogadores entram nele.

1. Rode um servidor: abra o projeto e use **Debug → Customize Run Instances** (veja abaixo) ou, com o jogo exportado, `EchoesOfEternia.exe --headless --server`.
2. **F5** abre o **menu**. Na primeira vez use **Criar conta**: nome da conta, senha (mínimo 6 caracteres, digitada duas vezes) e servidor (`127.0.0.1` se for no seu PC) com porta 7777. Depois é só **Entrar no mundo** com a mesma conta e senha.

O personagem fica salvo no servidor: ao entrar de novo você aparece onde parou. A conexão é cifrada (DTLS) e o servidor guarda só o hash da senha. O menu lembra o servidor e a conta da última vez, nunca a senha.

Ao entrar aparecem "Fulano entrou no mundo" e o nome da zona no canto. **F1** abre a ajuda (abas Controles e Como jogar; abre sozinha no primeiro jogo).

No jogo:

| Tecla | Ação |
|---|---|
| WASD / setas | andar |
| Espaço / J | ataque básico |
| 1, 2, 3 | habilidades da classe (ou clique na barra) |
| 4 | poção |
| Clique / Tab | escolher alvo |
| E | conversar com NPC / abrir baú |
| I | inventário (clique usa/equipa) |
| Enter | chat (`/g` grupo, `/z` zona, `/w Nome` sussurro, `/r` responder, `/quem`, `/convidar Nome`, `/aceitar`, `/sair`) |
| / | abre o chat já com "/" |
| G | convidar o jogador selecionado para o grupo |
| Esc | fecha janela → limpa alvo → pausa (volume da música e dos efeitos, sair para o menu) |
| F1 | ajuda: controles e como jogar |
| F3 | painel técnico (FPS, ping, zona, posição, jogadores) |

No primeiro login você escolhe a classe (Guerreiro, Mago ou Arqueiro). O Ancião, ao lado do ponto inicial, dá as primeiras missões. A estrada leste da vila leva à **Floresta Sombria** (Guarda Florestal, morcegos, slimes venenosos) e de lá à **Caverna do Rei Slime**, o chefe.

**Mapa da vila:** `scenes/maps/village.tscn`. Para editar, abra a cena e pinte com o painel TileMap: `Ground` (chão, terra, água), `GroundDetail` (flores pequenas) ou `Objects` (árvores, casas, barracas — com colisão). Mantenha as saídas norte e leste livres: elas levam às futuras áreas.

**Arte:** pacote Ninja Adventure (CC0). Veja `assets/LICENSES.md` antes de adicionar qualquer asset.

## Testar com várias janelas (sem clicar no menu)

No editor: **Debug → Customize Run Instances**, ative *Enable Multiple Instances* e use nos argumentos de cada instância:

- instância 1 (servidor): `--server`
- instância 2: `--join=127.0.0.1 --user=Ana --pass=segredo1`
- instância 3: `--join=127.0.0.1 --user=Bia --pass=segredo2`

Acrescente `--create` para criar a conta se ela ainda não existir (se já existir, o jogo entra com ela). Entrar com uma conta que já está online derruba a sessão anterior, que é salva antes.

Servidor: `--port=N`, `--max-players=N` e `--data=PASTA` (padrão 7777, 16 e `user://data`, onde ficam as contas). Cliente (só em build de debug, pula o menu): `--join=IP`, `--port=N`, `--user=X`, `--pass=Y`, `--create` e `--fake-version=0.0.0` (testa a recusa por versão diferente).

Para desligar o servidor salvando todos os personagens, crie um arquivo vazio `stop.request` na pasta de dados (na VM o `systemctl stop` faz isso). Para zerar as contas e personagens de teste do seu PC, apague a pasta `data` em `%APPDATA%\Godot\app_userdata\Echoes of Eternia\`.

**Servidor na nuvem:** passo a passo em [deploy/README.md](deploy/README.md).

## Teste de rede (Gate 0)

A cena de teste fica em `scenes/debug/net_test.tscn` (não é a cena principal: abra-a e rode com **F6**, "Run Current Scene").

**No editor (mesmo PC):** Debug → Customize Run Instances → ative *Enable Multiple Instances*, quantidade 2.
Na instância 1 clique **Hospedar**; na 2, **Entrar** com `127.0.0.1`. O log deve mostrar `pong ... ms` nas duas.
Atalho: nos argumentos de cada instância use `--host` ou `--join=127.0.0.1`.

**Entre PCs (LAN):** PC A clica **Hospedar** e lê o IPv4 mostrado na tela. PC B digita esse IP e clica **Entrar**.
Na primeira execução o Windows pergunta sobre o firewall: permita em **redes privadas** (porta UDP 7777).

**Entre PCs (Tailscale):** igual, usando o IP `100.x.y.z` do host mostrado no app do Tailscale.

**Pelo .exe:** `EchoesOfEternia.exe res://scenes/debug/net_test.tscn -- --host` (ou `-- --join=192.168.0.10`).

## Exportar

Project → Export:
- **Cliente Windows** → `export/windows/` (o jogo para os jogadores).
- **Servidor Linux x86_64** ou **Servidor Linux ARM64** → `export/server/` (para a VM; veja `deploy/README.md`).

A pasta `export/` é ignorada pelo git.
Executáveis são distribuídos pela **Release** do GitHub, nunca commitados.
O `.exe` não é assinado: no aviso do Windows clique em **Mais informações → Executar assim mesmo**.

## Fluxo de trabalho

`git pull` na `main` → branch `feat/<assunto>` → commits pequenos → PR testado → outra pessoa aprova → merge.
Detalhes na seção 7 do plano de trabalho.
