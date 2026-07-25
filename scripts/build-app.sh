#!/bin/bash
#
# Monta MacMount.app universal (x86_64 + arm64) sem projeto Xcode.
#
# A fatia Intel é compilada com piso 10.13 (High Sierra) e a fatia Apple Silicon
# com 11.0, porque arm64 não existe antes do Big Sur — é exatamente o que o Xcode
# faz para um app universal com deployment target 10.13.
#
# Uso: scripts/build-app.sh [diretório-de-saída]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${1:-$ROOT/build}"

APP_NAME="MacMount"
BUNDLE="$BUILD/$APP_NAME.app"
VERSION="$(tr -d ' \n' < "$ROOT/VERSION")"

MIN_X86="10.13"
MIN_ARM="11.0"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"

echo "==> MacMount $VERSION (SDK $SDK_VERSION, piso x86_64 $MIN_X86 / arm64 $MIN_ARM)"

SOURCES=("$ROOT"/src/*.m)

WARNINGS=(
  -Wall -Wextra
  -Wno-unused-parameter
  # A garantia central de compatibilidade: usar qualquer API mais nova que o
  # deployment target sem @available vira erro de compilação, não bug em campo.
  -Werror=unguarded-availability
  -Werror=unguarded-availability-new
  -Werror=objc-method-access
  -Werror=incompatible-pointer-types
  -Werror=return-type
)

FRAMEWORKS=(
  -framework Cocoa
  -framework NetFS
  -framework Security
  -framework CoreGraphics
  # SCNetworkReachability, usado pelo MMReconnector — o Network framework, que
  # seria o substituto moderno, só existe do macOS 10.14 em diante.
  -framework SystemConfiguration
)

# Só o que este script produz. Apagar o diretório inteiro levaria junto o dmg e
# o zip já empacotados — e qualquer alvo que dependa de `all`, como o smoke
# test, rodaria como uma faxina silenciosa nos artefatos. Para limpar tudo
# existe o `make clean`.
rm -rf "$BUNDLE" "$BUILD/obj"
mkdir -p "$BUILD/obj"

compile_slice() {
  local arch="$1" minver="$2" out="$3"
  echo "--> compilando $arch (piso $minver)"
  clang \
    -arch "$arch" \
    -mmacosx-version-min="$minver" \
    -isysroot "$SDK" \
    -fobjc-arc \
    -O2 \
    "${WARNINGS[@]}" \
    -I"$ROOT/src" \
    "${SOURCES[@]}" \
    "${FRAMEWORKS[@]}" \
    -o "$out"
}

compile_slice x86_64 "$MIN_X86" "$BUILD/obj/$APP_NAME-x86_64"
compile_slice arm64  "$MIN_ARM" "$BUILD/obj/$APP_NAME-arm64"

echo "--> unindo as fatias"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
lipo -create \
  "$BUILD/obj/$APP_NAME-x86_64" \
  "$BUILD/obj/$APP_NAME-arm64" \
  -output "$BUNDLE/Contents/MacOS/$APP_NAME"

echo "--> montando o bundle"
sed "s/__VERSION__/$VERSION/g" "$ROOT/resources/Info.plist" > "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

for lproj in "$ROOT"/resources/*.lproj; do
  cp -R "$lproj" "$BUNDLE/Contents/Resources/"
done

"$ROOT/scripts/make-icns.sh" "$ROOT/resources/icon.png" \
  "$BUNDLE/Contents/Resources/AppIcon.icns"

# Assinatura ad-hoc não é opcional: sem ela a fatia arm64 nem abre no Apple
# Silicon. Não substitui notarização — a primeira abertura ainda exige o
# clique-direito > Abrir.
echo "--> assinando (ad-hoc)"
codesign --force --deep --sign - --timestamp=none "$BUNDLE"

echo "==> pronto: $BUNDLE"
