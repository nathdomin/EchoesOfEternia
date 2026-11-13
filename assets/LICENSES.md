# Licenças dos assets

Registre aqui **todo** pacote adicionado ao projeto, antes do primeiro commit que o usa.

| Pacote | Autor | Licença | Link | Onde está |
|---|---|---|---|---|
| Ninja Adventure Asset Pack | Pixel-Boy & AAA | CC0 1.0 (`assets/NINJA_ADVENTURE_LICENSE.txt`) | https://pixel-boy.itch.io/ninja-adventure-asset-pack | `assets/*/ninja/`, `audio/music/` |

**Regra:** o jogo usa **um único estilo** (Ninja Adventure, top-down 16×16). Não adicionar pacotes de outro estilo.
O pacote completo (89 MB) não está no repositório: só copiamos o que é usado. Para adicionar algo, baixe o pacote no link acima e copie apenas o necessário.

## O que foi copiado
- **Personagens** (`assets/characters/ninja/`): Knight (Guerreiro), SorcererBlack (Mago), Hunter (Arqueiro), OldMan e Noble (NPCs), `Shadow.png`.
  Folhas: `Walk.png` = 4 colunas (baixo, cima, esquerda, direita) × 4 frames; `Idle.png`/`Attack.png` = 4 direções × 1 frame.
  As animações prontas ficam em `resources/characters/*_frames.tres`.
- **Monstros** (`assets/enemies/ninja/`): Slime, Slime2, Mushroom, Skull, BlueBat; chefe GiantSlime.
- **Tilesets** (`assets/environments/ninja/tilesets/`): Floor, FloorDetail, Nature, House, Water, Dungeon, Relief. TileSet do jogo: `assets/environments/ninja/ninja_tileset.tres`.
- **Cenário animado** (`assets/environments/ninja/animated/`): Flag, Flower, Water Ripples, Plant.
- **Efeitos** (`assets/effects/ninja/`): Attack, Elemental, Environment, Magic, Particle, Projectile, Slash, Smoke.
- **UI** (`assets/ui/ninja/`): Dialog, Emote, Font, Receptacle (barras/corações), Skill Icon, Theme Wood.
- **Músicas** (`audio/music/`): Village, Dark Forest, Dungeon, Fight.
