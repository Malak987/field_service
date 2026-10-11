#!/usr/bin/env python3
"""Cheap syntax sanity check for Dart files: delimiter balance + stray tokens.

This is NOT a parser and it is not a substitute for `dart analyze`. It exists
because the sandbox has no Dart SDK: it catches the gross breakage that hand
patching can introduce (an unclosed brace from an inserted block, a string left
open, a stray comma at top level) without pretending to type-check anything.

What it does per file:
  * strips line/block comments and string/interpolation literals,
  * requires `()`, `[]`, `{}` to balance and to close in order,
  * requires every interpolation `${...}` inside a string to balance,
  * reports the line where a mismatch becomes unrecoverable.

Usage: python3 tool/check_dart_syntax_sanity.py [paths...]
Exit code 0 = no structural problems, 1 = problems found.
"""

from __future__ import annotations

import os
import sys

PAIRS = {'(': ')', '[': ']', '{': '}'}
CLOSERS = {')', ']', '}'}


def scan(path: str) -> list[str]:
    src = open(path, encoding='utf-8').read()
    problems: list[str] = []
    stack: list[tuple[str, int]] = []
    line = 1
    index = 0
    length = len(src)
    string_quote: str | None = None

    while index < length:
        char = src[index]
        nxt = src[index + 1] if index + 1 < length else ''

        if char == '\n':
            line += 1
            index += 1
            continue

        # --- inside a string literal ---------------------------------------
        if string_quote is not None:
            if char == '\\':
                index += 2
                continue
            if char == '$' and nxt == '{':
                # Interpolation: the braces must balance inside the literal.
                depth = 0
                position = index + 1
                while position < length:
                    if src[position] == '{':
                        depth += 1
                    elif src[position] == '}':
                        depth -= 1
                        if depth == 0:
                            break
                    elif src[position] == '\n':
                        line += 1
                    position += 1
                else:
                    problems.append('line %d: unterminated interpolation' % line)
                    return problems
                index = position + 1
                continue
            if char == string_quote:
                string_quote = None
            elif string_quote == "'" and char == '\n':
                problems.append('line %d: unterminated single-quoted string' % line)
                return problems
            index += 1
            continue

        # --- comments -------------------------------------------------------
        if char == '/' and nxt == '/':
            while index < length and src[index] != '\n':
                index += 1
            continue
        if char == '/' and nxt == '*':
            index += 2
            while index < length and not (src[index] == '*' and
                                          src[index + 1:index + 2] == '/'):
                if src[index] == '\n':
                    line += 1
                index += 1
            index += 2
            continue

        # --- string starts --------------------------------------------------
        if char in ("'", '"'):
            # A raw string (r'...') behaves the same for balancing purposes.
            triple = src[index:index + 3]
            if triple in ("'''", '"""'):
                end = src.find(triple, index + 3)
                if end == -1:
                    problems.append('line %d: unterminated raw string' % line)
                    return problems
                line += src[index:end + 3].count('\n')
                index = end + 3
                continue
            string_quote = char
            index += 1
            continue

        # --- delimiters -----------------------------------------------------
        if char in PAIRS:
            stack.append((char, line))
        elif char in CLOSERS:
            if not stack:
                problems.append('line %d: unmatched "%s"' % (line, char))
                return problems
            opener, opener_line = stack.pop()
            if PAIRS[opener] != char:
                problems.append(
                    'line %d: "%s" closes "%s" opened on line %d'
                    % (line, char, opener, opener_line))
                return problems
        index += 1

    if string_quote is not None:
        problems.append('unterminated string literal')
    for opener, opener_line in stack:
        problems.append('line %d: unclosed "%s"' % (opener_line, opener))
    return problems


def dart_files(roots: list[str]) -> list[str]:
    found: list[str] = []
    for root in roots:
        if os.path.isfile(root):
            found.append(root)
            continue
        for dirpath, _dirs, files in os.walk(root):
            if any(part in ('.dart_tool', 'build', '.git') for part in dirpath.split(os.sep)):
                continue
            for name in files:
                if name.endswith('.dart'):
                    found.append(os.path.join(dirpath, name))
    return sorted(found)


def main() -> int:
    args = sys.argv[1:] or ['lib', 'test', 'tool']
    files = dart_files(args)
    bad = 0
    for path in files:
        problems = scan(path)
        if problems:
            bad += 1
            print('%s' % path)
            for problem in problems:
                print('    %s' % problem)
    if bad:
        print('DART SYNTAX SANITY: %d file(s) with structural problems '
              '(of %d checked)' % (bad, len(files)))
        return 1
    print('DART SYNTAX SANITY: OK (%d files, all delimiters balanced)' % len(files))
    return 0


if __name__ == '__main__':
    sys.exit(main())
