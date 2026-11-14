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

No PC (troque o IP e a chave):

```bash
scp -i chave.key export/server/echoes_server.arm64 deploy/install_server.sh deploy/update_server.sh deploy/echoes-server.service ubuntu@IP_DA_VM:~
ssh -i chave.key ubuntu@IP_DA_VM
```

Na VM:

```bash
sudo bash install_server.sh ./echoes_server.arm64
```

O script cria o usuário `echoes`, instala em `/opt/echoes`, abre a porta UDP 7777 no firewall da VM e cria o serviço `echoes-server`, que **inicia com a VM e reinicia sozinho se cair**.

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
| Parar | `sudo systemctl stop echoes-server` |
| Atualizar para uma versão nova | `sudo bash update_server.sh ./echoes_server.arm64` |

## Testar no próprio PC (sem VM)

O mesmo jogo vira servidor com `--server`:

- Pelo editor: **Debug → Customize Run Instances**, instância 1 com `--server`, as outras com `--join=127.0.0.1 --name=Ana`.
- Pelo executável: `EchoesOfEternia.exe --headless --server` num terminal e o jogo normal em outra janela.

Isso também é o **plano B da apresentação**: se a VM ou a internet falharem, um notebook roda o servidor e os outros entram pela rede local.
