"""Regression tests for false-green prevention and master document governance."""
from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import types
import unittest
from unittest.mock import patch
import zlib

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
sys.path.insert(0, str(ROOT / 'godot/tools'))
from check_feature_contracts import TEXT_SUFFIXES, graph_errors, hash_matches, ledger_meta, parse_master
import run_verification
from run_verification import derive_check_config, inspect_log
from authored_guard import require_candidate


class EngineeringGuards(unittest.TestCase):
    def test_text_crlf_hash_compatibility(self):
        data = '文本\r\n第二行\r\n'.encode('utf-8')
        with tempfile.TemporaryDirectory() as temp:
            for suffix in TEXT_SUFFIXES:
                with self.subTest(suffix=suffix):
                    path = Path(temp) / ('resource' + suffix.upper())
                    path.write_bytes(data)
                    self.assertTrue(hash_matches(path, hashlib.sha256(data).hexdigest()))
                    self.assertTrue(hash_matches(path, hashlib.sha256(data.replace(b'\r\n', b'\n')).hexdigest()))
                    self.assertFalse(hash_matches(path, hashlib.sha256(b'changed\n').hexdigest()))

    def test_binary_crlf_hash_never_normalized(self):
        # 合法 GLB 的 BIN 块允许任意字节；PNG 签名本身就含 CRLF。
        doc = json.dumps({'asset': {'version': '2.0'}, 'buffers': [{'byteLength': 4}]}).encode('utf-8')
        doc += b' ' * (-len(doc) % 4)
        glb = (struct.pack('<4sII', b'glTF', 2, 32 + len(doc)) +
               struct.pack('<I4s', len(doc), b'JSON') + doc +
               struct.pack('<I4s', 4, b'BIN\x00') + b'\r\n\x00\x00')

        def chunk(kind, payload):
            return (struct.pack('>I', len(payload)) + kind + payload +
                    struct.pack('>I', zlib.crc32(kind + payload)))

        png = (b'\x89PNG\r\n\x1a\n' +
               chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)) +
               chunk(b'IDAT', zlib.compress(b'\x00\xff\x00\x00')) + chunk(b'IEND', b''))
        with tempfile.TemporaryDirectory() as temp:
            for suffix, data in [('.glb', glb), ('.png', png),
                                 ('.blend', b'BLENDER-v300\x00\r\n'),
                                 ('.glb', b'UTF-8\r\n'), ('.bin', b'UTF-8\r\n'),
                                 ('.unknown', b'UTF-8\r\n'), ('', b'UTF-8\r\n'),
                                 ('.json', b'nul\x00\r\n'), ('.txt', b'\xff\r\n')]:
                with self.subTest(suffix=suffix, data=data[:12]):
                    path = Path(temp) / ('resource' + suffix)
                    path.write_bytes(data)
                    raw_sha = hashlib.sha256(data).hexdigest()
                    normalized_sha = hashlib.sha256(data.replace(b'\r\n', b'\n')).hexdigest()
                    self.assertNotEqual(raw_sha, normalized_sha)
                    self.assertTrue(hash_matches(path, raw_sha))
                    self.assertFalse(hash_matches(path, normalized_sha))

    def test_raw_hash_match_skips_text_detection(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'resource.txt'
            data = b'raw\r\n'
            path.write_bytes(data)
            with patch('check_feature_contracts._is_text_resource', side_effect=AssertionError('不应执行文本判定')):
                self.assertTrue(hash_matches(path, hashlib.sha256(data).hexdigest()))

    def test_unknown_dependency_rejected(self):
        self.assertTrue(graph_errors([{'feature_id': 'A', 'dependencies': ['MISSING']}]))

    def test_cycle_rejected(self):
        self.assertTrue(graph_errors([{'feature_id': 'A', 'dependencies': ['B']}, {'feature_id': 'B', 'dependencies': ['A']}]))

    def test_duplicate_feature_rejected(self):
        self.assertTrue(graph_errors([{'feature_id': 'A', 'dependencies': []}] * 2))

    def test_current_master_and_ledger_identity(self):
        rows = parse_master((ROOT / 'GDD_V1.0.md').read_text())
        self.assertFalse(graph_errors(rows))
        for row in rows:
            self.assertEqual(row['feature_id'], ledger_meta((ROOT / row['ledger']).read_text())['feature_id'])

    def test_nonzero_exit_never_green(self):
        self.assertFalse(inspect_log('farming', 1, 'DONE', 'DONE')['passed'])

    def test_missing_completion_never_green(self):
        self.assertFalse(inspect_log('farming', 0, '', 'DONE')['passed'])

    def test_unexpected_error_never_green(self):
        self.assertFalse(inspect_log('farming', 0, 'SCRIPT ERROR: bad\nDONE', 'DONE')['passed'])

    def test_expected_fault_is_scoped_and_bounded(self):
        bad_json = 'ERROR: Parse JSON failed. Error at line 0: Expected key\n'
        self.assertTrue(inspect_log('selftest', 0, bad_json + 'DONE', 'DONE')['passed'])
        self.assertFalse(inspect_log('farming', 0, bad_json + 'DONE', 'DONE')['passed'])
        self.assertFalse(inspect_log('selftest', 0, bad_json * 2 + 'DONE', 'DONE')['passed'])

    def test_authored_project_refuses_generator(self):
        with self.assertRaises(SystemExit):
            require_candidate(ROOT / 'godot/tools/build_zones.py')

    def test_candidate_must_be_outside_source_repository(self):
        import json
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / 'repo/godot'
            candidate = root / 'repo/copy/godot'
            candidate.mkdir(parents=True)
            (candidate / '.sea-generation-candidate').write_text(json.dumps({'source_project': str(source)}))
            with self.assertRaises(SystemExit):
                require_candidate(candidate / 'tools/generator.py')
            external = root / 'work/godot'
            external.mkdir(parents=True)
            (external / '.sea-generation-candidate').write_text(json.dumps({'source_project': str(source)}))
            require_candidate(external / 'tools/generator.py')


class VerificationConfigGuards(unittest.TestCase):
    FULL_CONFIG = ('[application]\nrun/main_scene="res://scenes/main.tscn"\n'
                   'config/custom_user_dir_name="sea-verification/test"\n'
                   '[autoload]\nEconomy="*res://src/economy/economy.gd"\n'
                   'Zones="*res://src/world/zones.gd"\n'
                   '[gui]\ntheme/custom_font="res://assets/fonts/main.ttf"\n'
                   '[editor_plugins]\nenabled=PackedStringArray("res://addons/other/plugin.cfg")\n'
                   '[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    TOOL_CHECKS = ['workshop-random', 'plant-authoring', 'workshop-union',
                   'editor-workshop', 'editor-workshop-upgrade', 'editor-plant']
    GAME_CHECKS = ['management', 'save-seed', 'framework-integration']

    def test_tool_config_cannot_replace_full_game_config(self):
        for tool in self.TOOL_CHECKS:
            with self.subTest(tool=tool):
                tool_config = derive_check_config(self.FULL_CONFIG, tool)
                self.assertNotIn('[autoload]', tool_config)
                self.assertIn('[rendering]', tool_config)
                if tool in ['workshop-random', 'plant-authoring', 'workshop-union']:
                    self.assertNotIn('theme/custom_font=', tool_config)
                if tool.startswith('editor-'):
                    self.assertIn('run/main_scene=""', tool_config)
                    self.assertIn('res://addons/building_workshop/plugin.cfg', tool_config)
                    self.assertEqual('res://addons/plant_editor/plugin.cfg' in tool_config,
                                     tool == 'editor-plant')
                for game in self.GAME_CHECKS:
                    game_config = derive_check_config(self.FULL_CONFIG, game)
                    self.assertEqual(game_config, self.FULL_CONFIG)
                    # 负例：若把已裁剪配置当作完整配置，游戏 Autoload 无法自行恢复。
                    polluted = derive_check_config(tool_config, game)
                    self.assertNotEqual(polluted, game_config)
                    self.assertNotIn('[autoload]', polluted)

    def test_runner_tool_then_game_always_uses_full_config(self):
        for tool in self.TOOL_CHECKS:
            with self.subTest(tool=tool), tempfile.TemporaryDirectory() as temp:
                project = Path(temp) / 'project'
                project.mkdir()
                config_path = project / 'project.godot'
                config_path.write_text(self.FULL_CONFIG, encoding='utf-8')
                configs = []
                markers = {run_verification.TESTS[name][0]: marker for name, marker in [
                    (tool, '[%s] 1 checks, 0 failures' % {
                        'workshop-random': 'workshop-random', 'plant-authoring': 'plant-authoring',
                        'workshop-union': 'workshop-union', 'editor-workshop': 'workshop-editor',
                        'editor-workshop-upgrade': 'workshop-upgrade', 'editor-plant': 'plant-editor',
                    }[tool]),
                    ('management', '[management] 1 checks, 0 failed'),
                    ('save-seed', '[save-seed] ok=true'),
                    ('framework-integration', '[framework-integration] 1 checks, 0 failures'),
                ]}

                def run_check(cmd, *, stdout, **kwargs):
                    configs.append(config_path.read_text(encoding='utf-8'))
                    script = cmd[cmd.index('--script') + 1][6:] if '--script' in cmd else ''
                    stdout.write(markers[script] + '\n')
                    return types.SimpleNamespace(returncode=0)

                with patch.dict('os.environ', {'GODOT': sys.executable, 'SEA_WORK_ROOT': temp}), \
                        patch.object(sys, 'argv', ['run_verification.py', tool, 'management', 'framework-integration']), \
                        patch.object(run_verification, 'isolated_project', return_value=(project, 'sea-verification/test')), \
                        patch.object(run_verification.subprocess, 'check_output', return_value='test-head\n'), \
                        patch.object(run_verification.subprocess, 'run', side_effect=run_check), \
                        redirect_stdout(io.StringIO()):
                    self.assertEqual(run_verification.main(), 0)
                self.assertEqual(len(configs), 4)
                self.assertNotIn('[autoload]', configs[0])
                for config, game in zip(configs[1:], self.GAME_CHECKS):
                    group = 'restart' if game in ['save-seed', 'framework-integration'] else game
                    expected = self.FULL_CONFIG.replace('sea-verification/test"',
                                                        'sea-verification/test/' + group + '"')
                    self.assertEqual(config, expected)
                self.assertEqual(configs[2], configs[3])


class SealAuditGuards(unittest.TestCase):
    def run_audit(self, *, after_changes=None, glb_changes=None, missing=None, empty=False):
        path = ROOT / 'tools/blender/sunken_city/audit_seal.py'
        spec = importlib.util.spec_from_file_location('audit_seal_under_test', path)
        audit = importlib.util.module_from_spec(spec)
        # 只模拟 Blender 量测；报告聚合、哈希和退出判定执行真实 Python 代码。
        with patch.dict(sys.modules, {'bpy': types.ModuleType('bpy'), 'bmesh': types.ModuleType('bmesh')}):
            spec.loader.exec_module(audit)
        before = {'faces': 4, 'boundary_edges': 3, 'nonmanifold_edges': 0,
                  'bbox': [0, 0, 0, 1, 1, 1], 'materials': ['SEA_Matte'], 'triangles': 4}
        after = dict(before, faces=5, boundary_edges=0, triangles=6)
        after.update(after_changes or {})
        glb_data = {'triangles': 6, 'embedded_images': 0, 'surface_count': 1, 'bytes': 4}
        glb_data.update(glb_changes or {})
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            src_dir = root / 'art_source/scenes/sunken_city/v005'
            out_dir = root / 'art_source/scenes/sunken_city/v006'
            source = src_dir / 'building.blend'
            sealed = out_dir / 'component_packages/building/building.blend'
            runtime = root / 'godot/assets/models/scenery/sunken_city/building/building.glb'
            for label, file in [('source', source), ('sealed', sealed), ('glb', runtime)]:
                file.parent.mkdir(parents=True, exist_ok=True)
                if label != missing:
                    file.write_bytes(b'test')
            components = [] if empty else [{'slug': 'building', 'name': '测试建筑',
                'category': 'architecture', 'collection': 'Building',
                'component_blend': source.relative_to(root).as_posix()}]
            (src_dir / 'component_catalog.json').write_text(json.dumps({'components': components}), encoding='utf-8')
            with patch.object(audit, 'REPO', root), patch.object(sys, 'argv', ['audit_seal.py']), \
                    patch.object(audit, 'measure', side_effect=[before, after]), \
                    patch.object(audit, 'glb_info', return_value=glb_data), redirect_stdout(io.StringIO()):
                code = audit.main()
            report = json.loads((out_dir / 'seal_report.json').read_text(encoding='utf-8'))
            return code, report

    def test_complete_watertight_audit_passes(self):
        code, report = self.run_audit()
        self.assertEqual(code, 0)
        self.assertTrue(report['passed'])
        self.assertEqual(report['problems'], [])
        self.assertEqual(len(report['components']), 1)
        self.assertEqual(report['components'][0]['boundary_after'], 0)
        self.assertEqual(report['components'][0]['nonmanifold_after'], 0)
        for field in ['source_sha256', 'sealed_sha256', 'glb_sha256']:
            self.assertEqual(report['components'][0][field], hashlib.sha256(b'test').hexdigest())

    def test_each_explicit_contract_failure_is_not_green(self):
        cases = [
            ({'after_changes': {'boundary_edges': 1}}, 'boundary_after'),
            ({'after_changes': {'nonmanifold_edges': 1}}, 'nonmanifold_after'),
            ({'after_changes': {'bbox': [0, 0, 0, 2, 1, 1]}}, 'bbox changed'),
            ({'after_changes': {'materials': ['other']}}, 'material slots changed'),
            ({'after_changes': {'faces': 3}}, 'faces decreased'),
            ({'glb_changes': {'triangles': 7}}, 'glb tris'),
            ({'glb_changes': {'embedded_images': 1}}, 'glb embeds images'),
        ]
        for kwargs, problem in cases:
            with self.subTest(problem=problem):
                code, report = self.run_audit(**kwargs)
                self.assertNotEqual(code, 0)
                self.assertFalse(report['passed'])
                self.assertTrue(any(problem in p for p in report['problems']))
                self.assertEqual(len(report['components']), 1)

    def test_all_watertight_failures_are_reported(self):
        code, report = self.run_audit(after_changes={'boundary_edges': 2, 'nonmanifold_edges': 3})
        self.assertNotEqual(code, 0)
        self.assertFalse(report['passed'])
        self.assertEqual(report['components'][0]['boundary_after'], 2)
        self.assertEqual(report['components'][0]['nonmanifold_after'], 3)
        self.assertTrue(any('boundary_after=2' in p for p in report['problems']))
        self.assertTrue(any('nonmanifold_after=3' in p for p in report['problems']))

    def test_missing_inputs_or_empty_catalog_never_green(self):
        for missing in ['source', 'sealed', 'glb']:
            with self.subTest(missing=missing):
                code, report = self.run_audit(missing=missing)
                self.assertNotEqual(code, 0)
                self.assertFalse(report['passed'])
                self.assertEqual(report['components'], [])
                self.assertTrue(any('missing' in p for p in report['problems']))
                self.assertTrue(any('incomplete records' in p for p in report['problems']))
        code, report = self.run_audit(empty=True)
        self.assertNotEqual(code, 0)
        self.assertFalse(report['passed'])
        self.assertEqual(report['components'], [])
        self.assertTrue(report['problems'])


if __name__ == '__main__':
    unittest.main()
