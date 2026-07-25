# MacMount — instruções para o Claude

Montador gráfico de compartilhamentos de rede (SMB/Windows, AFP, NFS, WebDAV) para macOS da
Mdk Software. **Objective-C + AppKit, sem dependências, sem projeto Xcode** — o build é
`scripts/build-app.sh`. `index.html` na raiz é a política de privacidade servida via GitHub
Pages: **não mover nem renomear**, a URL é pública. Roadmap em `docs/ROADMAP.md`.

## Restrições que definem tudo (não negocie sem motivo forte)

- **Piso macOS 10.13 High Sierra.** Consequências: nada de SwiftUI (10.15+), nada de
  SF Symbols (11+), nada de `SMAppService` (13+), nada de Network framework (10.14+).
  Objective-C em vez de Swift porque a ABI do Swift só estabilizou no 10.14.4 — em Swift o
  app teria que embutir o runtime.
- **Universal.** Fatia `x86_64` com `-mmacosx-version-min=10.13`, fatia `arm64` com `11.0`
  (arm64 não existe antes do Big Sur), unidas por `lipo`.
- **Xcode fixado em 16.4 no CI.** É a versão em que o deployment target 10.13 está
  confirmado. Não troque para `macos-latest` sem reverificar.
- **Assinatura ad-hoc é obrigatória** (`codesign --sign -`), senão a fatia arm64 não abre no
  Apple Silicon. Notarização de verdade está fora de escopo (exige conta paga).
- **Nenhum Mac disponível para desenvolvimento.** Todo build e verificação acontece no CI.
  Por isso as verificações estáticas abaixo não são opcionais — são o que substitui abrir o
  app. Nunca afirme que algo "funciona" sem o CI ter passado, e não chame de "testado" o
  que só passou no CI. Existe um MacBook Air 2011 com High Sierra para teste manual (a
  v0.1.0 foi confirmada nele), mas ele entra depois do release, nunca antes.

## Mapa dos arquivos

```
src/
  main.m           três modos: normal, --mount-at-login, --smoke
  MMShare          modelo + montagem de URL + parser de UNC/URL   ← lógica pura, testada
  MMMounter        NetFSMountURLSync, desmontar, getfsstat        ← lógica pura, testada
  MMKeychain       kSecClassInternetPassword (mesmo item do Finder)
  MMStore          shares.json em Application Support, 0600      ← índice de reordenação testado
  MMPrefs          NSUserDefaults: ícone no Dock, aviso do login
  MMLoginItem      LaunchAgent em ~/Library/LaunchAgents
  MMCoordinator    estado de montagem — a janela e o menu são duas visões dele
  MMReconnector    SCNetworkReachability + despertar → remonta em silêncio
  MMBrowser        Bonjour _smb._tcp / _afpovertcp._tcp
  MMMainWindow     NSTableView com a lista, reordenável arrastando
  MMEditSheet      folha de adicionar/editar (NSGridView, 10.12+)
  MMStatusMenu     NSStatusItem, ícone desenhado em código, preferências
  MMAppDelegate    ciclo de vida, menu principal, modo login, smoke test
```

`MMShare`, `MMMounter` e a função `MMDestinationIndexForMove` do `MMStore` são
deliberadamente livres de UI: é o que `test/logic_tests.m` consegue exercitar sem Mac de
verdade e sem servidor.

## Onde cada coisa é gravada

| O quê | Onde | Chave |
|---|---|---|
| Compartilhamentos | `~/Library/Application Support/MacMount/shares.json` (0600) | — |
| Senhas | Keychain, *internet password* | — |
| Ícone no Dock | NSUserDefaults | `MMShowDockIcon` (padrão YES) |
| Aviso ao montar no login | NSUserDefaults | `MMNotifyOnLoginMount` (padrão YES) |
| Montar ao iniciar | `~/Library/LaunchAgents/com.mdksoftware.macmount.login.plist` | — |

Campos booleanos novos no `shares.json` entram com padrão que **preserva o comportamento
anterior** para quem já tem o arquivo: `savePassword` ausente vale YES porque sempre foi o
padrão; `reconnect` ausente vale NO porque é recurso novo e ligar sozinho seria mudar o
comportamento pelas costas do usuário.

## Comandos

```
make          build universal em build/
make check    build + check-bundle.sh + check-strings.py
make test     testes de lógica
make smoke    constrói a interface fora da tela
make dist     dmg + zip
make strings  só a checagem de localização (roda em qualquer sistema, inclusive Linux)
make icon     regera resources/icon.png
```

`make strings` e `python3 scripts/gen-icon.py` são os únicos que rodam fora do macOS —
use-os sempre que mexer em texto de interface ou no ícone.

## Regras de trabalho

- **Toda string visível passa por `NSLocalizedString`** e entra nos dois `.lproj`.
  `scripts/check-strings.py` falha o CI se faltar, sobrar, duplicar ou se os especificadores
  de formato divergirem entre idiomas. Rode antes de commitar.
- **Lógica nova em `MMShare`/`MMMounter` vem com teste** em `test/logic_tests.m`.
- **Nunca grave senha no `shares.json`** — só Keychain. Há teste que verifica isso.
- Chamadas do NetFS voltam na fila principal; nada de bloquear a main thread esperando
  montagem (o `mount_smoke.m` mostra o padrão certo com run loop).
- Ao usar uma API nova, confira a disponibilidade. O `-Werror=unguarded-availability` pega,
  mas descobrir na hora de escrever é mais barato que descobrir no CI.

## Princípios de produto (invioláveis)

- **Zero coleta de dados**: sem contas, login, analytics, anúncios ou telemetria.
- **Únicas conexões de rede permitidas**: os servidores que o próprio usuário cadastrou, e
  Bonjour multicast na rede local para sugerir nomes. Nada mais — nem verificação de
  atualização.
- Qualquer feature que contrarie esses pontos exige atualizar a política de privacidade
  (`index.html`) **antes** do merge.

## Convenções

- Idioma da UI e das respostas: **português** (com i18n en-US).
- Identidade visual: teal `#00C4A0` / `#007A68`, fundo escuro `#0f1115`.
- Fluxo: issue → branch `claude/<slug>` → PR pequeno → merge na `main`. Nunca commitar
  direto na `main`.
- Convenções novas (helpers, formatos de arquivo, chaves de storage) entram neste CLAUDE.md
  no mesmo PR que as introduz.
