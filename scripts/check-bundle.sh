#!/bin/bash
#
# Verificações estáticas do bundle. Como não há um High Sierra para abrir o app,
# estas assertivas são o que garante que o binário realmente aceita 10.13 —
# junto com o -Werror=unguarded-availability da compilação.
#
# Uso: scripts/check-bundle.sh [diretório-de-build]

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${1:-$ROOT/build}"

APP="$BUILD/MacMount.app"
BIN="$APP/Contents/MacOS/MacMount"
PLIST="$APP/Contents/Info.plist"

EXPECTED_MIN_X86="10.13"
EXPECTED_MIN_ARM="11.0"

fails=0

ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; }
fail() { printf '  \033[31mFALHA\033[0m %s\n' "$1"; fails=$((fails + 1)); }

echo "==> conferindo $APP"

if [ ! -x "$BIN" ]; then
  fail "executável não encontrado em $BIN"
  echo "$fails falha(s)."
  exit 1
fi

# 1. As duas arquiteturas estão presentes.
archs="$(lipo -archs "$BIN" 2>/dev/null)"
for arch in x86_64 arm64; do
  case " $archs " in
    *" $arch "*) ok "fatia $arch presente" ;;
    *)           fail "fatia $arch ausente (lipo: $archs)" ;;
  esac
done

# 2. Piso de cada fatia. Clang emite LC_VERSION_MIN_MACOSX abaixo do 10.14 e
#    LC_BUILD_VERSION daí para cima; o awk aceita os dois formatos.
slice_min() {
  vtool -arch "$1" -show-build-version "$BIN" 2>/dev/null \
    | awk '/^[[:space:]]*(minos|version)[[:space:]]/ { print $2; exit }'
}

check_min() {
  local arch="$1" expected="$2" actual
  actual="$(slice_min "$arch")"
  if [ "$actual" = "$expected" ]; then
    ok "fatia $arch exige macOS $actual"
  else
    fail "fatia $arch exige macOS '${actual:-desconhecido}', esperado $expected"
  fi
}

check_min x86_64 "$EXPECTED_MIN_X86"
check_min arm64  "$EXPECTED_MIN_ARM"

# 3. Nenhuma dylib do Swift: o runtime do Swift só vem de fábrica a partir do
#    10.14.4, e o app é Objective-C justamente para não precisar embutir nada.
if otool -L "$BIN" | grep -q 'libswift'; then
  fail "o binário linka runtime do Swift:"
  otool -L "$BIN" | grep 'libswift' | sed 's/^/        /'
else
  ok "sem runtime do Swift linkado"
fi

# 4. Só frameworks do sistema — nenhuma dependência que precise ser embarcada.
if otool -L "$BIN" | tail -n +2 | grep -qvE '^[[:space:]]+(/usr/lib/|/System/Library/)'; then
  fail "dependência fora do sistema:"
  otool -L "$BIN" | tail -n +2 | grep -vE '^[[:space:]]+(/usr/lib/|/System/Library/)' | sed 's/^/        /'
else
  ok "só depende de bibliotecas do sistema"
fi

# 5. O Info.plist declara o mesmo piso que o binário.
plist_min="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST" 2>/dev/null)"
if [ "$plist_min" = "$EXPECTED_MIN_X86" ]; then
  ok "Info.plist declara LSMinimumSystemVersion $plist_min"
else
  fail "Info.plist declara '$plist_min', esperado $EXPECTED_MIN_X86"
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null)"
case "$version" in
  *__VERSION__*|"") fail "a versão não foi substituída no Info.plist" ;;
  *)                ok "versão preenchida: $version" ;;
esac

# 6. Recursos que a interface espera encontrar em tempo de execução.
for resource in Resources/AppIcon.icns Resources/pt.lproj/Localizable.strings \
                Resources/en.lproj/Localizable.strings; do
  if [ -e "$APP/Contents/$resource" ]; then
    ok "$resource presente"
  else
    fail "$resource ausente"
  fi
done

# 7. Assinatura ad-hoc — sem ela a fatia arm64 não abre no Apple Silicon.
if codesign --verify --deep --strict "$APP" 2>/dev/null; then
  ok "assinatura válida"
else
  fail "assinatura inválida ou ausente"
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "todas as verificações passaram."
  exit 0
fi
echo "$fails verificação(ões) falharam."
exit 1
