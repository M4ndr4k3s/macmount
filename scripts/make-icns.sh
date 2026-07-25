#!/bin/bash
#
# Converte o PNG de 1024x1024 em .icns usando só ferramentas do sistema.
# O PNG é gerado por scripts/gen-icon.py, que roda em qualquer sistema — só
# esta última etapa depende do macOS.
#
# Uso: scripts/make-icns.sh entrada.png saida.icns

set -euo pipefail

SRC="$1"
DEST="$2"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

# Nomes exigidos pelo iconutil: cada tamanho em 1x e 2x.
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SRC" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done

iconutil --convert icns --output "$DEST" "$ICONSET"
