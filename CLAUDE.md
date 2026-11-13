# Echoes of Eternia — instruções para o Claude Code

**MMORPG** em pixel art (Godot 4 + GDScript): servidor dedicado na nuvem, contas com senha, personagens salvos, até 16 jogadores, zonas. Pequeno, mas um MMO de verdade — **não é uma demo**. Plano completo da equipe (v3): `docs/Echoes_of_Eternia_Plano_de_Trabalho.docx`.

## Regras de execução
1. Uma etapa (E1…E24) por vez. **Não avançar para a próxima etapa sem autorização.**
2. Entregar funcionalidade **testável** e dizer como testar. Código "aparentemente completo" não conta.
3. Corrigir erros antes de adicionar recursos. Não substituir o que já funciona sem necessidade.
4. Servidor e rede são prioridade. Todo sistema novo nasce pensando em servidor dedicado + persistência.
5. Respeitar o dono de cada cena (tabela no README). Não editar `.tscn` de outro papel sem pedido explícito.

## Roteiro (fases e gates, sem datas)
- **Fase 1 ✅ Fundação:** E1 projeto · E2 personagem · E3 vila · E4 menu · E5 NetworkManager.
- **Fase 2 Servidor e contas:** E6 servidor dedicado (`--server`, 16 vagas, exportação Linux, deploy na VM) · E7 cadastro/login (hash + salt) + DTLS · E8 personagem salvo · E9 jogadores por zona (spawner, nomes, interpolação, late join) · E10 quedas/reconexão + teste com a VM. **Gate 1:** servidor na VM com contas e persistência, 2+ PCs jogando.
- **Fase 3 Combate:** E11 Health/Hitbox · E12 ataque validado no servidor + quadro do alvo · E13 monstros por zona com barra de vida · E14 morte/respawn · E15 teste pela internet. **Gate 2 / tag `v0.2-p0`.**
- **Fase 4 Sistemas de MMO:** E16 XP/níveis · E17 classes + habilidades + hotbar · E18 inventário/itens/loot/equipamento · E19 chat · E20 grupo · E21 NPC/missões + rastreador · E22 HUD completa. **Gate 3.**
- **Fase 5 Zonas:** E23 floresta + passagem entre zonas · E24 dungeon + chefe (bônus). **Feature freeze.**
- **Fase 6** polimento + teste de carga com 16 clientes · **Fase 7** entrega (servidor na VM, cliente .exe, apresentação).
- P2 (só depois do freeze): comércio, guildas, ranking, minimapa, emotes, web.

## Arquitetura (decisões fechadas)
- **Servidor dedicado headless**, mesmo projeto: `--server` (ou export com a feature `dedicated_server`) abre `scenes/server/server_main.tscn`, sem jogador próprio, câmera, som ou HUD. Exportado para Linux (x86_64 e ARM64) e hospedado em VM gratuita (Oracle Always Free São Paulo; alternativa Azure for Students).
- ENet UDP porta 7777, até **16 jogadores**; DTLS a partir da E7.
- **Cliente** é autoridade do movimento do próprio personagem (servidor confere velocidade). **Servidor** é autoridade de: contas, persistência, IA dos monstros, dano, vida, morte, XP, itens, loot, missões, chat e grupo. Lógica disso roda sob `multiplayer.is_server()`.
- Contas: senha só como hash + salt. Persistência em JSON por conta/personagem no servidor (`user://`), salvamento atômico e periódico.
- Zonas: vila, floresta, dungeon como cenas separadas; o servidor mantém todas; cada cliente só recebe a sua zona (visibilidade do sincronizador/spawner por zona).
- Ataque: cliente pede via RPC → servidor valida (alcance, recarga) → aplica → estado sincronizado.
- Tudo que existe na rede nasce por `MultiplayerSpawner` (late join). `MultiplayerSynchronizer` para posição + animação; remotos interpolados.
- Checagem de versão no aperto de mão com `GameVersion.VERSION`.
- Componentes: `HealthComponent`, `HitboxComponent`; dados em Resources (`ClassData`, `ItemData`, tabela de XP) — nunca hardcoded.

## Sistemas de MMO (onde cada um entra)
- E5 mensagens de sistema · E9 nome sobre cada jogador, mundo compartilhado · E12/E13 barra de vida, quadro do alvo · E16 level up · E17 hotbar 1–4 · E18 inventário/loot/equipamento · E19 chat (global, grupo, sistema) · E20 grupo + quadro do grupo · E21 NPC com diálogo no estilo manuscrito + rastreador de missão · Fase 6 números de dano, painel F3.

## Pixel art e assets
- Viewport 480×270, stretch `viewport`, scale `integer`, filtro padrão Nearest, janela 1440×810 (3×), renderer Compatibility (por isso partículas são `CPUParticles2D`).
- Base visual única: **Ninja Adventure Asset Pack** (Pixel-Boy & AAA, CC0), top-down 16×16. Não misturar com outros estilos. Detalhes do que foi copiado em `assets/LICENSES.md`.
- Personagens: `AnimatedSprite2D` com `resources/characters/<nome>_frames.tres` (animações `idle_/walk_/attack_` + `down/up/left/right`, e `dead`). Sombra `assets/characters/ninja/Shadow.png` sob cada personagem.
- Atmosfera: `scenes/maps/ambience.tscn` (CanvasModulate, folhas, vaga-lumes, feixe de luz, vinheta `shaders/vignette.gdshader`).

