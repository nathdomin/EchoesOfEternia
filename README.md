# Echoes of Eternia

MMORPG em pixel art feito em **Godot 4.7.2**, como demo. Os jogadores entram num mundo compartilhado hospedado num servidor dedicado na nuvem, com contas, personagens salvos e até 16 pessoas ao mesmo tempo.

**Jogar:** baixe o zip em [EchoesOfEternia-releases](https://github.com/nathdomin/EchoesOfEternia-releases/releases/latest), descompacte e abra o `EchoesOfEternia.exe` (Windows). O servidor oficial, `152.67.51.151:7777`, já vem preenchido, e o jogo se atualiza sozinho.

## O que tem

- **Mundo:** 3 zonas (vila, floresta e caverna) com passagens entre elas e baús de tesouro. Cada zona tem clima e música próprios.
- **Combate:** ataques validados no servidor e monstros com IA. O chefe, o Rei Slime, tem um ataque em área. Quem morre renasce na vila.
- **Progressão:** XP e níveis até o 10. São 3 classes (Guerreiro, Mago e Arqueiro), cada uma com 3 habilidades.
- **Itens:** inventário de 20 espaços, equipamento (arma, armadura e acessório), saque dos monstros e poções.
- **Social:** chat global, de grupo, de zona e mensagem privada. Grupos de até 4 dividem a XP e recebem a cura de grupo.
- **Missões:** NPCs com diálogo, missões encadeadas e um rastreador na tela.
- **Interface:** HUD completa e menu no estilo manuscrito medieval. O F1 abre a ajuda, com o tutorial.

## Como funciona

| Parte | Como é feita |
|---|---|
| Autoridade | O **servidor dedicado** decide dano, vida, IA dos monstros, XP, itens, saque, missões, chat e grupo. O cliente move só o próprio personagem, e o servidor confere a velocidade e recusa teletransporte. |
| Rede | ENet sobre UDP, porta 7777. Personagens e monstros nascem pelo `MultiplayerSpawner` e se sincronizam pelo `MultiplayerSynchronizer`; cada jogador só recebe a zona onde está. As posições remotas são interpoladas. |
| Segurança | A conexão é cifrada com DTLS, e o cliente só aceita o certificado do servidor oficial. As senhas ficam guardadas só como PBKDF2-HMAC-SHA256 com salt. Há bloqueio após tentativas erradas e limite de mensagens no chat. |
| Persistência | Um JSON por conta e por personagem, com gravação atômica. Salva quando o jogador sai, a cada 60 s e quando o servidor para. |
| Quedas | O cliente reconecta sozinho com um token de sessão de uso único, sem pedir a senha de novo. |
| Versões | O servidor recusa clientes de outra versão. O cliente baixa a versão nova da release, confere o SHA-256, troca o `.exe` e reabre. |
| Hospedagem | Uma VM Oracle Always Free (São Paulo) com Ubuntu e um serviço `systemd`. O custo é zero. |

Cliente e servidor são **o mesmo projeto**: com `--server`, ou exportado com a feature `dedicated_server`, o jogo abre o servidor sem janela.

## Rodar a partir do código

1. Instale o **Godot 4.7.2 standard** (não o .NET) e abra o `project.godot`.
2. No editor, vá em **Debug → Customize Run Instances**, ative *Enable Multiple Instances* e configure os argumentos:
   - instância 1 (servidor): `--server`
   - instância 2: `--join=127.0.0.1 --user=Ana --pass=segredo1 --create`
   - instância 3: `--join=127.0.0.1 --user=Bia --pass=segredo2 --create`
3. Aperte **F5**. Sem argumentos, o jogo abre o menu: use **Criar conta** com o servidor `127.0.0.1`, porta 7777.

Mais opções da linha de comando:
- **Servidor:** `--port=N`, `--max-players=N` e `--data=PASTA` (por padrão, 7777, 16 e `user://data`).
- **Cliente** (só em build de debug): `--fake-version=X`, que testa a recusa por versão.

Para parar o servidor salvando todos os personagens, crie um arquivo `stop.request` na pasta de dados.

### Controles

| Tecla | Ação |
|---|---|
| WASD / setas | andar |
| Espaço / J | atacar |
| 1, 2, 3 · 4 | habilidades da classe · poção |
| Clique / Tab | escolher alvo |
| E | falar com NPC / abrir baú |
| I | inventário |
| Enter | chat (`/g`, `/z`, `/w Nome`, `/r`, `/quem`, `/convidar Nome`, `/aceitar`, `/sair`) |
| G | convidar o jogador selecionado para o grupo |
| Esc | pausa (volume, ajuda, sair) |
| F1 / F3 | ajuda / painel técnico (FPS, ping) |

## Servidor e versões

- **Colocar o servidor numa VM:** [deploy/README.md](deploy/README.md), com o passo a passo da Oracle em [deploy/PASSO_A_PASSO_ORACLE.md](deploy/PASSO_A_PASSO_ORACLE.md).
- **Exportar** (Project → Export):
  - **Cliente Windows** sai em `export/windows/`;
  - **Servidor Linux x86_64 / ARM64** sai em `export/server/`.
- **Publicar uma versão:** aumente `GameVersion.VERSION` (`scripts/systems/game_version.gd`) e `config/version`, rode `tools/publicar.ps1` e depois `deploy/atualizar_servidor.ps1`.

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `scripts/multiplayer/` | rede, login, sincronização de personagens |
| `scripts/server/` | contas, personagens salvos, tokens de sessão, servidor |
| `scripts/combat/`, `scripts/progression/` | combate, monstros, XP, classes, itens, missões |
| `scripts/ui/` | HUD, menus, janelas |
| `scenes/maps/` | vila, floresta, caverna |
| `resources/` | dados do jogo em `.tres`: classes, habilidades, itens, monstros, missões |
| `deploy/` | instalação e atualização do servidor na VM |
| `tools/` | geração de sons e baú, empacotamento e publicação |

## Licença e créditos

- **Código:** licença [MIT](LICENSE).
- **Arte e música:** [Ninja Adventure Asset Pack](https://pixel-boy.itch.io/ninja-adventure-asset-pack) (Pixel-Boy & AAA), CC0.
- **Sons:** parte do Kenney (CC0); o resto foi gerado em `tools/gen_sfx.py`.
- **Fontes:** Pixelify Sans e Jacquard 12/24 (SIL OFL 1.1) e Kenney Mini (CC0).

Detalhes de cada asset em [assets/LICENSES.md](assets/LICENSES.md).
