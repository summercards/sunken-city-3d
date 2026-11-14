#!/usr/bin/env python3
"""B4 A08 离线证据协议与纯 Python 负例；不启动引擎、不查找或读取玩家存档。

自测：python3 -B -m unittest discover -s tests/tooling -p test_lifecycle_evidence.py -v
收集：python3 -B tests/tooling/test_lifecycle_evidence.py --input RUN.log \
    --source-exit-code 0 --report /工程外/新报告.json
JSON：--input samples.json（格式由 synthetic_document 展示，但合成样本永不签真机通过）。

日志沿用 profile 的“标签 + JSON”：[lifecycle-evidence] 后分别为
{"type":"meta", ...}、{"type":"sample", ...}，最后独立一行
[lifecycle-evidence] complete。源进程退出码必须显式传入，不推测退出成功。
JSON 顶层为 schema_version/meta/samples；日志 meta 行同样需 schema_version=1。
meta 的 head/working_tree/run_id 对应 runner 的 head/working_tree/label；
user_data_name 必须来自 runner 的 sea-verification/<隔离目录>。

每个 scenario 独立进程/测量范围，cycle 从1连续；至少3轮 warmup 再3轮 measure。
采样必须在返回/重置/销毁完成并等待延迟释放后的同一检查点（settled=true）。
objects/nodes/resources 沿用 profile monitor 字段，orphan_nodes 另测；
WeakRef 必须在销毁前登记实际目标，释放 Callable 后再测捕获对象及持有槽位；
weakrefs_checked/callables_checked 必须非零，不能用未布探针的0代替释放成功。
tree_residuals 为应释放目标仍在树中的路径，不是全树节点数。
所有计数由外部 Godot 探针提供，本工具只校验/分析，不声称证明输入真实性。
末两轮预热须稳定，测量窗口不能高于稳定基线或继续波动；不拿冷启动作基线。
这是保守的观测窗口门禁，不是泄漏归因、全设备或长期零泄漏证明。
退出码：0=真实输入窗口通过，1=观测失败，2=UNEXECUTED/缺失或无效证据。
"""
from contextlib import redirect_stdout
import copy
import hashlib
import io
import json
from pathlib import Path
import re
import tempfile
import unittest
import argparse

SCENARIOS = ('dive_return', 'reset', 'create_destroy')
COUNTS = ('objects', 'nodes', 'resources', 'orphan_nodes')
PROBES = ('weakrefs_checked', 'weakrefs_alive', 'callables_checked', 'callables_retained')
PREFIX = '[lifecycle-evidence] '
LONG_MATRIX = [
    'Godot 长期潜水往返：默认家园/各来源、正常/缺氧/取消/异常退场。',
    'Godot 长期重置：重复成功、失败恢复、跨进程重启。',
    'Godot 长期重复创建/销毁：会话、面板、Callable 捕获对象及延迟释放。',
    '真实渲染、导出包与目标设备长期矩阵（headless 不能替代）。',
]


def natural(value):
    return type(value) is int and value >= 0


