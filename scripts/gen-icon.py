#!/usr/bin/env python3
"""Gera resources/icon.png (1024x1024) — o ícone do MacMount.

Rasterizador próprio em Python puro (só zlib/struct da stdlib) para que o ícone
seja reproduzível e editável em qualquer sistema, não só no Mac. O build converte
esse PNG em .icns com sips + iconutil (scripts/make-icns.sh).

Uso: python3 scripts/gen-icon.py [saida.png]

Desenho: quadrado arredondado com gradiente teal da identidade Mdk Software e um
glifo de rede em branco — um nó no topo ligado a dois nós na base.
"""

import math
import struct
import sys
import zlib

SIZE = 1024
SS = 3  # supersampling por eixo (3x3 = 9 amostras por pixel)

TEAL = (0x00, 0xC4, 0xA0)
TEAL_DARK = (0x00, 0x7A, 0x68)
WHITE = (0xFF, 0xFF, 0xFF)


def rounded_rect_sdf(x, y, cx, cy, half_w, half_h, radius):
    """Distância com sinal até um retângulo arredondado (negativo = dentro)."""
    dx = abs(x - cx) - (half_w - radius)
    dy = abs(y - cy) - (half_h - radius)
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    inside = min(max(dx, dy), 0.0)
    return outside + inside - radius


def circle_sdf(x, y, cx, cy, radius):
    return math.hypot(x - cx, y - cy) - radius


def segment_sdf(x, y, ax, ay, bx, by, radius):
    """Distância até uma cápsula (segmento de reta com espessura)."""
    vx, vy = bx - ax, by - ay
    wx, wy = x - ax, y - ay
    denom = vx * vx + vy * vy
    t = 0.0 if denom == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / denom))
    return math.hypot(wx - t * vx, wy - t * vy) - radius


def coverage(sdf_value):
    """Converte distância em cobertura 0..1 — anti-aliasing de 1 unidade."""
    return max(0.0, min(1.0, 0.5 - sdf_value))


def blend(dst, src, alpha):
    return tuple(round(d + (s - d) * alpha) for d, s in zip(dst, src))


def build_pixels():
    s = float(SIZE)
    # Geometria do glifo, em fração do lado, para escalar junto com SIZE.
    node_r = 0.085 * s
    link_r = 0.028 * s
    top = (0.5 * s, 0.315 * s)
    left = (0.285 * s, 0.685 * s)
    right = (0.715 * s, 0.685 * s)

    plate_half = 0.5 * s
    plate_radius = 0.2237 * s  # proporção do "squircle" das apps macOS modernas

    rows = []
    inv_samples = 1.0 / (SS * SS)
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            r_acc = g_acc = b_acc = a_acc = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    x = px + (sx + 0.5) / SS
                    y = py + (sy + 0.5) / SS

                    plate = coverage(
                        rounded_rect_sdf(x, y, 0.5 * s, 0.5 * s,
                                         plate_half, plate_half, plate_radius)
                    )
                    if plate <= 0.0:
                        continue

                    # Gradiente diagonal teal -> teal escuro.
                    t = max(0.0, min(1.0, (x + y) / (2.0 * s)))
                    color = tuple(
                        c0 + (c1 - c0) * t for c0, c1 in zip(TEAL, TEAL_DARK)
                    )

                    # Glifo de rede por cima.
                    glyph = max(
                        coverage(segment_sdf(x, y, top[0], top[1], left[0], left[1], link_r)),
                        coverage(segment_sdf(x, y, top[0], top[1], right[0], right[1], link_r)),
                        coverage(segment_sdf(x, y, left[0], left[1], right[0], right[1], link_r)),
                        coverage(circle_sdf(x, y, top[0], top[1], node_r)),
                        coverage(circle_sdf(x, y, left[0], left[1], node_r)),
                        coverage(circle_sdf(x, y, right[0], right[1], node_r)),
                    )
                    if glyph > 0.0:
                        color = blend(color, WHITE, glyph)

                    r_acc += color[0] * plate
                    g_acc += color[1] * plate
                    b_acc += color[2] * plate
                    a_acc += plate

            alpha = a_acc * inv_samples
            if alpha <= 0.0:
                row += b"\x00\x00\x00\x00"
            else:
                # Cor não pré-multiplicada: divide pela cobertura acumulada.
                row += bytes((
                    max(0, min(255, round(r_acc / a_acc))),
                    max(0, min(255, round(g_acc / a_acc))),
                    max(0, min(255, round(b_acc / a_acc))),
                    max(0, min(255, round(alpha * 255))),
                ))
        rows.append(bytes(row))
    return rows


def write_png(path, rows):
    raw = b"".join(b"\x00" + r for r in rows)  # filtro 0 (None) por linha

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "resources/icon.png"
    write_png(out, build_pixels())
    print("icone gerado: %s (%dx%d)" % (out, SIZE, SIZE))


if __name__ == "__main__":
    main()
