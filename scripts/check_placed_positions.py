#!/usr/bin/env python3
"""Check that every manually placed structure keeps a row in the position ledger.

Rule (AGENTS.md #12, GDD section 0): the transform a user dragged into
`godot/scenes/main.tscn` is the only truth for placement. `zones.json` origins
and coordinates written in design docs are *reference* positions handed in when
the structure was first introduced. Reference and actual may legitimately
differ; what must never happen is an undocumented difference.

Fails when:
  1. a bound structure is placed in main.tscn but has no row in the ledger;
  2. the ledger row's actual position disagrees with main.tscn;
  3. a ledger row lists a reference position that disagrees with zones.json;
  4. a ledger row names a node that no longer exists in main.tscn.

Warnings (never failures) when:
  - a placed structure's basis is non-uniformly scaled, which is a drag-handle
    accident signature rather than a placement decision.
"""
import argparse
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / 'godot' / 'scenes' / 'main.tscn'
ZONES = ROOT / 'godot' / 'assets' / 'data' / 'zones.json'
LEDGER = ROOT / 'docs' / 'features' / 'world' / 'placed_positions.md'

POS_TOL = 0.01      # ledger must match main.tscn to the centimetre
REF_TOL = 0.5       # reference vs actual beyond this is "moved", needs a row
SCALE_TOL = 0.02


def parse_main(path):
    """Return {node_path: {'translation': [x,y,z], 'basis': [[r0],[r1],[r2]], 'line': n}}."""
    text = path.read_text(encoding='utf-8')
    nodes = {}
    current = None
    line_no = 0
    for line_no, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        m = re.match(r'\[node name="([^"]+)"(.*)\]$', line)
        if m:
            name, attrs = m.group(1), m.group(2)
            parent = re.search(r'parent="([^"]*)"', attrs)
            if 'parent="' in attrs:
                p = parent.group(1) if parent else '.'
                node_path = name if p in ('', '.') else p + '/' + name
            else:
                node_path = name
            current = node_path
            nodes[current] = {'translation': None, 'basis': None, 'line': line_no}
            continue
        if current and line.startswith('transform = Transform3D('):
            inner = re.search(r'Transform3D\((.*)\)', line)
            nums = [float(v) for v in re.findall(r'-?[0-9.]+', inner.group(1))] if inner else []
            if len(nums) >= 12:
                xx, xy, xz, yx, yy, yz, zx, zy, zz, ox, oy, oz = nums[:12]
                nodes[current]['basis'] = [[xx, xy, xz], [yx, yy, yz], [zx, zy, zz]]
                nodes[current]['translation'] = [ox, oy, oz]
    return nodes


def parse_zones(path):
    data = json.loads(path.read_text(encoding='utf-8'))
    out = {}
    for z in data:
        binding = z.get('scene_binding')
        if binding:
            out[binding] = {'id': z['id'], 'origin': z.get('origin') or [0, 0, 0]}
    return out


def parse_ledger(path):
    """Rows: | `node/path` | zone_id | `x, y, z` | `x, y, z` | dist | scale note | ... |"""
    rows = {}
    if not path.exists():
        return rows
    for raw in path.read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line.startswith('|'):
            continue
        cells = [c.strip() for c in line.strip('|').split('|')]
        if len(cells) < 3:
            continue
        node = cells[0].strip('` ').strip()
        if not node or node.startswith('---') or node.startswith('节点'):
            continue
        ref = num3(cells[2]) if len(cells) > 2 else None
        act = num3(cells[3]) if len(cells) > 3 else None
        note = cells[5] if len(cells) > 5 else ''
        if node:
            rows[node] = {'zone': cells[1].strip('` ').strip(), 'ref': ref,
                          'actual': act, 'scale_note': note}
    return rows


def num3(cell):
    nums = re.findall(r'-?[0-9]+(?:\.[0-9]+)?', cell)
    if len(nums) < 3:
        return None
    return [float(v) for v in nums[:3]]


