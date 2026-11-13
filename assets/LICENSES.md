# Licenças dos assets

Registre aqui **todo** pacote adicionado ao projeto, antes do primeiro commit que o usa.

| Pacote | Autor | Licença | Link | Usado em |
|---|---|---|---|---|
| Roguelike Characters | Kenney | CC0 1.0 | https://kenney.nl/assets/roguelike-characters | personagens (`assets/characters/kenney_roguelike_characters/`) |
| Roguelike/RPG Pack | Kenney | CC0 1.0 | https://kenney.nl/assets/roguelike-rpg-pack | tiles e itens (`assets/environments/kenney_roguelike_rpg/`) |
| Tiny Town | Kenney | CC0 1.0 | https://kenney.nl/assets/tiny-town | vila inicial (`assets/environments/kenney_tiny_town/`) |

Regra: só pacotes **top-down 16×16** compatíveis com o Roguelike/RPG Pack. Nada isométrico.
Pacotes do itch.io: conferir a licença um a um e anotar aqui antes de usar.

## Notas de uso das folhas
- `roguelike_characters.png` e `roguelike_rpg.png`: tiles 16×16 com **1 px de margem** (passo de 17 px). Tile (coluna c, linha r) = `Rect2(c*17, r*17, 16, 16)`.
- `tiny_town.png` (versão *packed*): tiles 16×16 **sem margem**, 12×11 tiles.
- Personagens prontos: colunas 0–1, linhas 5–11 da folha de personagens. Herói atual: c0 r11 (guerreiro). Candidatos: maga c1 r5, arqueira c1 r7.
