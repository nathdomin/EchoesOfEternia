# Servidor na Oracle: passo a passo

Faça tudo no PC de onde você vai administrar o servidor. Ele precisa ter esta pasta do pacote (`EchoesOfEternia-servidor.zip`, descompactada). Leva de 20 a 30 minutos. Precisa do **Cliente OpenSSH** do Windows. Para conferir, rode `ssh -V` no PowerShell. Se não existir, instale em Configurações → Aplicativos → Recursos opcionais → Adicionar → **Cliente OpenSSH** e abra o PowerShell de novo.

## 1. Conta (uma vez)
1. Acesse **cloud.oracle.com** e clique em **Sign up**. Escolha **Home Region: Brazil East (São Paulo)**.
   A região não pode ser trocada depois, e é a que dá o menor ping.
2. O cartão serve só para verificar a conta. A Oracle faz uma reserva de cerca de US$ 1 e devolve.
   Enquanto a conta for **Always Free** (sem "Upgrade to Pay As You Go"), nada é cobrado.

## 2. Criar a VM
1. Menu ☰ → **Compute → Instances → Create instance**.
2. **Name:** `echoes-server`.
3. **Image and shape → Edit:**
   - **Image:** Canonical **Ubuntu 24.04** (ou 22.04);
   - **Shape:** Ampere **VM.Standard.A1.Flex** com **1 OCPU e 6 GB** de memória (aparece "Always Free-eligible").
   - Se der **"Out of capacity"**, tente o shape **VM.Standard.E2.1.Micro** (AMD) ou crie de novo mais tarde. O script escolhe sozinho o servidor certo para cada tipo.
4. **Networking:** deixe criar a VCN nova e marque **Assign a public IPv4 address**.
5. **Add SSH keys → Generate a key pair for me → Save private key.**
   Guarde o arquivo `.key` (ex.: `C:\Users\voce\echoes.key`). Sem ele não dá para entrar na VM.
6. **Create.** Quando ficar **Running**, anote o **Public IP address**.

## 3. Abrir a porta do jogo no painel
1. Na página da VM → **Primary VNIC → Subnet** (link) → **Security** (ou **Security Lists**) → **Default Security List**.
2. **Add Ingress Rules:**
   - Source CIDR: `0.0.0.0/0`;
   - IP Protocol: **UDP**;
   - Destination Port Range: `7777`.
3. **Add Ingress Rules** para salvar.
4. Repita com a porta `443` (UDP). É a porta alternativa: redes de faculdade e empresa costumam bloquear a 7777, e o jogo tenta a 443 sozinho.

## 4. Instalar o servidor (um comando)
Abra o **PowerShell** nesta pasta e rode, trocando o IP e o caminho da chave:

```powershell
powershell -ExecutionPolicy Bypass -File .\enviar_para_vm.ps1 -Ip 123.45.67.89 -Chave C:\Users\voce\echoes.key
```

Na primeira vez pode aparecer "Are you sure you want to continue connecting": ele aceita sozinho.
No fim, o status deve mostrar **active (running)**.

## 5. Me mandar
- O **IP público**.
- A saída do comando: o certificado, que é público e pode ser enviado:

```powershell
ssh -i C:\Users\voce\echoes.key ubuntu@123.45.67.89 "sudo cat /var/lib/echoes/tls/server.crt"
```

Com isso eu gero o cliente da entrega, que já abre apontando para o servidor e só aceita o seu certificado.
**Nunca mande o arquivo `.key`** nem o `server.key` da VM.

## Atualizar depois (versão nova do jogo)
Quando uma versão nova for publicada, rode nesta pasta o comando abaixo. A VM baixa a versão nova sozinha, e este PC não precisa receber arquivo nenhum. O script salva os personagens e faz backup antes de trocar:

```powershell
powershell -ExecutionPolicy Bypass -File .\atualizar_servidor.ps1 -Ip 123.45.67.89 -Chave C:\Users\voce\echoes.key
```

Os jogadores não fazem nada: o jogo se atualiza sozinho ao abrir.

Para instalar a partir dos arquivos desta pasta, em vez de baixar, use o mesmo comando da instalação com `-Atualizar`:

```powershell
powershell -ExecutionPolicy Bypass -File .\enviar_para_vm.ps1 -Ip 123.45.67.89 -Chave C:\Users\voce\echoes.key -Atualizar
```

## Se algo der errado

| Sintoma | O que fazer |
|---|---|
| `The term 'ssh' is not recognized` | Instale o Cliente OpenSSH (veja o início) e abra o PowerShell de novo. |
| `does not have a '.ps1' extension` | O caminho tem espaço: ponha entre aspas (`-File "C:\...\enviar_para_vm.ps1"`). |
| `Permission denied (publickey)` | O caminho da chave está errado, ou a imagem não é Ubuntu (o usuário é `ubuntu`; no Oracle Linux é `opc`: use `-Usuario opc`). |
| O jogo diz "Não foi possível conectar" | Confira a regra UDP 7777 do passo 3 e se o serviço está rodando (abaixo). |
| Ver os logs | `ssh -i CHAVE ubuntu@IP "sudo journalctl -u echoes-server -n 50 --no-pager"` |