def dist(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def col_len(basis, index):
    return math.sqrt(sum(basis[r][index] ** 2 for r in range(3)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--quiet', action='store_true')
    args = ap.parse_args()

    for needed in (MAIN, ZONES):
        if not needed.exists():
            print('FAIL: missing ' + str(needed))
            return 1

    nodes = parse_main(MAIN)
    zones = parse_zones(ZONES)
    rows = parse_ledger(LEDGER)

    problems = []
    warnings = []
    checked = 0

    if not LEDGER.exists():
        problems.append('position ledger missing: ' + str(LEDGER.relative_to(ROOT)))

    for binding, info in sorted(zones.items()):
        node = nodes.get(binding)
        if node is None or node['translation'] is None:
            problems.append('%s: bound node %s not found with a transform in main.tscn'
                            % (info['id'], binding))
            continue
        checked += 1
        actual = node['translation']
        ref = [float(v) for v in info['origin']]
        row = rows.get(binding)

        if row is None:
            if dist(ref, actual) > REF_TOL:
                problems.append('%s (%s): moved %.2f m from reference but has no ledger row'
                                % (info['id'], binding, dist(ref, actual)))
            continue

        if row['actual'] is not None and dist(row['actual'], actual) > POS_TOL:
            problems.append('%s (%s): ledger actual %s != main.tscn %s'
                            % (info['id'], binding, fmt(row['actual']), fmt(actual)))
        if row['ref'] is not None and dist(row['ref'], ref) > REF_TOL:
            problems.append('%s (%s): ledger reference %s != zones.json origin %s'
                            % (info['id'], binding, fmt(row['ref']), fmt(ref)))

        basis = node['basis']
        lengths = [col_len(basis, i) for i in range(3)]
        if max(lengths) - min(lengths) > SCALE_TOL:
            confirmed = '有意' in row['scale_note']
            message = ('%s (%s): non-uniform scale %s at main.tscn:%d'
                       % (info['id'], binding,
                          '/'.join('%.3f' % v for v in lengths), node['line']))
            if confirmed:
                if not args.quiet:
                    print('NOTE: ' + message + ' — confirmed intentional by user')
            else:
                warnings.append(message + ' — ledger has no 「有意」 mark, ask the user')

    # Non-zone SeaStructures (ordinary buildings/retired landmarks) own no zones.json
    # row, but their authored transform still requires the same position ledger.
    for binding, node in nodes.items():
        if not binding.startswith('World/SeaStructures/') or binding.count('/') != 2 or binding in zones:
            continue
        if node['translation'] is None:
            problems.append('%s: non-zone structure has no explicit transform' % binding)
            continue
        checked += 1
        row = rows.get(binding)
        if row is None:
            problems.append('%s: non-zone structure has no position ledger row' % binding)
            continue
        if row['actual'] is None or dist(row['actual'], node['translation']) > POS_TOL:
            problems.append('%s: ledger actual %s != main.tscn %s' %
                            (binding, row['actual'], node['translation']))
        if row['ref'] is None:
            problems.append('%s: initial reference position missing from ledger' % binding)
        basis = node['basis']
        lengths = [col_len(basis, i) for i in range(3)]
        if max(lengths) - min(lengths) > SCALE_TOL and '有意' not in row['scale_note']:
            warnings.append('%s: non-uniform scale without user confirmation' % binding)

    for node in rows:
        if node not in nodes:
            problems.append('ledger row %s: node no longer exists in main.tscn' % node)

    if not args.quiet:
        print('placed structures checked: %d' % checked)
        for w in warnings:
            print('WARN: ' + w)
        for p in problems:
            print('FAIL: ' + p)
    if problems:
        print('FAIL: %d placement issue(s)' % len(problems))
        return 1
    print('PASS: %d placed structure(s), %d warning(s)' % (checked, len(warnings)))
    return 0


def fmt(v):
    return '(%.6f, %.6f, %.6f)' % tuple(v)


if __name__ == '__main__':
    sys.exit(main())
