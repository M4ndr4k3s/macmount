# MacMount

Montador gráfico de compartilhamentos de rede para macOS — **SMB (Windows)**, AFP, NFS e WebDAV,
numa lista que você monta com um clique. Universal (Intel + Apple Silicon), **roda do macOS 10.13
High Sierra em diante**, sem coleta de dados.

Feito pela **Mdk Software**.

---

## O que faz

- Lista de compartilhamentos salvos, com estado ao vivo (montado / desmontado)
- Montar e desmontar num clique, pela janela ou pelo ícone na barra de menus
- Cola o caminho do Windows direto: `\\SERVIDOR\Publico` vira `smb://SERVIDOR/Publico` sozinho
- Senha guardada no **Keychain**, no mesmo formato que o Finder usa — a credencial é a mesma
  do "Conectar ao servidor" do sistema, não uma cópia
- **Montar todos** e **desmontar todos** de uma vez
- Montar ao iniciar a sessão sem abrir janela nenhuma, com aviso por notificação ao terminar
- **Reconectar sozinho** quando a rede volta ou o Mac acorda — em silêncio, sem diálogo
  surpresa: sem credencial pronta, prefere ficar desmontado
- **Viver só na barra de menus**, sem ícone no Dock, se você quiser
- Reordenar a lista arrastando
- Descoberta de servidores na rede local via Bonjour, para não ter que digitar o nome
  (não encontra PCs Windows — veja a seção sobre Windows abaixo)
- Opções por compartilhamento: somente leitura, não mostrar na mesa, conectar como convidado
- Interface em português e inglês

Por baixo é o **NetFS.framework**, a mesma API pública que o Finder usa. Não é um invólucro
em volta do `mount_smbfs`.

## Instalar

