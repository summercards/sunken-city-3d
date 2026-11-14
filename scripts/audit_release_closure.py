#!/usr/bin/env python3
"""D05/R06 只读发行闭包审计；不调用 Godot、导出器或发布脚本。

用法：python3 scripts/audit_release_closure.py --pack /发行/sea.pck \
    --closure-root /发行 --closure /配置/closure.json --json
退出码：0=声明范围静态通过，1=BLOCKED，2=UNEXECUTED（输入缺失/不可验证）。
--report 只允许新建报告，绝不覆盖现有文件；默认仅输出，不写磁盘。

closure JSON v1 示例（路径均禁止越界；registry 路径相对仓库根）：
{
  "schema_version": 1,
  "required_data": ["res://assets/data/new_catalog.json"],
  "dynamic_resources": [
    {"source": "res://scenes/new.tscn",
     "pack_paths": ["scenes/new.tscn.remap", ".godot/exported/new.scn"]}
  ],
  "resource_manifests": [
    {"path": "project_release_resources.json", "key": "resources"}
  ],
  "asset_ids": [],
  "target_features": ["windows", "release", "x86_64"],
  "gdextensions": [],
  "external_libraries": {},
  "licenses": [
    {"source": "godot/src/ui/fonts/OFL.txt", "path": "licenses/OFL.txt",
     "location": "external", "license": "SIL-OFL-1.1", "status": "verified"}
  ]
}
required_data 必须原样入包；dynamic_resources 的 pack_paths 为必须全部存在的
显式导出条目（不猜 .remap 的目标）。resource_manifests 是项目提供的 JSON
路径清单，指定顶层 key，其元素与 dynamic_resources 相同；不默认要求全库入包。
GDExtension 从包内条目及 gdextensions 读取项目声明，按 target_features 匹配
最具体 libraries 项；external_libraries 可把 res:// 库路径映射到闭包相对路径。
许可检查覆盖实际/声明资源命中的 registry、manifest、字体 OFL 及插件 LICENSE。
声明范围不代表全工程、平台运行、法律结论或 payload 完整性验收。
"""
import argparse
import configparser
import json
from pathlib import Path, PurePosixPath
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
BAD_STATUS = re.compile(r'pending|unknown|unverified|unreviewed|待核|未知', re.I)


def relative(value):
    if not isinstance(value, str) or not value or '\\' in value or '\x00' in value:
        raise ValueError(f'非法相对路径：{value!r}')
    value = value.removeprefix('res://')
    path = PurePosixPath(value)
    if path.is_absolute() or '..' in path.parts or ':' in value or value == '.':
        raise ValueError(f'路径越界：{value}')
    return path.as_posix()


def within(root, value):
    path = (root / relative(value)).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f'路径或符号链接越界：{value}')
    return path


def load_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def read_pack(pack):
    """仅读真实 PCK 索引，支持格式 2/3/4 及尾注定位的内嵌 PCK。"""
    with pack.open('rb') as stream:
        stream.seek(0, 2)
        total = stream.tell()
        start, end = 0, total
        stream.seek(0)
        if stream.read(4) != b'GDPC':
            if total < 12:
                raise ValueError('包过短')
            stream.seek(total - 12)
            size, magic = struct.unpack('<Q4s', stream.read(12))
            start, end = total - 12 - size, total - 12
            if magic != b'GDPC' or start < 0 or size < 40:
                raise ValueError('缺少有效 PCK 头或内嵌尾注')
        stream.seek(start)

        def read(size):
            if size < 0 or stream.tell() + size > end:
                raise ValueError('PCK 索引截断')
            data = stream.read(size)
            if len(data) != size:
                raise ValueError('PCK 索引截断')
            return data

        header = read(40)
        if header[:4] != b'GDPC':
            raise ValueError('内嵌 PCK 头无效')
        version = struct.unpack_from('<I', header, 4)[0]
        flags = struct.unpack_from('<I', header, 20)[0]
        if version not in (2, 3, 4) or flags & 1:
            raise ValueError('不支持的 PCK 格式或加密目录')
        directory = 96 if version == 2 else struct.unpack_from('<Q', header, 32)[0]
        if directory < 40 or start + directory + 4 > end:
            raise ValueError('PCK 目录偏移无效')
        stream.seek(start + directory)
        count = struct.unpack('<I', read(4))[0]
        if count == 0 or count > (end - stream.tell()) // 40:
            raise ValueError('PCK 条目数量无效')
        entries = {}
        for _ in range(count):
            length = struct.unpack('<I', read(4))[0]
            if length == 0:
                raise ValueError('PCK 路径为空')
            name = relative(read(length).rstrip(b'\0').decode('utf-8'))
            offset, size, digest, file_flags = struct.unpack('<QQ16sI', read(36))
            if name in entries or file_flags & 2:
                raise ValueError(f'重复或删除型 PCK 条目：{name}')
            if size > end - start:
                raise ValueError(f'PCK 条目大小越界：{name}')
            entries[name] = size
        return {'format': version, 'embedded': start != 0,
                'entry_count': count, 'entries': entries}