## Convenções
- GDScript com tipagem estática (`:=`, `-> void`), tabs, snake_case para arquivos.
- Scripts em `scripts/<sistema>/`, cenas em `scenes/<categoria>/`.
- `*.import` são versionados; `.godot/` e `export/` não.
- Cena inicial: `scenes/ui/main_menu.tscn` (menu). O jogo é `scenes/main/main.tscn`. `scenes/debug/net_test.tscn` é o teste de rede do Gate 0 (rodar com F6).
- Autoload `Session` (`scripts/systems/session.gd`): modo HOST/JOIN, IP, porta e nome escolhidos no menu. O NetworkManager (E5) lê daqui.
- `NetUtils` (`scripts/multiplayer/net_utils.gd`): porta padrão, lista de IPv4 (LAN/Tailscale) e validação de IP/porta. Reutilizar em vez de duplicar.
- UI: tema global `resources/ui/ninja_theme.tres` (Theme Wood do Ninja Adventure). Variações: `TextMenuButton` (botão só texto, dourado ao focar; o menu põe a seta como ícone) e `DarkPanel` (painel escuro translúcido). Não nomear variações com nomes de classes do Godot (ex.: `MenuButton`), senão o tema não aplica. Fontes Kenney (CC0) em `assets/ui/fonts/`: `kenney_pixel.ttf` tamanho 16 (texto) e `kenney_mini.ttf` tamanhos 8/16/24 (títulos). Não usar a `NormalFont.ttf` do Ninja Adventure: o "i" e o espaço são defeituosos.
- Identidade visual do menu: **manuscrito medieval iluminado**. Pergaminho e moldura com vinhas em `shaders/parchment.gdshader`; capitular azul e dourada em `shaders/illuminated_box.gdshader`, com janela em arco mostrando a vila ao vivo (SubViewport). Letra gótica pixel **Jacquard 24** (títulos, tamanhos múltiplos de 24) e **Jacquard 12** (opções, tamanho 24). Variações de tema em tinta: `InkMenuButton` (vermelho de rubrica ao focar), `InkLabel`, `InkLineEdit` (só linha embaixo), `InkFlatButton`. Usar o mesmo estilo nas próximas telas (pausa, diálogo, missão).
- Input actions: `move_left/right/up/down` (WASD + setas), definidas no `project.godot`.

## Estado das etapas
- E1 ✅ estrutura e config pixel art
- E2 ✅ player local (8 direções de movimento, animação em 4 direções, sombra, câmera) — `scenes/characters/player.tscn`, `scripts/player/player.gd`
- E3 ✅ vila 56×36 — `scenes/maps/village.tscn`, `scripts/maps/village.gd` (SpawnPoint, `get_bounds()`), `scripts/main/main.gd`
- E4 ✅ menu Hospedar/Entrar — `scenes/ui/main_menu.tscn`, `scripts/ui/main_menu.gd` (valida IP/porta, lista IPs com clique para copiar, grava em `Session`; ainda sem rede real)
- E5 ✅ NetworkManager — `scripts/multiplayer/network_manager.gd` (autoload): host/cliente a partir de `Session`, aperto de mão (versão + nome, nomes repetidos viram "Nome 2"), lista `players` sincronizada só para jogadores aceitos, recusa por versão/partida cheia, timeouts de 3–6 s, mensagens de sistema. HUD de rede `scenes/ui/net_hud.tscn`. Esc no jogo volta ao menu; o motivo da saída aparece no menu.
- Gate 0 ⏳ falta o teste entre 2 PCs reais

## Rede (como usar)
- Lógica de jogo que muda estado oficial roda só no servidor (`multiplayer.is_server()`); RPCs do servidor para clientes usam `NetworkManager._broadcast` (só jogadores aceitos).
- Sinais úteis: `connection_ready`, `connection_ended(reason)`, `player_joined(id, name)`, `player_left(id, name)`, `players_changed`, `system_message(text)`.
- Linha de comando (pula o menu): `--host`, `--join=IP`, `--port=N`, `--name=X`. Só em build de debug: `--fake-version=X` (testa a recusa por versão).

## Mapas
- TileSet `assets/environments/ninja/ninja_tileset.tres`: fontes 0 Floor, 1 Nature, 2 House, 3 Water, 4 FloorDetail; physics layer 0 = colisão.
- Camadas da vila: `Ground` (chão/terra/água, z -3), `GroundDetail` (flores pequenas, z -2), `Objects` (árvores, casas, props; y-sort).
- Objetos grandes são tiles multi-célula com colisão só na base (tronco/parede) e `y_sort_origin` na base: o player passa atrás de copas e telhados.
- Para adicionar um objeto grande novo no TileSet: criar o tile com o tamanho certo no atlas, `texture_origin` −8 nos eixos de tamanho par, colisão na base e `y_sort_origin` na base.
