"""D05/R06 独立纯 Python 正反例；所有包和许可都是临时合成夹具。"""
from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/audit_release_closure.py'
SPEC = importlib.util.spec_from_file_location('audit_release_closure', SCRIPT)
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class ReleaseClosureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.release = self.root / 'release'
        self.release.mkdir()
        self.repo.mkdir()
        self.pack = self.release / 'sea.pck'
        self.closure = self.root / 'closure.json'
        self.config = {'schema_version': 1, 'required_data': ['res://assets/data/new.json'],
                       'dynamic_resources': [], 'licenses': []}
        self.index = {'domains': {'ui': {'ledger': 'assets/registry/ledgers/ui.json',
                                       'asset_key': 'assets'}},
                      'runtime_inventory': 'assets/registry/runtime.json'}
        self.rows = []
        self.manifests = ['assets/data/new.json']
        self.write_json('assets/registry/ledger_index.json', self.index)
        self.write_json('assets/registry/runtime.json', {'resources': []})
        self.write_json('assets/registry/ledgers/ui.json', {'assets': []})

    def write(self, root, path, data):
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        return target

    def write_json(self, path, document):
        return self.write(self.repo, path, json.dumps(document).encode())

    def make_pack(self, names=None, version=4, embedded=False):
        names = self.manifests if names is None else names
        payload = b'{}'
        directory = bytearray(struct.pack('<I', len(names)))
        for name in names:
            encoded = ('res://' + name).encode()
            encoded += b'\0' * (-len(encoded) % 4)
            directory += struct.pack('<I', len(encoded)) + encoded
            directory += struct.pack('<QQ16sI', 0, len(payload), hashlib.md5(payload).digest(), 0)
        header = bytearray(96 if version == 2 else 40)
        struct.pack_into('<4sIIIIIQQ', header, 0, b'GDPC', version, 4, 7, 2, 2,
                         len(header), len(header) + len(payload))
        if version == 2:
            body = bytes(header) + bytes(directory) + payload
        else:
            body = bytes(header) + payload + bytes(directory)
        if embedded:
            body = b'MZ' + b'\0' * 1022 + body + struct.pack('<Q4s', len(body), b'GDPC')
        self.pack.write_bytes(body)

    def run_audit(self):
        self.closure.write_text(json.dumps(self.config))
        self.write_json('assets/registry/ledgers/ui.json', {'assets': self.rows})
        return AUDIT.audit(self.pack, self.release, self.closure, self.repo)

    def assert_code(self, result, code, exit_code=1):
        self.assertEqual(result['exit_code'], exit_code, result)
        self.assertFalse(result['passed'])
        self.assertIn(code, [item['code'] for item in result['problems']], result)

    def font(self, status='SIL-OFL-1.1'):
        font = 'src/ui/fonts/test.ttf'
        ofl = 'src/ui/fonts/OFL.txt'
        self.config['dynamic_resources'].append(font)
        self.rows.append({'asset_id': 'FONT', 'runtime_path': 'godot/' + font,
                          'license': status, 'license_file': 'godot/' + ofl})
        self.write(self.repo, 'godot/' + ofl, b'SIL OPEN FONT LICENSE')
        self.write(self.release, 'licenses/OFL.txt', b'SIL OPEN FONT LICENSE')
        self.config['licenses'].append({'source': 'godot/' + ofl, 'path': 'licenses/OFL.txt',
                                        'license': 'SIL-OFL-1.1', 'status': 'verified'})
        self.manifests.append(font)

    def extension(self):
        extension = 'addons/test/test.gdextension'
        lib = 'addons/test/bin/native.dll'
        self.write(self.repo, 'godot/' + extension,
                   ('[libraries]\nwindows.release.x86_64 = "res://' + lib + '"\n').encode())
        self.write(self.repo, 'godot/addons/test/LICENSE.txt', b'MIT license')
        self.write(self.release, 'licenses/plugin-LICENSE.txt', b'MIT license')
        self.write(self.release, 'native.dll', b'native fixture')
        self.config['licenses'].append({'source': 'godot/addons/test/LICENSE.txt',
                                        'path': 'licenses/plugin-LICENSE.txt',
                                        'license': 'MIT', 'status': 'verified'})
        self.config['target_features'] = ['windows', 'release', 'x86_64']
        self.manifests.append(extension)

    def test_missing_pack_is_unexecuted(self):
        self.assert_code(self.run_audit(), 'UNEXECUTED', 2)

    def test_no_inputs_cli_returns_json_unexecuted(self):
        with redirect_stdout(io.StringIO()) as output:
            code = AUDIT.main(['--json'])
        result = json.loads(output.getvalue())
        self.assertEqual(code, 2)
        self.assertEqual(result['status'], 'UNEXECUTED')
        self.assertFalse(result['export_executed'])

    def test_missing_config_never_uses_include_filter(self):
        self.make_pack()
        self.write(self.repo, 'godot/export_presets.cfg', b'include_filter="*.json"')
        result = AUDIT.audit(self.pack, self.release, None, self.repo)
        self.assert_code(result, 'UNEXECUTED', 2)

    def test_empty_config_is_unexecuted(self):
        self.make_pack()
        self.config.update(required_data=[], dynamic_resources=[], include_filter='*.json')
        self.assert_code(self.run_audit(), 'UNEXECUTED', 2)

    def test_minimal_valid_closure(self):
        self.make_pack()
        result = self.run_audit()
        self.assertEqual(result['status'], 'PASS', result)
        self.assertEqual(result['exit_code'], 0)
        self.assertIn('未执行', result['unexecuted'][0])

    def test_valid_font_and_external_library_closure(self):
        self.font()
        self.extension()
        self.make_pack()
        self.assertEqual(self.run_audit()['exit_code'], 0)

    def test_missing_font_license_blocks(self):
        self.font()
        self.config['licenses'][0]['path'] = 'missing/OFL.txt'
        self.make_pack()
        self.assert_code(self.run_audit(), 'MISSING_LICENSE')

    def test_missing_source_license_blocks(self):
        self.config['licenses'].append({'source': 'godot/missing/OFL.txt', 'path': 'OFL.txt',
                                        'license': 'SIL-OFL-1.1'})
        self.write(self.release, 'OFL.txt', b'OFL')
        self.make_pack()
        self.assert_code(self.run_audit(), 'MISSING_LICENSE')

    def test_plugin_license_missing_blocks(self):
        self.extension()
        self.config['licenses'][0]['path'] = 'missing/LICENSE.txt'
        self.make_pack()
        self.assert_code(self.run_audit(), 'MISSING_LICENSE')

    def test_pending_registry_not_overridden_by_closure(self):
        self.font('pending_provider_terms_review')
        self.make_pack()
        result = self.run_audit()
        self.assert_code(result, 'PENDING_OR_UNKNOWN')
        self.assertTrue(any('#FONT' in row['subject'] for row in result['problems']))

    def test_pending_closure_blocks(self):
        self.config['license_status'] = 'unknown'
        self.make_pack()
        self.assert_code(self.run_audit(), 'PENDING_OR_UNKNOWN')

    def test_pending_manifest_blocks(self):
        self.font()
        self.rows[0]['manifest'] = 'assets/font_manifest.json'
        self.write_json('assets/font_manifest.json', {'license_status': 'pending_review'})
        self.make_pack()
        self.assert_code(self.run_audit(), 'PENDING_OR_UNKNOWN')

    def test_pending_inventory_blocks(self):
        self.write_json('assets/registry/runtime.json', {'resources': [
            {'path': 'godot/assets/data/new.json', 'status': 'provenance_pending'}]})
        self.make_pack()
        self.assert_code(self.run_audit(), 'PENDING_OR_UNKNOWN')

    def test_unrelated_pending_source_does_not_require_whole_registry(self):
        self.rows = [{'asset_id': 'NOT_SHIPPED', 'runtime_path': None, 'license': 'pending'}]
        self.make_pack()
        self.assertEqual(self.run_audit()['exit_code'], 0)

    def test_missing_declared_data_not_hidden_by_filter(self):
        self.config['include_filter'] = '*.json'
        self.make_pack(['unrelated.json'])
        self.assert_code(self.run_audit(), 'MISSING_PACK_ENTRY')

    def test_explicit_dynamic_export_mapping_requires_all_paths(self):
        self.config['dynamic_resources'] = [{'source': 'scenes/new.tscn',
            'pack_paths': ['scenes/new.tscn.remap', '.godot/exported/new.scn']}]
        self.make_pack(self.manifests + ['scenes/new.tscn.remap'])
        self.assert_code(self.run_audit(), 'MISSING_PACK_ENTRY')
        self.make_pack(self.manifests + ['scenes/new.tscn.remap', '.godot/exported/new.scn'])
        self.assertEqual(self.run_audit()['exit_code'], 0)

    def test_project_manifest_drives_new_resources(self):
        self.config['resource_manifests'] = [{'path': 'release_resources.json', 'key': 'resources'}]
        self.write_json('release_resources.json', {'resources': ['assets/data/future.json']})
        self.make_pack()
        self.assert_code(self.run_audit(), 'MISSING_PACK_ENTRY')
        self.make_pack(self.manifests + ['assets/data/future.json'])
        self.assertEqual(self.run_audit()['exit_code'], 0)

    def test_library_inside_pck_does_not_replace_external_library(self):
        self.extension()
        self.config['external_libraries'] = {'addons/test/bin/native.dll': 'missing/native.dll'}
        self.make_pack(self.manifests + ['addons/test/bin/native.dll'])
        self.assert_code(self.run_audit(), 'MISSING_EXTERNAL_LIBRARY')

    def test_unspecified_platform_is_blocked(self):
        self.extension()
        self.config['target_features'] = []
        self.make_pack()
        self.assert_code(self.run_audit(), 'UNKNOWN_GDEXTENSION_TARGET')

    def test_unknown_asset_id_blocks(self):
        self.config['asset_ids'] = ['MISSING']
        self.make_pack()
        self.assert_code(self.run_audit(), 'UNKNOWN_ASSET')

    def test_missing_registry_license_is_unknown(self):
        self.rows = [{'asset_id': 'DATA', 'runtime_path': 'godot/assets/data/new.json'}]
        self.make_pack()
        self.assert_code(self.run_audit(), 'UNKNOWN_LICENSE')

    def test_imported_font_matches_registry_and_original_ofl(self):
        self.font('unknown_provenance')
        imported = '.godot/imported/font-test.fontdata'
        self.config['dynamic_resources'] = []
        self.write(self.repo, 'godot/src/ui/fonts/test.ttf.import',
                   ('[remap]\npath="res://' + imported + '"\n').encode())
        self.make_pack(['assets/data/new.json', imported])
        self.assert_code(self.run_audit(), 'PENDING_OR_UNKNOWN')
        self.rows[0]['license'] = 'SIL-OFL-1.1'
        self.assertEqual(self.run_audit()['exit_code'], 0)

    def test_unmapped_imported_font_is_unknown(self):
        self.make_pack(self.manifests + ['.godot/imported/unknown.fontdata'])
        self.assert_code(self.run_audit(), 'UNKNOWN_FONT_LICENSE')

    def test_explicit_imported_font_mapping_checks_source_ofl(self):
        self.font()
        imported = '.godot/imported/font-test.fontdata'
        self.config['dynamic_resources'] = [{'source': 'src/ui/fonts/test.ttf',
                                             'pack_paths': [imported]}]
        self.make_pack(['assets/data/new.json', imported])
        self.assertEqual(self.run_audit()['exit_code'], 0)

    def test_historical_pending_does_not_override_current_verified_license(self):
        self.font()
        self.rows[0]['previous_sources'] = [{'license_status': 'pending'}]
        self.make_pack()
        self.assertEqual(self.run_audit()['exit_code'], 0)

    def test_versions_and_embedded_pck(self):
        for version in (2, 3, 4):
            for embedded in (False, True):
                with self.subTest(version=version, embedded=embedded):
                    self.make_pack(version=version, embedded=embedded)
                    result = self.run_audit()
                    self.assertEqual(result['exit_code'], 0, result)
                    self.assertEqual(result['pck']['embedded'], embedded)

    def test_truncated_or_unsupported_pck_is_unexecuted(self):
        for data in (b'GDPC', b'bad', b'GDPC' + struct.pack('<I', 99) + bytes(32)):
            self.pack.write_bytes(data)
            self.assert_code(self.run_audit(), 'UNEXECUTED', 2)

    def test_traversal_config_is_unexecuted(self):
        self.make_pack()
        self.config['required_data'] = ['../escape.json']
        self.assert_code(self.run_audit(), 'UNEXECUTED', 2)

    def test_symlink_cannot_escape_closure(self):
        self.font()
        (self.release / 'escape').symlink_to(self.repo, target_is_directory=True)
        self.config['licenses'][0]['path'] = 'escape/godot/src/ui/fonts/OFL.txt'
        self.make_pack()
        self.assert_code(self.run_audit(), 'UNEXECUTED', 2)

    def test_cli_new_report_and_no_input_mutation(self):
        self.font()
        self.extension()
        self.make_pack()
        self.run_audit()
        files = [path for path in self.root.rglob('*') if path.is_file()]
        before = {str(path): path.read_bytes() for path in files}
        report = self.root / 'report.json'
        argv = ['--pack', str(self.pack), '--closure-root', str(self.release),
                '--closure', str(self.closure), '--repo-root', str(self.repo),
                '--report', str(report), '--json']
        with redirect_stdout(io.StringIO()) as output:
            self.assertEqual(AUDIT.main(argv), 0)
        self.assertTrue(json.loads(output.getvalue())['passed'])
        self.assertTrue(json.loads(report.read_text())['passed'])
        for path, data in before.items():
            self.assertEqual(Path(path).read_bytes(), data)
        with redirect_stdout(io.StringIO()):
            self.assertEqual(AUDIT.main(argv), 2)
        self.assertTrue(json.loads(report.read_text())['passed'])


if __name__ == '__main__':
    unittest.main()
