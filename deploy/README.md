# Servidor dedicado na nuvem

O servidor do Echoes of Eternia roda numa VM Linux gratuita, sem janela, sempre ligado.
Os jogadores só abrem o cliente e entram com o endereço da VM.

## 1. Exportar o servidor (no PC, pelo Godot)

1. Instale os Export Templates: **Editor → Manage Export Templates → Download and Install**.
2. **Project → Export**, escolha o preset conforme a VM:
   - **Servidor Linux ARM64 (Oracle Ampere)** — VMs ARM (Oracle A1).
   - **Servidor Linux x86_64** — VMs Intel/AMD (Oracle E2.1.Micro, Azure, Google).
3. **Export Project** (desmarque *Export With Debug*). O arquivo sai em `export/server/`.

> Cliente e servidor precisam da **mesma versão** (`scripts/systems/game_version.gd`). Exporte os dois juntos.

## 2. Criar a VM

### Oracle Cloud – Always Free (recomendado, região São Paulo)
1. Crie a conta em cloud.oracle.com (pede cartão só para verificação).
2. **Compute → Instances → Create instance**
   - Image: **Ubuntu 22.04 ou 24.04**
   - Shape: **Ampere A1 (ARM)**, 1–2 OCPU e 6–12 GB (dentro do gratuito). Se aparecer "out of capacity", tente outro horário ou o shape **VM.Standard.E2.1.Micro** (x86_64).
   - Baixe a chave SSH.
3. **Abrir a porta no painel:** Networking → Virtual Cloud Networks → sua VCN → Security Lists → Default → **Add Ingress Rule**: Source `0.0.0.0/0`, protocolo **UDP**, porta de destino **7777**.

### Azure for Students (sem cartão)
1. Ative em azure.microsoft.com/free/students com o e-mail da faculdade.
2. Crie uma VM **Ubuntu**, tamanho **B1s** ou **B1ms**.
3. Em **Networking → Add inbound port rule**: UDP, porta **7777**.

## 3. Instalar na VM

**Pelo Windows (mais fácil):** monte o pacote com `tools/empacotar.ps1` (gera `export/EchoesOfEternia-servidor.zip`), leve-o ao PC que tem a chave e siga `PASSO_A_PASSO_ORACLE.md`. O `enviar_para_vm.ps1` detecta ARM64/x86_64, envia e instala com um comando.

**Na mão** (troque o IP e a chave):

```bash
scp -i chave.key export/server/echoes_server.arm64 deploy/install_server.sh deploy/update_server.sh deploy/stop_server.sh deploy/echoes-server.service ubuntu@IP_DA_VM:~
ssh -i chave.key ubuntu@IP_DA_VM
```

Na VM:

```bash
sudo bash install_server.sh ./echoes_server.arm64
```

O script cria o usuário `echoes`, instala em `/opt/echoes`, abre a porta UDP 7777 no firewall da VM e cria o serviço `echoes-server`, que **inicia com a VM e reinicia sozinho se cair**.

As **contas**, os **personagens** e a **chave do DTLS** ficam em `/var/lib/echoes` (só o usuário `echoes` lê).

**Salvamento:** o servidor salva cada personagem quando o jogador sai, todos a cada 60 s, e todos ao parar com `systemctl stop`/`restart` (a parada segura avisa os jogadores "Seu personagem foi salvo"). Se a VM cair sem aviso, perde-se no máximo o último minuto. Na primeira vez que liga, o servidor gera a chave e o certificado em `/var/lib/echoes/tls/`.

Porta e vagas: `sudo PORT=7777 MAX_PLAYERS=16 bash install_server.sh ./echoes_server.arm64`
(ou edite `/etc/default/echoes-server` e rode `sudo systemctl restart echoes-server`).

## 4. Entrar no jogo

No menu do cliente: **Entrar no mundo** → IP = IP público da VM, porta 7777.

## Comandos úteis (na VM)

| Para | Comando |
|---|---|
| Ver os logs ao vivo | `sudo journalctl -u echoes-server -f` |
| Ver se está rodando | `systemctl status echoes-server` |
| Reiniciar | `sudo systemctl restart echoes-server` |
| Parar (salva todos antes) | `sudo systemctl stop echoes-server` |
| Atualizar para uma versão nova (faz backup antes) | `sudo bash update_server.sh ./echoes_server.arm64` |
| Backup manual das contas | `sudo tar czf ~/echoes-dados.tgz -C /var/lib echoes` |
| Quantas contas existem | `sudo ls /var/lib/echoes/accounts \| wc -l` |

## Quedas e reconexão

Se a internet do jogador oscilar ou o servidor reiniciar sozinho (o systemd religa em ~6 s), o jogo mostra "Conexão perdida. Reconectando..." e volta sozinho, sem pedir a senha, em até ~40 s. Se o servidor for parado para manutenção (`systemctl stop`/`restart`), os jogadores voltam ao menu com o aviso "Seu personagem foi salvo".

## Teste do Gate 1 (roteiro)

1. Exporte o servidor (preset da arquitetura da VM) e o cliente Windows **da mesma versão**.
2. Instale na VM (seção 3) e confira `systemctl status echoes-server` e o log (`journalctl -u echoes-server -f`).
3. Em 2 PCs (redes diferentes, se possível): **Criar conta** com o IP público da VM, porta 7777.
4. Os dois jogadores se veem e andam; o log da VM mostra as entradas.
5. `sudo systemctl restart echoes-server`: os dois voltam ao menu com "Seu personagem foi salvo"; ao entrar de novo, aparecem onde estavam.
6. Desligue o Wi-Fi de um PC por ~5 s e religue: o jogo mostra "Reconectando..." e volta.
7. `sudo systemctl kill -s KILL echoes-server` (queda brusca): o systemd religa o servidor e os clientes reconectam sozinhos.

## Certificado fixo no cliente (recomendado para a entrega)

A conexão já é cifrada, mas sem este passo o cliente aceita qualquer servidor que fale DTLS. Para o cliente só aceitar **o seu** servidor:

1. Na VM: `sudo cat /var/lib/echoes/tls/server.crt`
2. Copie o texto (de `-----BEGIN CERTIFICATE-----` até `-----END CERTIFICATE-----`) para `certs/server.crt` no projeto.
3. Exporte o cliente de novo. O aviso "sem certificado fixo" deixa de aparecer no log do cliente.

Só o certificado (público) vai para o projeto. A chave `server.key` **nunca** sai da VM (o `.gitignore` bloqueia `*.key`). Se a pasta `/var/lib/echoes` for apagada, a VM gera outra chave e os clientes com o certificado antigo deixam de conectar: repita os passos.

## Testar no próprio PC (sem VM)

O mesmo jogo vira servidor com `--server`:

- Pelo editor: **Debug → Customize Run Instances**, instância 1 com `--server`, as outras com `--join=127.0.0.1 --user=Ana --pass=segredo1 --create` (sem `--create` depois que a conta existir).
- Pelo executável: `EchoesOfEternia.exe --headless --server` num terminal e o jogo normal em outra janela.

Isso também é o **plano B da apresentação**: se a VM ou a internet falharem, um notebook roda o servidor e os outros entram pela rede local.
