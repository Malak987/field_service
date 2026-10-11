#!/usr/bin/env python3
"""Check that every `implements X` class declares all of X's members.

Adding a method to an interface (`JobsRepository`, `JobsRemoteDataSource`, ...)
turns every implementer that lacks it into a hard compile error. This script
walks `lib/` and `test/`, resolves each `implements` clause to a class declared
somewhere in the project, and reports missing members.

It is deliberately syntactic (no Dart analyzer needed): member names are what
matter here, not signatures — a missing override is the failure mode that a
sandbox without the Dart SDK cannot otherwise catch.

Usage: python3 tool/check_interface_implementations.py
Exit code 0 = nothing missing, 1 = problems found.
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CLASS_DECL = re.compile(r'^\s*(?:(?:abstract|base|interface|final|sealed|mixin)\s+)*class\s+(\w+)'
                        r'(?:\s+extends\s+[\w<>,\s]+?)?'
                        r'(?:\s+with\s+[\w<>,\s]+?)?'
                        r'((?:\s+implements\s+[\w<>,\s]+?)?)\s*\{',
                        re.MULTILINE)
MODIFIERS = r'(?:static\s+|final\s+|const\s+|late\s+|external\s+)*'
MEMBER = re.compile(r'^\s*(?:@\w+\s*)*' + MODIFIERS +
                    r'(?:Future<[^;{=]*?>|Stream<[^;{=]*?>|[\w<>,?\s]+?)\s+'
                    r'(\w+)\s*(?:\(|=>|;|\{)')
GETTER = re.compile(r'^\s*' + MODIFIERS +
                    r'[\w<>,?\s]+?\s+get\s+(\w+)\s*(?:async\*?\s*)?(?:=>|;|\{)')
CTOR = re.compile(r'^\s*(\w+)\s*\(')


def dart_files() -> list[str]:
    found: list[str] = []
    for base in ('lib', 'test'):
        for dirpath, _dirs, files in os.walk(os.path.join(ROOT, base)):
            for name in files:
                if name.endswith('.dart') and not name.endswith('.g.dart'):
                    found.append(os.path.join(dirpath, name))
    return sorted(found)


def class_bodies(text: str) -> dict[str, str]:
    """Map class name -> its brace-balanced body."""
    bodies: dict[str, str] = {}
    for match in CLASS_DECL.finditer(text):
        name = match.group(1)
        brace = text.index('{', match.end() - 1)
        depth = 0
        for index in range(brace, len(text)):
            if text[index] == '{':
                depth += 1
            elif text[index] == '}':
                depth -= 1
                if depth == 0:
                    bodies[name] = text[brace + 1:index]
                    break
    return bodies


def member_names(body: str, skip_static: bool = True) -> set[str]:
    """Member names declared directly in a class body (depth 1 only).

    `static` members are not part of an instance contract, and `_private`
    members are library-scoped — neither can be "missing" from an implementer
    in another library, so both are skipped by default.
    """
    names: set[str] = set()
    depth = 0
    for line in body.split('\n'):
        stripped = line.strip()
        if not stripped or stripped.startswith('//') or stripped.startswith('///'):
            depth += line.count('{') - line.count('}')
            continue
        if depth == 0:
            if skip_static and re.match(r'\s*static\b', line):
                continue
            getter = GETTER.match(line)
            if getter:
                names.add(getter.group(1))
            else:
                member = MEMBER.match(line)
                if member:
                    name = member.group(1)
                    # Skip keywords that the loose regex may capture.
                    if name not in {'if', 'for', 'while', 'switch', 'return',
                                    'else', 'case', 'do', 'try', 'catch'}:
                        names.add(name)
                else:
                    ctor = CTOR.match(line)
                    if ctor:
                        names.add(ctor.group(1))
        depth += line.count('{') - line.count('}')
        if depth < 0:
            depth = 0
    return names


def implements_of(text: str) -> list[tuple[str, list[str]]]:
    """(class name, [implemented interfaces]) for every class in a file."""
    result = []
    for match in CLASS_DECL.finditer(text):
        clause = (match.group(2) or '').strip()
        if not clause:
            continue
        clause = clause[len('implements'):].strip()
        interfaces = [part.strip().split('<')[0].strip()
                      for part in clause.split(',') if part.strip()]
        result.append((match.group(1), interfaces))
    return result


def main() -> int:
    files = dart_files()
    declarations: dict[str, str] = {}
    for path in files:
        text = open(path, encoding='utf-8').read()
        for name, body in class_bodies(text).items():
            # First declaration wins (test files use unique private names).
            declarations.setdefault(name, body)

    problems: list[str] = []
    checked = 0
    for path in files:
        text = open(path, encoding='utf-8').read()
        bodies = class_bodies(text)
        for class_name, interfaces in implements_of(text):
            for interface in interfaces:
                if interface not in declarations:
                    continue  # SDK / package type — out of scope
                expected = member_names(declarations[interface])
                # Members inherited by the interface's own supertypes are not
                # resolvable syntactically; only check what it declares.
                if not expected:
                    continue
                actual = member_names(bodies[class_name])
                # Constructors of the interface are not part of its contract,
                # and private members are library-scoped.
                expected = {m for m in expected
                            if m != interface and not m.startswith('_')}
                # A class that forwards everything through `noSuchMethod`
                # satisfies the contract at runtime (Dart allows this).
                if 'noSuchMethod' in actual:
                    continue
                missing = sorted(expected - actual)
                checked += 1
                if missing:
                    problems.append('%s (%s) does not implement %s: %s'
                                    % (class_name, os.path.relpath(path, ROOT),
                                       interface, ', '.join(missing)))

    if problems:
        print('INTERFACE IMPLEMENTATIONS: %d problem(s)' % len(problems))
        for problem in problems:
            print('  - %s' % problem)
        return 1

    print('INTERFACE IMPLEMENTATIONS: OK (%d implements clauses checked '
          'against project-declared interfaces)' % checked)
    return 0


if __name__ == '__main__':
    sys.exit(main())