def validate(document):
    """严格检查输入边界；不为缺失计数补0，不排序掩盖重复/乱序轮次。"""
    if not isinstance(document, dict) or document.get('schema_version') != 1:
        raise ValueError('schema_version 必须为1')
    meta = document.get('meta')
    if not isinstance(meta, dict):
        raise ValueError('缺少 meta')
    for key in ('run_id', 'head', 'engine', 'renderer', 'user_data_name'):
        if not isinstance(meta.get(key), str) or not meta[key].strip():
            raise ValueError('meta 缺少非空字符串：' + key)
    if not isinstance(meta.get('working_tree'), str):
        raise ValueError('meta 缺少 working_tree 快照')
    user_parts = meta['user_data_name'].split('/')
    if (user_parts[0] != 'sea-verification' or len(user_parts) < 2
            or any(part in ('', '.', '..') for part in user_parts)):
        raise ValueError('只接受 runner 隔离 user_data_name')
    if meta.get('evidence_kind') not in ('godot', 'synthetic'):
        raise ValueError('evidence_kind 必须显式为 godot 或 synthetic')
    if type(meta.get('source_exit_code')) is not int:
        raise ValueError('缺少源进程实际 source_exit_code')
    if type(meta.get('completion_marker')) is not bool:
        raise ValueError('缺少 completion_marker')
    errors = meta.get('unexpected_errors')
    if not isinstance(errors, list) or any(not isinstance(line, str) or not line for line in errors):
        raise ValueError('缺少 unexpected_errors 列表（JSON须保留源日志错误）')
    samples = document.get('samples')
    if not isinstance(samples, list):
        raise ValueError('缺少 samples 列表')
    groups = {name: [] for name in SCENARIOS}
    for row in samples:
        if not isinstance(row, dict) or row.get('scenario') not in groups:
            raise ValueError('未知 scenario 或非法采样行')
        rows = groups[row['scenario']]
        if type(row.get('cycle')) is not int or row['cycle'] != len(rows) + 1:
            raise ValueError('cycle 必须从1连续且不重复')
        if row.get('phase') not in ('warmup', 'measure'):
            raise ValueError('phase 必须为 warmup 或 measure')
        if row.get('settled') is not True:
            raise ValueError('缺少延迟释放后的 settled 检查点')
        for key in COUNTS + PROBES:
            if not natural(row.get(key)):
                raise ValueError('缺失或非法非负整数：' + key)
        if row['weakrefs_checked'] == 0 or row['callables_checked'] == 0:
            raise ValueError('WeakRef/Callable 探针必须实际登记目标，不能空测')
        if row['weakrefs_alive'] > row['weakrefs_checked']:
            raise ValueError('WeakRef 存活数大于检查数')
        if row['callables_retained'] > row['callables_checked']:
            raise ValueError('Callable 保留数大于检查数')
        residuals = row.get('tree_residuals')
        if not isinstance(residuals, list) or any(not isinstance(p, str) or not p for p in residuals):
            raise ValueError('缺失或非法 tree_residuals 路径列表')
        if rows and rows[-1]['phase'] == 'measure' and row['phase'] == 'warmup':
            raise ValueError('禁止测量后重新预热以隐藏增长')
        rows.append(row)
    return meta, groups


