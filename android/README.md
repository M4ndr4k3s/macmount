# kdmeu (Android)

App Android para **achar celulares pela intensidade do sinal Bluetooth**. Lista os aparelhos
por perto ordenados do sinal mais forte para o mais fraco e, ao tocar num deles, entra em modo
rastreio: uma barra grande que sobe conforme você chega perto.

> Projeto separado do MacMount (que é macOS/Objective-C). Vive nesta pasta e não participa do
> `make` da raiz.

## Como funciona

Duas varreduras rodam juntas, porque nenhuma sozinha basta:

| | O que dá | O que não dá |
|---|---|---|
| **BLE** (`BluetoothLeScanner`) | RSSI a cada anúncio, contínuo — é o que faz a barra reagir enquanto você anda | Nem sempre traz nome ou classe do aparelho |
| **Clássica** (`startDiscovery`) | Nome amigável e a classe (telefone / fone / computador) | Rodada de ~12 s, pesada, e atrapalha o BLE enquanto roda |

Por isso a descoberta clássica é reiniciada em intervalo (20 s) em vez de ficar ligada direto.

O RSSI cru pula demais — reflexão, corpo, orientação da antena. Cada aparelho tem seu valor
passado por média móvel exponencial (`Signal.smooth`, α = 0.3) e a distância sai do modelo
log-distância `d = 10^((txPower − rssi) / (10n))`, com `txPower = −59 dBm` e `n = 2.7`.
**Isso é estimativa, não medição**: serve para o jogo de quente-e-frio, não para dizer
"3,2 metros".

## Limites que valem conhecer

- **Só acha o que está anunciando.** Celular com Bluetooth desligado, ou que não emite anúncio
  BLE nem está em modo detectável, é invisível — não existe truque que contorne isso.
- **Endereços aleatórios.** iPhones e Androids recentes trocam de endereço BLE de tempos em
  tempos por privacidade; o mesmo aparelho pode reaparecer como outra entrada.
- **Sem varredura em segundo plano.** O app para junto com a tela: varrer em background gasta
  bateria e, no Android 12+, exigiria serviço em primeiro plano. É um app de uso ativo.
- **Nada sai do aparelho.** Sem contas, sem rede, sem telemetria — mesmo princípio do MacMount.
  A permissão de varredura é pedida com `neverForLocation`.

## Permissões

- Android 12+ (API 31+): `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT`
- Android 11 e anteriores: `BLUETOOTH`, `BLUETOOTH_ADMIN` e `ACCESS_FINE_LOCATION` (o sistema
  antigo exige localização para qualquer varredura Bluetooth)

`minSdk 23`, `targetSdk 34`.

## Build

Não há wrapper no repositório (o `gradle-wrapper.jar` é binário). Use o Android Studio, ou um
Gradle 8.7+ instalado:

```
cd android
gradle wrapper          # uma vez, se quiser o ./gradlew
gradle :app:assembleDebug
gradle :app:testDebugUnitTest
```

## Mapa dos arquivos

```
app/src/main/java/com/mdksoftware/kdmeu/
  Signal.kt            suavização, distância estimada, faixas de proximidade  ← lógica pura, testada
  DiscoveredDevice.kt  modelo + DeviceRegistry (estado das leituras)          ← lógica pura, testada
  BtScanner.kt         varredura BLE + descoberta clássica, permissões
  DeviceAdapter.kt     lista
  MainActivity.kt      tela única: lista + painel de rastreio
app/src/test/…/SignalTest.kt   testes de JVM, sem Android nem rádio
```

`Signal` e `DeviceRegistry` são deliberadamente livres de Android: é o que o teste de unidade
consegue exercitar sem aparelho de verdade.

Textos de interface ficam em `res/values/strings.xml` (pt-BR, padrão) e `res/values-en`.
