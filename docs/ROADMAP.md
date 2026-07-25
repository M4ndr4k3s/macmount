# MacMount — Plano de Desenvolvimento

> Montador gráfico de compartilhamentos de rede para macOS, da **Mdk Software**.
> Piso **macOS 10.13 High Sierra**, universal (Intel + Apple Silicon), offline.

## Fase 1 — MVP (em andamento)

1. Modelo `MMShare`: URL de montagem, parser de UNC/URL, validação, JSON
2. `MMMounter`: montar e desmontar via NetFS, detecção de estado por `getfsstat`
3. `MMKeychain`: senha como *internet password*, no mesmo formato do Finder
4. `MMStore`: `shares.json` em Application Support, permissão 0600
5. Janela com a lista + folha de adicionar/editar
6. Ícone e menu na barra de menus
7. Montar ao iniciar a sessão (LaunchAgent)
8. Descoberta Bonjour de servidores SMB/AFP
9. i18n pt-BR/en-US
10. Build universal, verificações estáticas e release por tag no GitHub Actions

## Fase 2 — Feita na v0.2.0

Depois do primeiro uso real: v0.1.0 montou um compartilhamento do Windows 10/11 a partir
de um MacBook Air 2011 com High Sierra. O que o uso pediu em seguida:

1. **Ocultar o ícone do Dock**, vivendo só na barra de menus (`MMPrefs.showDockIcon`)
2. **Desmontar todos**, na janela e no menu da barra
3. **Reordenar a lista** arrastando
4. **Reconectar sozinho** quando a rede volta ou o Mac acorda, sempre em silêncio
5. **Notificação** ao concluir a montagem do login

## Fase 3 — Candidatos

- **Perfis por rede**: montar só quando estiver em determinado Wi-Fi ou faixa de IP
- **Encontrar PCs Windows na rede.** O Bonjour só acha macOS, Samba e NAS; o Windows não
  anuncia por lá. Cobrir isso exigiria WS-Discovery (o que o Explorer passou a usar depois
  que o SMBv1 morreu) ou consulta de nomes NetBIOS — nenhum dos dois tem API pronta no
  macOS, seria implementar o protocolo na mão. Só vale se digitar o IP incomodar de verdade.
- **Importar** os servidores que já estão nos favoritos do Finder
- **Submontagem melhor**: hoje `Publico/Docs` só casa por igualdade exata do caminho; casar
  com o share pai já montado e abrir a subpasta seria mais amigável
- **Notificação na API nova.** O aviso do login usa `NSUserNotification`, obsoleto desde o
  macOS 11 e possivelmente inerte em versões recentes. O substituto,
  `UNUserNotificationCenter`, é 10.14+ — usar exigiria caminho duplo. Enquanto o alvo for o
  High Sierra, fica como está.

## Fase 3 — Distribuição

- **Notarização** (exige conta paga de desenvolvedor Apple, US$ 99/ano). Resolveria o
  atrito de "clique direito › Abrir" na primeira execução.
- **Verificação de atualizações** — só se for opcional, acionada pelo usuário e sem enviar
  identificador nenhum. Exige atualizar a política de privacidade antes.
- Homebrew cask

## Limites conhecidos

- **Nenhum Mac de desenvolvimento.** Build e verificação acontecem só no CI. Existe um
  MacBook Air 2011 com High Sierra para teste manual — a v0.1.0 foi confirmada nele —, mas
  a confirmação vem depois do release, nunca antes.
- **Sem notarização**, primeira abertura exige o caminho manual (documentado no README).
- **NFS não usa Keychain** — o protocolo não autentica por senha.
- **Xcode 16.4 fixado.** Quando o runner deixar de oferecer essa versão, será preciso
  reverificar se o Xcode novo ainda aceita deployment target 10.13 antes de subir o pino.
  `scripts/check-bundle.sh` detecta a perda, mas a decisão é humana.

## Convenções de trabalho

Iguais ao PassForge: issue com label (`feature`, `bug`, `qa`, `release`) → branch
`claude/<slug>` → PR pequeno → merge na `main`. Roadmap revisado a cada release.
