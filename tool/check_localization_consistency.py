#!/usr/bin/env python3
"""Consistency check for the hand-written localization layer.

`lib/core/localization/app_localizations.dart` is written by hand (abstract
contract + `AppLocalizationsEn` + `AppLocalizationsDe`), and the two `.arb`
files mirror it. A missing override in either subclass — or a `context.l10n.x`
reference to a getter that does not exist — is a hard compile error in Dart,
so this script fails loudly before the analyzer ever runs.

Checks performed:
  1. every abstract member declared in `AppLocalizations` is implemented in
     BOTH `AppLocalizationsEn` and `AppLocalizationsDe`;
  2. no subclass implements a member the contract does not declare;
  3. every `l10n.<member>` / `context.l10n.<member>` used in `lib/` exists in
     the contract;
  4. every contract member has a key in BOTH `.arb` files (placeholders aside)
     and every `.arb` key has a contract member;
  5. members that take arguments declare `placeholders` metadata in the
     `.arb` files (reported as a WARNING: the `.arb` files are a hand-kept
     mirror — the app compiles `app_localizations.dart` directly, there is no
     `l10n.yaml` and no `generate: true` in `pubspec.yaml`).

Usage: python3 tool/check_localization_consistency.py
Exit code 0 = consistent, 1 = problems found.
"""

from __future__ import annotations

import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L10N = os.path.join(ROOT, 'lib', 'core', 'localization', 'app_localizations.dart')
EN_ARB = os.path.join(ROOT, 'lib', 'core', 'localization', 'arb', 'app_en.arb')
DE_ARB = os.path.join(ROOT, 'lib', 'core', 'localization', 'arb', 'app_de.arb')

GETTER = re.compile(r'^\s*String get (\w+);\s*$')
METHOD = re.compile(r'^\s*String (\w+)\(([^)]*)\);\s*$')
IMPL_GETTER = re.compile(r'^\s*String get (\w+) =>')
IMPL_METHOD = re.compile(r'^\s*String (\w+)\(([^)]*)\) =>')
BLOCK_METHOD = re.compile(r'^\s*String (\w+)\(([^)]*)\)\s*\{')
USAGE = re.compile(r'\bl10n\.(\w+)')


def slice_class(text: str, name: str) -> str:
    """Return the body of `class <name> ... { ... }` (brace balanced)."""
    start = text.index('class %s ' % name)
    brace = text.index('{', start)
    depth = 0
    for index in range(brace, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[brace + 1:index]
    raise AssertionError('unbalanced braces in %s' % name)


def members_of(body: str) -> tuple[set[str], set[str]]:
    """(getters, methods) declared/implemented in a class body."""
    getters: set[str] = set()
    methods: set[str] = set()
    for line in body.split('\n'):
        match = IMPL_GETTER.match(line) or GETTER.match(line)
        if match:
            getters.add(match.group(1))
            continue
        match = IMPL_METHOD.match(line) or METHOD.match(line) or BLOCK_METHOD.match(line)
        if match:
            methods.add(match.group(1))
    return getters, methods


def main() -> int:
    text = io.open(L10N, encoding='utf-8').read()
    abstract = slice_class(text, 'AppLocalizations')
    # The delegate class also matches 'class _AppLocalizationsDelegate' — the
    # lookup above uses the exact name with a trailing space, which only the
    # real contract has.
    a_getters, a_methods = members_of(abstract)
    en_getters, en_methods = members_of(slice_class(text, 'AppLocalizationsEn'))
    de_getters, de_methods = members_of(slice_class(text, 'AppLocalizationsDe'))

    problems: list[str] = []

    contract = a_getters | a_methods
    for label, getters, methods in (('En', en_getters, en_methods),
                                    ('De', de_getters, de_methods)):
        implemented = getters | methods
        missing = sorted(contract - implemented)
        if missing:
            problems.append('%s is missing: %s' % (label, ', '.join(missing)))
        extra = sorted(implemented - contract)
        if extra:
            problems.append('%s implements undeclared members: %s'
                            % (label, ', '.join(extra)))
        # A getter in the contract must not be implemented as a method.
        for name in sorted(a_getters & methods):
            problems.append('%s implements getter "%s" as a method' % (label, name))
        for name in sorted(a_methods & getters):
            problems.append('%s implements method "%s" as a getter' % (label, name))

    # 3) usages in lib/
    used: set[str] = set()
    for base, _dirs, files in os.walk(os.path.join(ROOT, 'lib')):
        for file_name in files:
            if not file_name.endswith('.dart'):
                continue
            path = os.path.join(base, file_name)
            used |= set(USAGE.findall(io.open(path, encoding='utf-8').read()))
    unknown = sorted(used - contract)
    if unknown:
        problems.append('lib/ references unknown l10n members: %s' % ', '.join(unknown))

    # 4) ARB parity
    en_arb = json.load(io.open(EN_ARB, encoding='utf-8'))
    de_arb = json.load(io.open(DE_ARB, encoding='utf-8'))

    def arb_keys(data: dict) -> set[str]:
        return {k for k in data if not k.startswith('@')}

    for label, data in (('app_en.arb', en_arb), ('app_de.arb', de_arb)):
        keys = arb_keys(data)
        missing = sorted(contract - keys)
        if missing:
            problems.append('%s is missing keys: %s' % (label, ', '.join(missing)))
        extra = sorted(keys - contract)
        if extra:
            problems.append('%s has keys without a contract member: %s'
                            % (label, ', '.join(extra)))

    if sorted(arb_keys(en_arb)) != sorted(arb_keys(de_arb)):
        problems.append('app_en.arb and app_de.arb do not have the same keys')

    # 5) placeholder parity for parameterized members (warnings only)
    warnings: list[str] = []
    for name in sorted(a_methods):
        for label, data in (('app_en.arb', en_arb), ('app_de.arb', de_arb)):
            meta = data.get('@%s' % name)
            if not meta or 'placeholders' not in meta:
                warnings.append('%s: "%s" is parameterized but declares no '
                                'placeholders metadata' % (label, name))

    for warning in warnings:
        print('  warning: %s' % warning)

    if problems:
        print('LOCALIZATION CONSISTENCY: %d problem(s), %d warning(s)'
              % (len(problems), len(warnings)))
        for problem in problems:
            print('  - %s' % problem)
        return 1

    print('LOCALIZATION CONSISTENCY: OK')
    print('  contract members : %d (%d getters, %d methods)'
          % (len(contract), len(a_getters), len(a_methods)))
    print('  app_en.arb keys  : %d' % len(arb_keys(en_arb)))
    print('  app_de.arb keys  : %d' % len(arb_keys(de_arb)))
    print('  members used     : %d' % len(used))
    print('  warnings         : %d' % len(warnings))
    return 0


if __name__ == '__main__':
    sys.exit(main())
