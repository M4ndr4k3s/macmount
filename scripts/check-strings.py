#!/usr/bin/env python3
"""Confere que toda chave de NSLocalizedString usada em src/ existe em cada
Localizable.strings — e que nenhum arquivo tem chave sobrando ou duplicada.

Chave faltando não quebra a compilação: o NSLocalizedString devolve a própria
chave e ela aparece crua na interface. Como o app não pode ser aberto no CI
para conferir isso a olho, esta verificação é o que segura o problema.

Uso: python3 scripts/check-strings.py [raiz-do-projeto]
Sai com 1 se houver qualquer divergência.
"""

import os
import re
import sys

# NSLocalizedString(@"chave", @"comentário") — só o primeiro argumento importa.
CALL_RE = re.compile(r'NSLocalizedString\(\s*@"((?:[^"\\]|\\.)*)"', re.S)

# "chave" = "valor";  — aceita escapes dentro dos dois lados.
ENTRY_RE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.M)

COMMENT_RE = re.compile(r'/\*.*?\*/', re.S)

# Especificador de formato completo, com bandeiras, largura, precisão e o
# modificador de tamanho — %lu e %u não são intercambiáveis.
FORMAT_RE = re.compile(r'%[-+ #0]*[0-9*]*(?:\.[0-9*]+)?(?:hh|h|ll|l|q|z|t|j|L)?[@diouxXeEfgGcsSpaA%]')


def keys_used(src_dir):
    """Chaves referenciadas no código, mapeadas para os arquivos que as usam."""
    used = {}
    for name in sorted(os.listdir(src_dir)):
        if not name.endswith((".m", ".h")):
            continue
        path = os.path.join(src_dir, name)
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        # Comentários podem conter exemplos de chamada; fora com eles.
        text = COMMENT_RE.sub(" ", text)
        for key in CALL_RE.findall(text):
            used.setdefault(key, set()).add(name)
    return used


def keys_defined(strings_path):
    """Chaves definidas num .strings, e a lista das duplicadas."""
    with open(strings_path, encoding="utf-8") as fh:
        text = fh.read()
    text = COMMENT_RE.sub("\n", text)

    defined = {}
    duplicates = []
    for key, value in ENTRY_RE.findall(text):
        if key in defined:
            duplicates.append(key)
        defined[key] = value
    return defined, duplicates


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    src_dir = os.path.join(root, "src")
    res_dir = os.path.join(root, "resources")

    if not os.path.isdir(src_dir):
        print("erro: %s não existe" % src_dir)
        return 1

    used = keys_used(src_dir)
    if not used:
        print("erro: nenhuma chave NSLocalizedString encontrada em src/")
        return 1

    lproj_dirs = sorted(d for d in os.listdir(res_dir) if d.endswith(".lproj"))
    if not lproj_dirs:
        print("erro: nenhum .lproj em %s" % res_dir)
        return 1

    problems = 0
    all_defined = {}

    for lproj in lproj_dirs:
        path = os.path.join(res_dir, lproj, "Localizable.strings")
        if not os.path.isfile(path):
            print("erro: falta %s" % path)
            problems += 1
            continue

        defined, duplicates = keys_defined(path)
        all_defined[lproj] = defined

        for key in duplicates:
            print("erro: %s define \"%s\" mais de uma vez" % (lproj, key))
            problems += 1

        missing = sorted(set(used) - set(defined))
        for key in missing:
            where = ", ".join(sorted(used[key]))
            print("erro: %s não traduz \"%s\" (usada em %s)" % (lproj, key, where))
            problems += 1

        unused = sorted(set(defined) - set(used))
        for key in unused:
            print("aviso: %s define \"%s\", que o código não usa" % (lproj, key))
            problems += 1

        empty = sorted(k for k, v in defined.items() if not v.strip())
        for key in empty:
            print("erro: %s traduz \"%s\" como texto vazio" % (lproj, key))
            problems += 1

    # Especificadores de formato precisam bater entre os idiomas, senão o
    # -[NSString stringWithFormat:] lê lixo da pilha em um deles. O modificador
    # de tamanho faz parte da comparação: %lu e %u consomem larguras diferentes.
    reference = lproj_dirs[0]
    for lproj in lproj_dirs[1:]:
        for key in sorted(set(all_defined.get(reference, {})) & set(all_defined.get(lproj, {}))):
            a = FORMAT_RE.findall(all_defined[reference][key])
            b = FORMAT_RE.findall(all_defined[lproj][key])
            if a != b:
                print("erro: \"%s\" tem formatos diferentes entre %s (%s) e %s (%s)"
                      % (key, reference, "".join(a) or "nenhum", lproj, "".join(b) or "nenhum"))
                problems += 1

    if problems:
        print("\n%d problema(s) de localização." % problems)
        return 1

    print("localização OK: %d chaves em %s" % (len(used), ", ".join(lproj_dirs)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
