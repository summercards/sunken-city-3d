"""Regression tests for false-green prevention and master document governance."""
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
sys.path.insert(0, str(ROOT / 'godot/tools'))
from check_feature_contracts import graph_errors, ledger_meta, parse_master
from run_verification import inspect_log
from authored_guard import require_candidate


class EngineeringGuards(unittest.TestCase):
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


if __name__ == '__main__':
    unittest.main()
