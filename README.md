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
- Montar ao iniciar a sessão
- Descoberta de servidores na rede local via Bonjour, para não ter que digitar o nome
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
nuvem rodando macOS 15. **Ninguém abre o app num High Sierra de verdade antes do release** —
no lugar disso:

| Garantia | O que pega |
|---|---|
| `-Werror=unguarded-availability` | Usar qualquer API posterior ao 10.13 vira erro de compilação |
| `scripts/check-bundle.sh` | Confere `minos 10.13` na fatia Intel, as duas arquiteturas, ausência de runtime do Swift, só dependências do sistema e assinatura válida |
| `scripts/check-strings.py` | Toda chave de tradução usada em `src/` existe nos dois idiomas, sem duplicata e com os mesmos especificadores de formato |
| `make test` | URLs, parsing de UNC, casamento de volume montado, mapa de erros, ida e volta em JSON |
| `make smoke` | Constrói janela e menu fora da tela — pega constraint quebrada e crash de inicialização |
| Job "montagem real" no CI | Levanta um Samba no runner e monta de verdade (informativo, pode falhar) |

**O que isso não cobre, e vale saber:** ninguém clicou no app num High Sierra real, e o
comportamento contra um servidor Windows de verdade (domínio, NAS antigo em SMBv1, senha
expirada) não é exercitado. Se você tem a máquina alvo, o teste que importa é seu — abra o
`.zip` lá e relate o que quebrar.

O app é **Objective-C** por um motivo específico: a ABI do Swift só estabilizou no macOS
10.14.4, então um app Swift com piso 10.13 teria que embutir o runtime. E SwiftUI só existe
do 10.15 em diante, daí AppKit com a interface construída em código.

### Ícone

`resources/icon.png` é gerado por `scripts/gen-icon.py`, um rasterizador em Python puro — dá
para editar o ícone em qualquer sistema, não só no Mac. `make icon` regera o PNG; o build
converte para `.icns` com `sips` e `iconutil`.

## Onde ficam os dados

| O quê | Onde |
|---|---|
| Lista de compartilhamentos | `~/Library/Application Support/MacMount/shares.json` (permissão 0600) |
| Senhas | Keychain do usuário, como *internet password* |
| Montar ao iniciar | `~/Library/LaunchAgents/com.mdksoftware.macmount.login.plist` |

Nenhuma senha é gravada no `shares.json` — os testes verificam isso.

## Licença

MIT. Veja [LICENSE](LICENSE).