Baixe o `.dmg` da [página de releases](https://github.com/M4ndr4k3s/macmount/releases) e
arraste para a pasta Aplicativos.

O app **não é notarizado** (isso exigiria uma conta paga de desenvolvedor Apple), então na
primeira abertura o sistema reclama:

- **macOS 10.13 a 12** — clique com o botão direito no app e escolha *Abrir*
- **macOS 13 ou superior** — tente abrir, depois vá em *Ajustes do Sistema › Privacidade e
  Segurança* e clique em *Abrir assim mesmo*

Depois disso ele abre normalmente.

## Montando um compartilhamento do Windows 10/11

O caso mais comum, e o mais tranquilo: Windows 10 e 11 falam SMB2/SMB3, que o macOS 10.13
suporta nativamente. Nada do atrito de NAS antigo preso em SMBv1.

No Windows, compartilhe a pasta (botão direito › *Propriedades* › *Compartilhamento*). No
MacMount, clique em **+** e preencha o servidor com o nome do PC ou o IP — ou simplesmente
cole o caminho de rede inteiro, `\\MEU-PC\Publico`, que o app separa nos campos certos.

Detalhes que costumam travar a primeira conexão:

- **A descoberta Bonjour não encontra PCs Windows.** O Windows não anuncia compartilhamento
  por Bonjour — isso é coisa de macOS, Samba e NAS. Digite o nome ou o IP. Se o nome do PC
  não resolver, use o IP (`ipconfig` no Windows mostra).
- **Conta Microsoft**: o usuário costuma ser o e-mail completo da conta. Em algumas máquinas
  é preciso escrever `MicrosoftAccount\seu@email.com`.
- **Conta local**: se o usuário sozinho não funcionar, tente `NOME-DO-PC\usuario`.
- **Conta sem senha não conecta.** O Windows recusa acesso remoto de conta sem senha, e não
  é algo que o app possa contornar.
- Na rede do Windows, o perfil precisa estar como **Rede privada**; em *Rede pública* o
  compartilhamento fica bloqueado pelo firewall.

## O que acontece no início da sessão

Com *Montar ao iniciar a sessão* marcada, o MacMount monta o que está marcado **sem abrir
janela nenhuma** e fica na barra de menus. Uma notificação avisa o resultado.

Até a v0.3.1 ele encerrava depois de montar. Não encerra mais, e a diferença importa: quem
encerra perde o *Reconectar quando a rede voltar*, e é justamente no início da sessão — com
o Wi-Fi recém associado e os nomes ainda sem resolver — que a primeira tentativa mais falha
e uma segunda mais adianta.

Isso vale tanto quando o app é aberto pelo nosso LaunchAgent
(`~/Library/LaunchAgents/com.mdksoftware.macmount.login.plist`) quanto pelos **Itens de
Início** do sistema, se você tiver adicionado o app lá à mão. Nos dois casos ele reconhece
que está nascendo junto com a sessão e não mostra a janela.

Se você tem as duas coisas — o LaunchAgent e o Item de Início —, pode deixar: a partir da
v0.4.0 a segunda cópia percebe que já existe uma rodando e encerra na hora. Antes disso as
duas subiam juntas e disputavam a montagem do mesmo compartilhamento, o que travava a
montagem e ainda fazia a janela aparecer. Mesmo assim, o mais limpo é deixar só a caixa
dentro do app e remover o Item de Início em *Ajustes do Sistema › Geral › Itens de Início*
(no High Sierra: *Preferências do Sistema › Usuários e Grupos › Itens de Início*).

Se não houver senha guardada no Keychain, o diálogo de autenticação **do sistema** pode
aparecer — esse não é uma janela do MacMount, é o macOS pedindo a credencial, e é o que
permite a montagem acontecer. Guardar a senha no Keychain elimina o pedido.

## Um compartilhamento fica em "Montando…" e não sai dali

Acontece com mais frequência logo depois de reiniciar o Mac, e costuma pegar só alguns dos
compartilhamentos. A causa está na própria chamada que monta: `NetFSMountURLSync` é
síncrona e não aceita prazo nenhum. Contra um servidor que ainda não acordou, um nome que
ainda não resolve — Wi-Fi recém associado, DNS e NetBIOS ainda mudos — ou um pedido de
senha que nasceu atrás das outras janelas, ela fica minutos sem devolver resposta.

A partir da **v0.3.1** o app não fica preso nisso. Passados 90 segundos sem resposta, a
entrada volta a mostrar o estado real e fica clicável de novo, e o Console registra qual
foi. Antes disso ela travava até o app ser encerrado — e o botão ficava desativado, então
nem clicar de novo adiantava.

O que fazer quando aparecer:

- **Espere e clique em Montar de novo.** Na segunda tentativa a rede já costuma estar de pé.
- Se repetir sempre com o mesmo servidor, cadastre-o **pelo IP** em vez do nome: resolver
  nome de PC Windows é o que mais demora a ficar pronto depois de um boot.
- Marque **Reconectar quando a rede voltar** nas entradas que vivem montadas, para o app
  tentar sozinho quando a rede estabilizar em vez de depender do primeiro instante do login.

### Se acontecer de novo, o Console conta o que foi

A partir da v0.4.0 toda tentativa de montagem é registrada, tenha dado certo ou não. Abra o
**Console.app** e filtre por `MacMount`; as linhas úteis começam com `[MacMount]`:

```
[MacMount] montando smb://SERVIDOR/Publico (usuário: leandro, senha: em mãos, diálogo: proibido)
[MacMount] smb://SERVIDOR/Publico respondeu 0 em 1.2s
```

O que cada coisa diz:

- **`senha: nenhuma`** quando você marcou *Guardar a senha no Keychain* — o Keychain recusou
  a leitura, e a montagem vai cair no diálogo do sistema. Veja a seção seguinte.
- **`respondeu <código>`** com código diferente de 0 — é erro de verdade, com a explicação
  do lado.
- **Nenhuma linha `respondeu`** depois da linha `montando` — a chamada do sistema travou. O
  app libera a entrada em 90s e registra `não respondeu em 90s`.

## Senha guardada, e o app pede de novo

Sintoma: você marca *Guardar a senha no Keychain*, funciona, e depois de **atualizar o
MacMount** ele volta a pedir a senha — ou "montar ao iniciar" e "reconectar" param de agir,
que é o mesmo problema visto de outro ângulo, já que ambos desistem sem credencial pronta.

A causa é a falta de notarização. O app é assinado apenas de forma *ad-hoc*, e essa
assinatura muda a cada build. O macOS amarra a permissão de ler um item do Keychain à
identidade de quem gravou, então para o sistema a versão nova é **outro aplicativo**.

O que fazer quando aparecer o diálogo *"MacMount quer usar informações confidenciais
armazenadas em … no seu chaveiro"*: clique em **Sempre Permitir**, não em *Permitir*. Com
*Permitir* a autorização vale só para aquela vez e o pedido volta na montagem seguinte.

Se você clicou em *Negar* por engano, abra o **Acesso às Chaves**, procure pelo nome do
servidor, apague o item e salve a senha de novo pelo MacMount.

Isso só se resolve de vez com notarização (conta paga de desenvolvedor Apple), que está no
`docs/ROADMAP.md` como fase 3.

## Privacidade

O MacMount não coleta nada. Sem contas, login, analytics, anúncios ou telemetria.

As únicas conexões de rede são:

1. **Os servidores que você mesmo cadastrou**, quando você manda montar
2. **Bonjour multicast na rede local**, para sugerir servidores no campo "servidor" — não sai
   da sua rede

Nem sequer há verificação de atualizações. A política completa está em
[m4ndr4k3s.github.io/macmount](https://m4ndr4k3s.github.io/macmount/).

## Compilar

Precisa de um Mac com Xcode 16.4 (ou das Command Line Tools equivalentes). Não há projeto
Xcode — o build é um script.

```bash
make          # MacMount.app universal em build/
make check    # build + verificações estáticas
make test     # testes de lógica
make dist     # dmg + zip
```

O binário sai com duas fatias: `x86_64` com piso **10.13** e `arm64` com piso **11.0** (o
Apple Silicon não existe antes do Big Sur). É exatamente o que o Xcode faz para um app
universal com deployment target 10.13.

### Como o suporte ao 10.13 é garantido

O projeto é compilado e publicado pelos runners macOS do GitHub Actions, que são Macs na
nuvem rodando macOS 15 — nenhum desenvolvedor tem um High Sierra à mão durante o
desenvolvimento. A **v0.1.0 foi confirmada funcionando num MacBook Air de 2011 com macOS
10.13**, mas essa confirmação vem depois do release, não antes. O que segura cada build
antes de publicar é isto:

| Garantia | O que pega |
|---|---|
| `-Werror=unguarded-availability` | Usar qualquer API posterior ao 10.13 vira erro de compilação |
| `scripts/check-bundle.sh` | Confere `minos 10.13` na fatia Intel, as duas arquiteturas, ausência de runtime do Swift, só dependências do sistema e assinatura válida |
| `scripts/check-strings.py` | Toda chave de tradução usada em `src/` existe nos dois idiomas, sem duplicata e com os mesmos especificadores de formato |
| `make test` | URLs, parsing de UNC, casamento de volume montado, mapa de erros, ida e volta em JSON |
| `make smoke` | Constrói janela e menu fora da tela — pega constraint quebrada e crash de inicialização |
| Job "montagem real" no CI | Levanta um Samba no runner e monta de verdade: `NetFSMountURLSync`, detecção por `getfsstat` e desmontagem. Obrigatório — quebra ali barra o merge |

**O que isso não cobre, e vale saber:** nenhuma dessas garantias abre o app numa máquina
antiga, e nenhuma exercita servidor de verdade com domínio, NAS preso em SMBv1 ou senha
expirada. O Samba do CI é um servidor sintético e cooperativo. Se você tem a máquina alvo,
o teste que importa continua sendo o seu — relate o que quebrar.

O app é **Objective-C** por um motivo específico: a ABI do Swift só estabilizou no macOS
10.14.4, então um app Swift com piso 10.13 teria que embutir o runtime. E SwiftUI só existe
do 10.15 em diante, daí AppKit com a interface construída em código.

### Ícone

São dois, e por um bom motivo.

**Dock:** `resources/icon.png`, 1024×1024 RGBA — um disco externo com o glifo de rede
gravado na tampa. É arte fornecida, não gerada; o build só converte para `.icns` com `sips`
e `iconutil`. Para trocar, substitua o PNG mantendo 1024×1024 com transparência.

**Barra de menus:** desenhado em código, em `MMStatusMenu`. Não é o ícone do Dock reduzido,
e não pode ser: a barra exige uma *imagem template* — monocromática, definida só pelo alfa —
porque é o sistema que escolhe a cor conforme a barra esteja clara ou escura. Um ícone
colorido encolhido a 18 pontos vira uma mancha e desaparece no modo escuro.

## Onde ficam os dados

| O quê | Onde |
|---|---|
| Lista de compartilhamentos | `~/Library/Application Support/MacMount/shares.json` (permissão 0600) |
| Senhas | Keychain do usuário, como *internet password* |
| Montar ao iniciar | `~/Library/LaunchAgents/com.mdksoftware.macmount.login.plist` |

Nenhuma senha é gravada no `shares.json` — os testes verificam isso.

## Licença

MIT. Veja [LICENSE](LICENSE).