def inspect(document, log_text=''):
    report = {'schema_version': 1, 'label': 'b4-a08-lifecycle',
              'status': 'UNEXECUTED', 'exit_code': 2, 'passed': False,
              'engine_launched': False, 'real_samples': False,
              'real_rendering': [], 'expected_errors': [], 'unexpected_errors': [],
              'completion_marker': False, 'results': {}, 'problems': [],
              'unexecuted': list(LONG_MATRIX),
              'scope': '只分析提供的采样窗口；不签长期矩阵或零泄漏。'}
    for line in log_text.splitlines():
        if re.search(r'SCRIPT ERROR|SHADER ERROR|ERROR:|\bFAIL\b|'
                     r'ObjectDB instances (?:were )?leaked|'
                     r'\d+ resources still in use at exit', line, re.I):
            report['unexpected_errors'].append(line)
    try:
        meta, groups = validate(document)
    except ValueError as error:
        report['problems'].append('无有效证据：' + str(error))
        if report['unexpected_errors']:
            report.update(status='FAIL', exit_code=1)
        return report
    report.update({key: meta[key] for key in
                   ('run_id', 'head', 'working_tree', 'engine', 'renderer',
                    'user_data_name', 'source_exit_code', 'completion_marker', 'evidence_kind')})
    report['unexpected_errors'].extend(line for line in meta['unexpected_errors']
                                       if line not in report['unexpected_errors'])
    missing = []
    failures = list(report['unexpected_errors'])
    if meta['source_exit_code'] != 0:
        failures.append('源进程退出码非零：' + str(meta['source_exit_code']))
    if not meta['completion_marker']:
        missing.append('缺少完成标记，运行可能截断')
    for name, rows in groups.items():
        warm = [row for row in rows if row['phase'] == 'warmup']
        measured = [row for row in rows if row['phase'] == 'measure']
        result = {'status': 'UNEXECUTED', 'passed': False, 'warmup_cycles': len(warm),
                  'measured_cycles': len(measured), 'metrics': {}, 'problems': []}
        report['results'][name] = result
        for row in rows:
            for key in ('weakrefs_alive', 'callables_retained'):
                if row[key]:
                    result['problems'].append(f"cycle={row['cycle']} {key}={row[key]}")
            if row['tree_residuals']:
                result['problems'].append(f"cycle={row['cycle']} 树残留：{row['tree_residuals']}")
        if len(warm) < 3 or len(measured) < 3:
            missing.append(name + ' 至少需要3轮预热和3轮测量')
        else:
            for key in COUNTS:
                baseline = warm[-1][key]
                values = [row[key] for row in measured]
                metrics = {'cold': warm[0][key], 'baseline': baseline,
                           'warmup_delta': baseline - warm[0][key],
                           'min': min(values), 'max': max(values),
                           'end_delta': values[-1] - baseline,
                           'peak_delta': max(values) - baseline,
                           'window_growth': values[-1] - values[0]}
                result['metrics'][key] = metrics
                if warm[-2][key] != baseline:
                    result['problems'].append(key + ' 预热未稳定，不能建立基线')
                if max(values) > baseline:
                    result['problems'].append(key + ' 超出预热稳定值')
                if len(set(values)) != 1:
                    result['problems'].append(key + ' 测量窗口未稳定')
            result['status'] = 'FAIL' if result['problems'] else 'PASS'
        if result['problems']:
            result['status'] = 'FAIL'
            failures.extend(name + ': ' + message for message in result['problems'])
        result['passed'] = result['status'] == 'PASS' and meta['evidence_kind'] == 'godot'
        if result['status'] == 'PASS' and meta['evidence_kind'] == 'synthetic':
            result['status'] = 'SYNTHETIC_ONLY'
    if meta['evidence_kind'] == 'synthetic':
        missing.append('仅有合成 JSON/日志样本；Godot 实际生命周期采样 UNEXECUTED')
    report['real_samples'] = meta['evidence_kind'] == 'godot' and any(groups.values())
    report['problems'].extend(failures)
    report['unexecuted'].extend(missing)
    if failures:
        report.update(status='FAIL', exit_code=1)
    elif not missing:
        report.update(status='PASS', exit_code=0, passed=True)
    return report


