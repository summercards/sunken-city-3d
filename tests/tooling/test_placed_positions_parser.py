"""摆位检查的纯 Python 解析与失败门禁回归。"""
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    'placed_positions_checker', ROOT / 'scripts/check_placed_positions.py')
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)

BINDING = 'World/SeaStructures/test_structure'
IDENTITY = '1, 0, 0, 0, 1, 0, 0, 0, 1'
ROTATED = '+6e-1, +8E-1, 0, -.8, .6, 0, 0, 0, +1.'
SCALED = '1.2, 1.6, 0, -2.4, 1.8, 0, 0, 0, 4'
POSITION = '+1e1, -.25, +3E+0'


def scene(transform):
    return ('[gd_scene format=3]\n\n'
            '[node name="test_structure" type="Node3D" parent="World/SeaStructures"]\n'
            f'transform = {transform}\n')


class PlacedPositionsParserTests(unittest.TestCase):
    def test_num3_accepts_shared_float_grammar(self):
        for text, expected in [
                ('`(+1e1, -.25, +3E+0)`', [10.0, -.25, 3.0]),
                ('(.25, +2., -3e-2)', [.25, 2.0, -.03]),
                ('1, -2, +3', [1.0, -2.0, 3.0])]:
            with self.subTest(text=text):
                self.assertEqual(checker.num3(text), expected)

    def test_num3_rejects_partial_or_extra_numbers(self):
        for text in ('(1, 2)', '(1, 2, 3, 4)', '(1e, 2, 3)',
                     '(1..2, 2, 3)', '(--1, 2, 3)', '(1_0, 2, 3)',
                     '(NaN, 2, 3)', '(inf, 2, 3)', '(1e999, 2, 3)',
                     '(1x, 2, 3)', '位置(1, 2, 3)', '(1 2 3)',
                     '(1, 2, 3),', '(1, 2, 3) trailing'):
            with self.subTest(text=text):
                self.assertIsNone(checker.num3(text))

    def test_transform_preserves_serialized_basis_columns_and_translation(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'main.tscn'
            path.write_text(scene(f'Transform3D({ROTATED}, {POSITION})'), encoding='utf-8')
            node = checker.parse_main(path)[BINDING]
        self.assertEqual(node['translation'], [10.0, -.25, 3.0])
        self.assertEqual(node['basis'], [[.6, .8, 0.0], [-.8, .6, 0.0], [0.0, 0.0, 1.0]])
        for index in range(3):
            self.assertAlmostEqual(checker.col_len(node['basis'], index), 1.0)

    def test_scaled_rotation_measures_columns_not_rows(self):
        basis = [[1.2, 1.6, 0.0], [-2.4, 1.8, 0.0], [0.0, 0.0, 4.0]]
        for index, expected in enumerate((2.0, 3.0, 4.0)):
            self.assertAlmostEqual(checker.col_len(basis, index), expected)

    def test_transform_requires_exactly_twelve_complete_finite_numbers(self):
        valid = f'{IDENTITY}, 10, -.25, 3'
        invalid = [
            f'Transform3D({IDENTITY}, 10, -.25)',
            f'Transform3D({valid}, 99)',
            f'Transform3D({valid},)',
            f'Transform3D({IDENTITY}, 1e, -.25, 3)',
            f'Transform3D({IDENTITY}, 1..2, -.25, 3)',
            f'Transform3D({IDENTITY}, NaN, -.25, 3)',
            f'Transform3D({IDENTITY}, 1e999, -.25, 3)',
            f'Transform3D({IDENTITY}, 1_0, -.25, 3)',
            f'Transform3D({valid}) trailing',
            f'Transform3D({valid}',
        ]
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'main.tscn'
            for transform in invalid:
                with self.subTest(transform=transform):
                    path.write_text(scene(transform), encoding='utf-8')
                    with self.assertRaisesRegex(ValueError, r'main\.tscn:4:.*Transform3D'):
                        checker.parse_main(path)


class PlacedPositionsGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.main_path = self.root / 'main.tscn'
        self.zones_path = self.root / 'zones.json'
        self.ledger_path = self.root / 'placed_positions.md'

    def prepare(self, *, bound=True, basis=ROTATED, note='', actual=POSITION,
                reference='0, 0, 0', include_row=True):
        self.main_path.write_text(scene(f'Transform3D({basis}, {POSITION})'), encoding='utf-8')
        zones = [{'id': 'test_zone', 'scene_binding': BINDING, 'origin': [0, 0, 0]}] if bound else []
        self.zones_path.write_text(json.dumps(zones), encoding='utf-8')
        row = (f'| `{BINDING}` | `test_zone` | `({reference})` | `({actual})` '
               f'| 参考偏差 | {note} | 用户手摆 |\n')
        self.ledger_path.write_text(row if include_row else '', encoding='utf-8')

    def run_checker(self, *args):
        paths = (self.main_path, self.zones_path, self.ledger_path)
        before = {path: path.read_bytes() for path in paths if path.exists()}
        output = io.StringIO()
        with patch.multiple(checker, ROOT=self.root, MAIN=self.main_path,
                            ZONES=self.zones_path, LEDGER=self.ledger_path), \
                patch.object(sys, 'argv', ['check_placed_positions.py', *args]), \
                redirect_stdout(output):
            code = checker.main()
        for path, content in before.items():
            self.assertEqual(path.read_bytes(), content, f'检查不得修改 {path.name}')
        return code, output.getvalue()

    def test_scientific_position_and_rotated_basis_accept_user_placement(self):
        for bound in (True, False):
            with self.subTest(bound=bound):
                self.prepare(bound=bound)
                code, output = self.run_checker()
                self.assertEqual(code, 0, output)
                self.assertIn('1 placed structure(s), 0 warning(s)', output)

    def test_nonuniform_scale_only_warns_unless_intentionally_approved(self):
        for bound in (True, False):
            for note, warnings in (('', 1), ('待确认', 1), ('**有意** —— 用户确认', 0)):
                with self.subTest(bound=bound, note=note):
                    self.prepare(bound=bound, basis=SCALED, note=note)
                    code, output = self.run_checker()
                    self.assertEqual(code, 0, output)
                    self.assertIn(f'{warnings} warning(s)', output)
                    self.assertEqual('WARN:' in output, warnings == 1)
                    if bound and warnings:
                        self.assertIn('2.000/3.000/4.000', output)
                    if bound and not warnings:
                        self.assertIn('NOTE:', output)

    def test_missing_ledger_file_fails(self):
        self.prepare()
        self.ledger_path.unlink()
        code, output = self.run_checker()
        self.assertEqual(code, 1, output)
        self.assertIn('position ledger missing', output)

    def test_missing_ledger_row_fails_even_at_reference(self):
        for bound in (True, False):
            for at_reference in (True, False):
                with self.subTest(bound=bound, at_reference=at_reference):
                    self.prepare(bound=bound, include_row=False)
                    if bound and at_reference:
                        self.zones_path.write_text(json.dumps([{
                            'id': 'test_zone', 'scene_binding': BINDING,
                            'origin': [10, -.25, 3]}]), encoding='utf-8')
                    code, output = self.run_checker()
                    self.assertEqual(code, 1, output)
                    self.assertIn('no ', output)
                    self.assertIn('ledger row', output)

    def test_mismatching_actual_or_reference_fails(self):
        for bound, kwargs in ((True, {'actual': '11, -.25, 3'}),
                              (False, {'actual': '11, -.25, 3'}),
                              (True, {'reference': '2, 0, 0'})):
            with self.subTest(bound=bound, kwargs=kwargs):
                self.prepare(bound=bound, **kwargs)
                code, output = self.run_checker()
                self.assertEqual(code, 1, output)
                self.assertIn('!=', output)

    def test_malformed_ledger_coordinates_fail_in_both_paths(self):
        for bound in (True, False):
            for kwargs in ({'actual': '1e, -.25, 3'}, {'reference': '0, 0, 0, 4'}):
                with self.subTest(bound=bound, kwargs=kwargs):
                    self.prepare(bound=bound, **kwargs)
                    code, output = self.run_checker()
                    self.assertEqual(code, 1, output)
                    self.assertIn('FAIL:', output)

    def test_invalid_transform_reports_failure_without_traceback(self):
        self.prepare()
        self.main_path.write_text(scene(f'Transform3D({IDENTITY}, {POSITION}, 4)'), encoding='utf-8')
        code, output = self.run_checker('--quiet')
        self.assertEqual(code, 1, output)
        self.assertIn('FAIL:', output)
        self.assertIn('main.tscn:4:', output)


if __name__ == '__main__':
    unittest.main()
