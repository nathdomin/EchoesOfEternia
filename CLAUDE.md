# Echoes of Eternia — instruções para o Claude Code

Demo acadêmica de RPG de ação multiplayer (2–4 jogadores) em pixel art, Godot 4 + GDScript.
**É uma demo de MMORPG, não um MMORPG.** Plano completo da equipe: `docs/Echoes_of_Eternia_Plano_de_Trabalho.docx`.

## Regras de execução
1. Uma etapa (E1…E19) por vez. **Não avançar para a próxima etapa sem autorização.**
2. Entregar funcionalidade **testável** e dizer como testar. Código "aparentemente completo" não conta.
3. Corrigir erros antes de adicionar recursos. Não substituir o que já funciona sem necessidade.
4. Multiplayer é prioridade desde o início. Nada de sistemas complexos que a demo não precisa.
5. Respeitar o dono de cada cena (tabela no README). Não editar `.tscn` de outro papel sem pedido explícito.

## Gates (sem datas — uma fase só começa quando o gate anterior passa)
- **Gate 0:** 2 PCs reais trocam ping/pong (`scenes/debug/net_test.tscn`) via LAN e Tailscale; `.exe` abre num PC sem Godot.
- **Gate 1:** multiplayer (E5–E9) funcionando em 2 PCs reais. Nada de P1 antes disso.
- **Gate 2 / tag `v0.1-p0-completo`:** P0 inteiro (combate, vida, morte, respawn) entre PCs pelo `.exe`.
- **Gate 3 / feature freeze:** P1 testado. Depois só Fase 5 (polimento) e correção de bugs.

## Prioridades
- P0: jogo abre, movimento + mapa, multiplayer, combate + inimigos, vida/dano/morte.
- P1: classes + habilidades, XP/níveis, NPC + missão, HUD.
- P2 (bônus): floresta, dungeon, chefe, inventário, chat, persistência, web.

## Arquitetura (decisões fechadas)
- ENet, porta 7777, `create_server(7777, 3)` — host joga como 4º jogador.
- **Cliente** é autoridade do movimento do próprio player (authority = peer id).
- **Servidor** é autoridade de: IA dos inimigos, dano, vida, morte, respawn, XP, nível, missões. Toda lógica disso roda sob `multiplayer.is_server()`.
- Ataque: cliente pede via RPC → servidor valida (alcance, cooldown) → aplica → estado sincronizado.
- Tudo que existe na rede nasce por `MultiplayerSpawner` (garante late join).
- `MultiplayerSynchronizer` para posição + estado de animação; remotos interpolados.
- Checagem de versão no handshake com `GameVersion.VERSION` (`scripts/systems/game_version.gd`).
- Argumentos `--host` e `--join=IP` (ler `OS.get_cmdline_args()` + `OS.get_cmdline_user_args()`).
- Componentes: `HealthComponent`, `HitboxComponent`; classes como `ClassData` (Resource) — uma cena de player + 3 `.tres`.
- Balanceamento sempre em Resources (`resources/*.tres`), nunca hardcoded.

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
- Gate 0 ⏳ falta o teste entre 2 PCs reais

## Mapas
- TileSet `assets/environments/ninja/ninja_tileset.tres`: fontes 0 Floor, 1 Nature, 2 House, 3 Water, 4 FloorDetail; physics layer 0 = colisão.
- Camadas da vila: `Ground` (chão/terra/água, z -3), `GroundDetail` (flores pequenas, z -2), `Objects` (árvores, casas, props; y-sort).
- Objetos grandes são tiles multi-célula com colisão só na base (tronco/parede) e `y_sort_origin` na base: o player passa atrás de copas e telhados.
- Para adicionar um objeto grande novo no TileSet: criar o tile com o tamanho certo no atlas, `texture_origin` −8 nos eixos de tamanho par, colisão na base e `y_sort_origin` na base.