def parse_log(text, source_exit_code):
    meta = None
    samples = []
    complete = False
    for line in text.splitlines():
        if not line.startswith(PREFIX):
            continue
        payload = line[len(PREFIX):]
        if complete:
            raise ValueError('完成标记后仍有采样或重复完成标记')
        if payload == 'complete':
            complete = True
            continue
        row = json.loads(payload)
        if not isinstance(row, dict):
            raise ValueError('日志记录必须为JSON对象')
        kind = row.pop('type', None)
        if kind == 'meta' and meta is None and not samples:
            meta = row
        elif kind == 'sample' and meta is not None:
            samples.append(row)
        else:
            raise ValueError('日志需唯一meta，之后仅sample/complete')
    if meta is None:
        raise ValueError('日志没有生命周期采样；普通profile对象计数不能替代释放证据')
    version = meta.pop('schema_version', None)
    meta.update(source_exit_code=source_exit_code, completion_marker=complete)
    return {'schema_version': version, 'meta': meta, 'samples': samples}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, help='只读取显式指定的日志或JSON，不递归发现输入')
    parser.add_argument('--source-exit-code', type=int, help='headless日志源进程的实际退出码')
    parser.add_argument('--report', type=Path, help='工程外新JSON文件，拒绝覆盖现有文件')
    args = parser.parse_args(argv)
    report = inspect(None)
    try:
        if args.input:
            raw = str(args.input)
            path = args.input.expanduser().resolve()
            # 不访问系统玩家目录，即使输入/符号链接显式指向那里也拒绝。
            forbidden = ('/Library/Application Support/', '/.local/share/', '/AppData/')
            if 'user:' in raw or any(part in path.as_posix() + '/' for part in forbidden):
                raise ValueError('拒绝读取 user:// 或系统玩家数据目录；请提供工程外日志副本')
            data = path.read_bytes()
            text = data.decode('utf-8-sig')
            if path.suffix.lower() == '.json':
                if args.source_exit_code is not None:
                    raise ValueError('JSON使用meta.source_exit_code，禁止命令行覆盖')
                report = inspect(json.loads(text))
            else:
                report = inspect(parse_log(text, args.source_exit_code), text)
            report['source'] = {'path': str(path), 'sha256': hashlib.sha256(data).hexdigest()}
    except (OSError, UnicodeError, ValueError) as error:
        report = inspect(None, locals().get('text', ''))
        report['problems'].append(str(error))
    if args.report:
        try:
            output = args.report.expanduser().resolve()
            repo = Path(__file__).resolve().parents[2]
            if output.is_relative_to(repo):
                raise ValueError('报告必须放工程外')
            with output.open('x', encoding='utf-8') as stream:
                json.dump(report, stream, ensure_ascii=False, indent=2)
                stream.write('\n')
        except (OSError, ValueError) as error:
            report.update(status='UNEXECUTED', exit_code=2, passed=False)
            report['problems'].append('报告未写入：' + str(error))
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return report['exit_code']


def synthetic_document():
    """唯一样本模板：明确 synthetic，全部数值只是单元测试夹具。"""
    samples = []
    for name in SCENARIOS:
        for cycle in range(1, 7):
            samples.append({'scenario': name, 'cycle': cycle,
                            'phase': 'warmup' if cycle <= 3 else 'measure',
                            'settled': True, 'objects': 100 if cycle == 1 else 140,
                            'nodes': 20, 'resources': 10, 'orphan_nodes': 0,
                            'weakrefs_checked': 2, 'weakrefs_alive': 0,
                            'callables_checked': 2, 'callables_retained': 0,
                            'tree_residuals': []})
    return {'schema_version': 1, 'meta': {
        'run_id': 'synthetic-unit-test', 'head': 'synthetic-not-a-commit', 'working_tree': '',
        'engine': 'synthetic-not-godot', 'renderer': 'headless',
        'user_data_name': 'sea-verification/synthetic-unit-test',
        'evidence_kind': 'synthetic', 'source_exit_code': 0, 'completion_marker': True,
        'unexpected_errors': []},
        'samples': samples}


class LifecycleEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.doc = synthetic_document()

    def sample(self, cycle=6, scenario='dive_return'):
        return next(row for row in self.doc['samples']
                    if row['cycle'] == cycle and row['scenario'] == scenario)

    def assert_status(self, status, code):
        report = inspect(self.doc)
        self.assertEqual((report['status'], report['exit_code']), (status, code), report)
        self.assertEqual(report['passed'], code == 0)
        return report

    def test_warmup_jump_is_not_measured_growth_or_real_evidence(self):
        report = self.assert_status('UNEXECUTED', 2)
        metric = report['results']['dive_return']['metrics']['objects']
        self.assertEqual((metric['warmup_delta'], metric['peak_delta']), (40, 0))
        self.assertFalse(report['real_samples'])
        self.assertTrue(all(not row['passed'] for row in report['results'].values()))

    def test_declared_real_window_pass_is_not_engine_execution(self):
        # 仅测试分支；此夹具未运行Godot，不能作为交付的真实采样。
        self.doc['meta']['evidence_kind'] = 'godot'
        report = self.assert_status('PASS', 0)
        self.assertFalse(report['engine_launched'])
        self.assertEqual(report['real_rendering'], [])
        self.assertEqual(report['unexecuted'], LONG_MATRIX)

    def test_every_scenario_and_counter_growth_fails(self):
        original = copy.deepcopy(self.doc)
        for scenario in SCENARIOS:
            for key in COUNTS:
                with self.subTest(scenario=scenario, key=key):
                    self.doc = copy.deepcopy(original)
                    self.sample(6, scenario)[key] += 1
                    self.assert_status('FAIL', 1)

    def test_flat_but_above_warm_baseline_fails(self):
        for cycle in (4, 5, 6):
            self.sample(cycle)['objects'] += 1
        self.assert_status('FAIL', 1)

    def test_peak_then_return_not_hidden_by_end_delta(self):
        self.sample(5)['objects'] += 4
        report = self.assert_status('FAIL', 1)
        self.assertEqual(report['results']['dive_return']['metrics']['objects']['end_delta'], 0)

    def test_warmup_still_growing_fails(self):
        self.sample(3)['objects'] += 1
        self.assert_status('FAIL', 1)

    def test_weak_callable_and_tree_residuals_fail_without_count_growth(self):
        for key, value in [('weakrefs_alive', 1), ('callables_retained', 1),
                           ('tree_residuals', ['/root/OldRuntime'])]:
            with self.subTest(key=key):
                self.doc = synthetic_document()
                self.sample()[key] = value
                self.assert_status('FAIL', 1)

    def test_incomplete_matrix_unexecuted(self):
        self.doc['samples'] = [row for row in self.doc['samples'] if row['scenario'] != 'reset']
        self.doc['meta']['evidence_kind'] = 'godot'
        self.assert_status('UNEXECUTED', 2)

    def test_short_empty_or_truncated_unexecuted(self):
        for samples in ([], self.doc['samples'][:-1]):
            with self.subTest(samples=len(samples)):
                document = synthetic_document()
                document['samples'] = samples
                self.assertEqual(inspect(document)['exit_code'], 2)
        self.doc['meta']['completion_marker'] = False
        self.assert_status('UNEXECUTED', 2)

    def test_missing_invalid_and_empty_probe_never_defaults_zero(self):
        for key in COUNTS + PROBES + ('tree_residuals', 'settled'):
            for value in (None, -1, False, '0'):
                with self.subTest(key=key, value=value):
                    self.doc = synthetic_document()
                    self.sample()[key] = value
                    self.assert_status('UNEXECUTED', 2)
        for key in ('weakrefs_checked', 'callables_checked'):
            self.doc = synthetic_document()
            self.sample()[key] = 0
            self.assert_status('UNEXECUTED', 2)

    def test_missing_fields_and_impossible_probe_counts_unexecuted(self):
        for key in COUNTS + PROBES + ('tree_residuals', 'settled'):
            with self.subTest(key=key):
                self.doc = synthetic_document()
                del self.sample()[key]
                self.assert_status('UNEXECUTED', 2)
        for key in ('weakrefs_alive', 'callables_retained'):
            self.doc = synthetic_document()
            self.sample()[key] = 3
            self.assert_status('UNEXECUTED', 2)

    def test_bad_cycle_and_rewarming_unexecuted(self):
        for key, value in [('cycle', 1), ('phase', 'warmup')]:
            self.doc = synthetic_document()
            self.sample()[key] = value
            self.assert_status('UNEXECUTED', 2)

    def test_source_exit_timeout_or_missing_never_pass(self):
        for code in (1, 124, -9, None):
            self.doc = synthetic_document()
            self.doc['meta']['evidence_kind'] = 'godot'
            self.doc['meta']['source_exit_code'] = code
            self.assert_status('UNEXECUTED' if code is None else 'FAIL', 2 if code is None else 1)

    def log(self):
        meta = dict(self.doc['meta'], type='meta', schema_version=1)
        return '\n'.join([PREFIX + json.dumps(meta)] +
                         [PREFIX + json.dumps(dict(row, type='sample')) for row in self.doc['samples']] +
                         [PREFIX + 'complete'])

    def test_json_and_headless_protocol_equivalent(self):
        parsed = parse_log('Godot Engine\n' + self.log(), 0)
        self.assertEqual(parsed, self.doc)
        self.assertEqual(inspect(parsed), inspect(self.doc))

    def test_log_completion_and_actual_exit_required(self):
        for text, code in [(self.log().replace(PREFIX + 'complete', ''), 0), (self.log(), None)]:
            self.assertEqual(inspect(parse_log(text, code))['exit_code'], 2)
        for text in (self.log() + '\n' + PREFIX + 'complete', PREFIX + '{bad',
                     '[performance-audit] {"objects":100}\n[performance-audit] complete'):
            with self.assertRaises(ValueError):
                parse_log(text, 0)

    def test_exit_leaks_and_engine_errors_never_filtered_as_expected(self):
        for warning in ('WARNING: 9 ObjectDB instances were leaked at exit',
                        'WARNING: ObjectDB instances leaked at exit',
                        'ERROR: 2 resources still in use at exit', 'SCRIPT ERROR: invalid call'):
            with self.subTest(warning=warning):
                report = inspect(self.doc, self.log() + '\n' + warning)
                self.assertEqual(report['exit_code'], 1)
                self.assertIn(warning, report['unexpected_errors'])
                self.assertEqual(report['expected_errors'], [])

    def test_json_errors_not_hidden_by_zero_exit(self):
        self.doc['meta']['evidence_kind'] = 'godot'
        self.doc['meta']['unexpected_errors'] = ['SCRIPT ERROR: invalid call']
        report = self.assert_status('FAIL', 1)
        self.assertEqual(report['unexpected_errors'], ['SCRIPT ERROR: invalid call'])
        del self.doc['meta']['unexpected_errors']
        self.assert_status('UNEXECUTED', 2)

    def test_real_player_user_name_rejected(self):
        for name in ('sea', 'sea-verification/../sea', 'sea-verification/'):
            self.doc['meta']['user_data_name'] = name
            self.assert_status('UNEXECUTED', 2)

    def test_cli_no_input_is_unexecuted(self):
        with redirect_stdout(io.StringIO()) as output:
            self.assertEqual(main([]), 2)
        self.assertEqual(json.loads(output.getvalue())['status'], 'UNEXECUTED')

    def test_cli_inputs_report_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for suffix, content, extra in [('.json', json.dumps(self.doc), []),
                                            ('.log', self.log(), ['--source-exit-code', '0'])]:
                source = root / ('sample' + suffix)
                source.write_text(content, encoding='utf-8')
                target = root / ('report' + suffix + '.json')
                argv = ['--input', str(source), '--report', str(target)] + extra
                with redirect_stdout(io.StringIO()):
                    self.assertEqual(main(argv), 2)
                report = json.loads(target.read_text())
                self.assertEqual(report['source']['sha256'], hashlib.sha256(source.read_bytes()).hexdigest())
                before = target.read_bytes()
                with redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(main(argv), 2)
                self.assertIn('报告未写入', output.getvalue())
                self.assertEqual(before, target.read_bytes())
                self.assertEqual(source.read_text(), content)

    def test_cli_missing_malformed_or_unsafe_inputs_unexecuted(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bad = root / 'bad.json'
            bad.write_text('{broken')
            for source in (bad, root / 'missing.log', Path('user://save.json'),
                           Path.home() / 'Library/Application Support/sea/save.json'):
                with self.subTest(source=source), redirect_stdout(io.StringIO()):
                    self.assertEqual(main(['--input', str(source)]), 2)


if __name__ == '__main__':
    raise SystemExit(main())
