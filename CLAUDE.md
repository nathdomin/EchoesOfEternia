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
- Viewport 640×360, stretch `viewport`, scale `integer`, filtro padrão Nearest, janela 1280×720, renderer Compatibility.
- Base visual: Kenney Roguelike/RPG Pack (top-down 16×16, CC0). Tiny Town só na vila. Nunca misturar perspectivas.
- Personagens Kenney têm 1 frame: animar com tween ("bob"), flip_h e flash.
- Registrar todo pacote em `assets/LICENSES.md`.

## Convenções
- GDScript com tipagem estática (`:=`, `-> void`), tabs, snake_case para arquivos.
- Scripts em `scripts/<sistema>/`, cenas em `scenes/<categoria>/`.
- `*.import` são versionados; `.godot/` e `export/` não.
- Cena principal: `scenes/main/main.tscn`. `scenes/debug/net_test.tscn` é o teste de rede do Gate 0 (rodar com F6).
- Input actions: `move_left/right/up/down` (WASD + setas), definidas no `project.godot`.
- Gráficos atuais são placeholders (`assets/*/placeholder_*.png`) até o pacote Kenney ser baixado.

## Estado das etapas
- E1 ✅ estrutura e config pixel art
- E2 ✅ player local (8 direções, bob/flip, câmera) — `scenes/characters/player.tscn`, `scripts/player/player.gd`
- Gate 0 ⏳ falta o teste entre 2 PCs reais