def resource(row):
    if isinstance(row, str):
        name = relative(row)
        return name, [name]
    source = relative(row['source'])
    paths = row['pack_paths']
    if not isinstance(paths, list) or not paths:
        raise ValueError(f'pack_paths 必须是非空列表：{source}')
    return source, [relative(path) for path in paths]


def audit(pack=None, closure_root=None, closure=None, repo_root=ROOT):
    report = {'status': 'UNEXECUTED', 'passed': False, 'exit_code': 2,
              'pack': str(pack) if pack else None,
              'closure_root': str(closure_root) if closure_root else None,
              'closure': str(closure) if closure else None,
              'problems': [], 'checks': [],
              'unexecuted': ['真实平台运行、渲染和 payload 完整性验证未执行'],
              'export_executed': False}

    def problem(code, subject, detail):
        report['problems'].append({'code': code, 'subject': subject, 'detail': detail})

    missing = False
    for label, path, directory in [('pack', pack, False), ('closure', closure, False),
                                   ('closure_root', closure_root, True)]:
        if path is None or not (path.is_dir() if directory else path.is_file()):
            problem('UNEXECUTED', label, '缺少显式输入或输入不存在')
            missing = True
    if missing:
        return report
    try:
        repo_root = repo_root.resolve()
        closure_root = closure_root.resolve()
        config = load_json(closure)
        if not isinstance(config, dict) or config.get('schema_version') != 1:
            raise ValueError('closure 必须是 schema_version=1 的 JSON 对象')
        for key in ('required_data', 'dynamic_resources'):
            if not isinstance(config.get(key), list):
                raise ValueError(f'closure 必须显式声明 {key} 列表')
        declarations = [(relative(path), [relative(path)]) for path in config['required_data']]
        declarations += [resource(row) for row in config['dynamic_resources']]
        for manifest in config.get('resource_manifests', []):
            document = load_json(within(repo_root, manifest['path']))
            rows = document[manifest['key']]
            if not isinstance(rows, list):
                raise ValueError('资源清单必须指向列表')
            declarations += [resource(row) for row in rows]
        if not declarations:
            raise ValueError('闭包未声明任何数据或动态资源；include_filter 不能作为证据')
        parsed = read_pack(pack)
        report['pck'] = {key: value for key, value in parsed.items() if key != 'entries'}
        names = set(parsed['entries'])
        selected = names | {source for source, _ in declarations}
        selected.update(relative(path) for path in config.get('gdextensions', []))
        for source, expected in declarations:
            absent = sorted(set(expected) - names)
            report['checks'].append({'kind': 'resource', 'source': source,
                                     'required': expected, 'missing': absent})
            if absent:
                problem('MISSING_PACK_ENTRY', source, absent)
            empty = [path for path in expected if path in names and parsed['entries'][path] == 0]
            if empty:
                problem('EMPTY_PACK_ENTRY', source, empty)

        def statuses(document, subject, require_license=False):
            if require_license and not document.get('license'):
                problem('UNKNOWN_LICENSE', subject, 'license 缺失或为空')
            for key, value in document.items():
                if key in ('license', 'license_status', 'provenance_status', 'status', 'stage'):
                    if value is None or value == '' or BAD_STATUS.search(str(value)):
                        problem('PENDING_OR_UNKNOWN', subject, {key: value})
                elif key in ('previous_sources', 'hash_history', 'history', 'license_history'):
                    continue
                elif isinstance(value, dict):
                    statuses(value, subject + '.' + key)
                elif isinstance(value, list):
                    for index, item in enumerate(value):
                        if isinstance(item, dict):
                            statuses(item, f'{subject}.{key}[{index}]')

        statuses(config, 'closure')
        license_rows = config.get('licenses', [])
        license_map = {}
        for row in license_rows:
            source = relative(row['source'])
            if source.startswith('godot/'):
                source = source[6:]
            if source in license_map:
                raise ValueError(f'重复许可映射：{source}')
            license_map[source] = row

        def license_file(source):
            rel = relative(source)
            rel = rel.removeprefix('godot/')
            row = license_map.get(rel)
            location = row.get('location', 'external') if row else None
            destination = relative(row['path']) if row else rel
            if location not in (None, 'external', 'pack'):
                raise ValueError(f'未知许可 location：{location}')
            shipped = ((destination in names and parsed['entries'][destination] > 0)
                       if location == 'pack' else
                       (within(closure_root, destination).is_file() and
                        within(closure_root, destination).stat().st_size > 0))
            if location is None:
                shipped = shipped or (rel in names and parsed['entries'][rel] > 0)
            source_path = within(repo_root, 'godot/' + rel)
            exists = source_path.is_file() and source_path.stat().st_size > 0
            report['checks'].append({'kind': 'license_file', 'source': source,
                                     'destination': destination, 'source_exists': exists,
                                     'shipped': shipped})
            if not exists or not shipped:
                problem('MISSING_LICENSE', source, '源许可或发行闭包中的非空许可文件缺失')

        for row in license_rows:
            statuses(row, 'closure.licenses:' + row['source'], require_license=True)
            license_file(row['source'])

        index = load_json(within(repo_root, 'assets/registry/ledger_index.json'))
        requested = set(config.get('asset_ids', []))
        found = set()
        font_licenses = set()
        imported_fonts = set()

        def shipped_resource(path):
            if path in selected or path + '.remap' in names or path.removesuffix('.gd') + '.gdc' in names:
                return True
            metadata = within(repo_root, 'godot/' + path + '.import')
            if metadata.is_file():
                destinations = {relative(value) for value in re.findall(
                    r'"(res://[^"]+)"', metadata.read_text(encoding='utf-8'))}
                hits = destinations & names
                if hits and path.lower().endswith(('.ttf', '.otf')):
                    selected.add(path)
                    imported_fonts.update(hits)
                return bool(hits)
            return False

        for route in index['domains'].values():
            ledger = load_json(within(repo_root, route['ledger']))
            for row in ledger[route.get('asset_key', 'assets')]:
                paths = [row.get(key) for key in ('runtime_path', 'prefab')]
                paths += row.get('stage_models', {}).values() if isinstance(row.get('stage_models'), dict) else []
                paths = [relative(path).removeprefix('godot/') for path in paths if isinstance(path, str)]
                matched = row['asset_id'] in requested or any(
                    shipped_resource(path) or any(name.startswith(path.rstrip('/') + '/')
                                                  for name in selected)
                    for path in paths)
                if not matched:
                    continue
                found.add(row['asset_id'])
                statuses(row, route['ledger'] + '#' + row['asset_id'], require_license=True)
                report['checks'].append({'kind': 'registry', 'asset_id': row['asset_id']})
                if row.get('manifest'):
                    statuses(load_json(within(repo_root, row['manifest'])), row['manifest'])
                if row.get('license_file'):
                    font_licenses.add(row['license_file'])
                    license_file(row['license_file'])
        for asset_id in sorted(requested - found):
            problem('UNKNOWN_ASSET', asset_id, 'registry 中不存在此 AssetID')
        if index.get('runtime_inventory'):
            inventory = load_json(within(repo_root, index['runtime_inventory']))
            for row in inventory['resources']:
                path = relative(row['path']).removeprefix('godot/')
                if shipped_resource(path):
                    statuses(row, index['runtime_inventory'] + '#' + path)

        declared_imports = {path for source, paths in declarations
                            if source.lower().endswith(('.ttf', '.otf')) for path in paths}
        for name in sorted(selected):
            if name.lower().endswith('.fontdata'):
                if name not in imported_fonts | declared_imports:
                    problem('UNKNOWN_FONT_LICENSE', name, '导入字体无法关联源字体及 OFL；须补资源声明或 .import')
            elif name.lower().endswith(('.ttf', '.otf')):
                parent = PurePosixPath(name).parent.as_posix()
                if not any(relative(path).removeprefix('godot/').startswith(parent + '/')
                           for path in font_licenses):
                    license_file(parent + '/OFL.txt')
        plugins = {PurePosixPath(name).parts[1] for name in selected
                   if name.startswith('addons/') and len(PurePosixPath(name).parts) > 2}
        for plugin in sorted(plugins):
            folder = within(repo_root, 'godot/addons/' + plugin)
            licenses = sorted(path for path in folder.glob('LICENSE*') if path.is_file())
            if not licenses:
                problem('MISSING_PLUGIN_LICENSE', plugin, '插件源目录缺少 LICENSE 文件')
            for path in licenses:
                license_file(path.relative_to(repo_root).as_posix())

        extensions = {name for name in names if name.endswith('.gdextension')}
        extensions.update(relative(path) for path in config.get('gdextensions', []))
        features = set(config.get('target_features', []))
        library_map = config.get('external_libraries', {})
        for extension in sorted(extensions):
            if extension not in names:
                problem('MISSING_PACK_ENTRY', extension, 'GDExtension 声明未入包')
            parser = configparser.ConfigParser(interpolation=None)
            parser.optionxform = str
            with within(repo_root, 'godot/' + extension).open(encoding='utf-8') as stream:
                parser.read_file(stream)
            options = [(key, value) for key, value in parser['libraries'].items()
                       if set(key.split('.')) <= features]
            if not features or not options:
                problem('UNKNOWN_GDEXTENSION_TARGET', extension, '未声明目标 features 或无匹配库')
                continue
            specificity = max(len(key.split('.')) for key, _ in options)
            options = [(key, value) for key, value in options if len(key.split('.')) == specificity]
            if len(options) != 1:
                problem('UNKNOWN_GDEXTENSION_TARGET', extension, '目标库匹配存在歧义')
                continue
            key, value = options[0]
            lib = relative(json.loads(value))
            destination = library_map.get('res://' + lib, library_map.get(lib, PurePosixPath(lib).name))
            path = within(closure_root, destination)
            exists = path.is_file() and path.stat().st_size > 0
            if path.is_dir() and path.suffix == '.framework':
                binary = path / path.stem
                exists = binary.is_file() and binary.stat().st_size > 0
            report['checks'].append({'kind': 'external_library', 'extension': extension,
                                     'target': key, 'source': lib, 'destination': destination,
                                     'exists': exists})
            if not exists:
                problem('MISSING_EXTERNAL_LIBRARY', lib, '原生库必须在发行闭包外置，PCK 条目不替代它')
        report['status'] = 'BLOCKED' if report['problems'] else 'PASS'
        report['exit_code'] = 1 if report['problems'] else 0
        report['passed'] = not report['problems']
    except (OSError, ValueError, KeyError, TypeError, AttributeError, configparser.Error, struct.error) as exc:
        problem('UNEXECUTED', 'input', f'输入或配置无法完整验证：{exc}')
        report['unexecuted'].append('输入不完整，闭包审计未完成')
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--pack', type=Path, help='显式 PCK/bin 或内嵌 PCK 的可执行文件')
    parser.add_argument('--closure-root', type=Path, help='解包后的发行闭包目录（不自动解压）')
    parser.add_argument('--closure', type=Path, help='项目声明的 closure JSON')
    parser.add_argument('--repo-root', type=Path, default=ROOT)
    parser.add_argument('--json', action='store_true', help='标准输出完整 JSON')
    parser.add_argument('--report', type=Path, help='显式新建 JSON 报告，父目录须存在')
    args = parser.parse_args(argv)
    result = audit(args.pack, args.closure_root, args.closure, args.repo_root)
    if args.report:
        try:
            with args.report.open('x', encoding='utf-8') as stream:
                json.dump(result, stream, ensure_ascii=False, indent=2)
                stream.write('\n')
        except OSError as exc:
            result.update(status='UNEXECUTED', passed=False, exit_code=2)
            result['problems'].append({'code': 'REPORT_WRITE_FAILED', 'subject': str(args.report),
                                       'detail': str(exc)})
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"{result['status']} exit={result['exit_code']}：{len(result['problems'])} 项阻断；未导出")
        for item in result['problems']:
            print(f"  {item['code']} {item['subject']}：{item['detail']}")
        for item in result['unexecuted']:
            print('UNEXECUTED ' + item)
    return result['exit_code']


if __name__ == '__main__':
    sys.exit(main())
