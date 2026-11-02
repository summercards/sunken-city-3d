#!/usr/bin/env python3
"""导出并发布 Windows 单文件 exe（pck 内嵌，双击即玩）。

与 daily_release.py 的区别：那边发的是 exe + pck 的 zip 包，必须整包解压、
漏了 pck 就跑不起来；这里用独立预设 `Windows Desktop (单文件)`（embed_pck=true）
导出一个自包含 exe，单独一条链接。

导出后必须验证 pck 真的嵌进去了 —— 只看"导出成功"不够：
Godot 的 embed 失败也能产出一个只有引擎、没有游戏数据的 exe。

用法：
    python3 scripts/release_single_exe.py              # 导出 + 发布（原地更新）
    python3 scripts/release_single_exe.py --no-export  # 复用已有 exe 只发布
    python3 scripts/release_single_exe.py --skip-publish
"""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))

import daily_release as dr  # noqa: E402  复用 find_godot / find_publish / run / check_pack_assets

PRESET = 'Windows Desktop (单文件)'
OUT_DIR = dr.BUILD / 'windows_single'
OUT_EXE = OUT_DIR / 'sea.exe'

STATE_KEY = 'windows_single'
TITLE = 'sea 单文件版（Windows x64 独立 exe）'
DESC = ('Godot 4.6.3 导出的 Windows x64 单文件可执行程序，游戏数据已内嵌，'
        '下载后直接双击运行，无需解压、无需附带 pck。')

EXPORT_TIMEOUT = 1800
PUBLISH_TIMEOUT = 3600
# 内嵌 pck 尾部：pck 数据 + 12 字节尾注 + "GDPC" 魔数，共 16 字节
TRAILER = 16


def log(msg):
    print(f'[{dt.datetime.now():%H:%M:%S}] {msg}', flush=True)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def find_embedded_pck(data):
    """返回内嵌 pck 的起始偏移；找不到返回 None。

    pck 头是 `GDPC` + u32 version + u32 major + u32 minor。文件里也会有别的
    GDPC 字样（资源内容里可能碰巧出现），所以要按头部字段校验。
    """
    import struct
    offsets = []
    i = data.find(b'GDPC')
    while i != -1:
        offsets.append(i)
        i = data.find(b'GDPC', i + 1)
    # 倒序找：内嵌 pck 一定是靠后的那个大块
    for off in reversed(offsets):
        if off < 1024 or off + 16 > len(data):
            continue
        version, major, minor = struct.unpack_from('<III', data, off + 4)
        if version == 3 and 3 <= major <= 5 and minor <= 20:
            return off
    return None


def verify_embedded(exe):
    """确认 exe 里真的嵌了 pck，并跑资产契约。返回 (ok, detail)。"""
    data = exe.read_bytes()
    size = len(data)
    if data[:2] != b'MZ':
        return False, '不是 PE 可执行文件（缺 MZ 头）'
    if data[-4:] != b'GDPC':
        return False, '文件末尾没有 GDPC 魔数，pck 未内嵌'

    off = find_embedded_pck(data)
    if off is None:
        return False, '找不到内嵌 pck 头'

    pck = data[off:size - TRAILER]
    if len(pck) < 1048576:
        return False, f'内嵌 pck 过小（{len(pck)} 字节），大概率导出残缺'

    # 抽出来交给现有资产契约检查：字体/数据必须真的在包里
    tmp = Path(tempfile.gettempdir()) / 'sea_single_embedded.pck'
    tmp.write_bytes(pck)
    checker = ROOT / 'scripts' / 'check_pack_assets.py'
    code, out = dr.run([sys.executable, str(checker), str(tmp), '--quiet'], 600)
    tmp.unlink(missing_ok=True)
    tail = out.strip().splitlines()[-2:]
    if code != 0:
        return False, f'资产契约不成立：{tail}'
    return True, {'exe_bytes': size, 'pck_offset': off, 'pck_bytes': len(pck),
                  'pack_check': tail}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--no-export', action='store_true', help='复用已有 exe，只发布')
    ap.add_argument('--skip-publish', action='store_true')
    args = ap.parse_args()

    result = {
        'started': dt.datetime.now().isoformat(timespec='seconds'),
        'preset': PRESET, 'problems': [],
    }
    dr.RELEASE_DIR.mkdir(parents=True, exist_ok=True)
    state = dr.load_state()

    if not args.no_export:
        godot = dr.find_godot()
        if not godot:
            result['problems'].append('找不到 godot 可执行文件')
            log('找不到 godot，中止')
        else:
            OUT_DIR.mkdir(parents=True, exist_ok=True)
            if OUT_EXE.exists():
                OUT_EXE.unlink()          # 不能留着旧 exe 让失败看起来成功
            log(f'导出单文件 exe（{PRESET}）')
            started = time.time()
            code, out = dr.run([godot, '--headless', '--path', str(dr.GODOT_DIR),
                                '--export-release', PRESET, str(OUT_EXE)],
                               EXPORT_TIMEOUT)
            result['export'] = {
                'code': code,
                'seconds': round(time.time() - started, 1),
                'tail': out.strip().splitlines()[-3:] if out.strip() else [],
            }
            if code != 0 or not OUT_EXE.exists():
                result['problems'].append('导出失败')
                log(f'导出失败（code {code}）')

    if not result['problems']:
        log('校验内嵌 pck')
        ok, detail = verify_embedded(OUT_EXE)
        result['verify'] = detail
        if not ok:
            result['problems'].append(f'单文件校验失败：{detail}')
            log(f'  校验失败：{detail}')
        else:
            result['size_bytes'] = detail['exe_bytes']
            result['mib'] = round(detail['exe_bytes'] / 1048576, 1)
            result['sha256'] = sha256_of(OUT_EXE)
            log(f"  {result['mib']} MiB，内嵌 pck {detail['pck_bytes']} 字节")

    if not result['problems'] and not args.skip_publish:
        publish_py = dr.find_publish()
        if not publish_py:
            result['problems'].append('找不到 publish.py')
        else:
            site_id = (state.get(STATE_KEY) or {}).get('site_id')
            cmd = [sys.executable, str(publish_py), 'server', str(OUT_EXE)]
            if site_id:
                cmd += ['--update', '--site-id', site_id]
            else:
                cmd += ['--name', 'sea-windows-single', '--title', TITLE, '--desc', DESC]
            log(f'发布（{"原地更新 " + site_id if site_id else "新建站点"}）')
            code, out = dr.run(cmd, PUBLISH_TIMEOUT)
            url = None
            for line in out.splitlines():
                if line.startswith('URL:') or line.startswith('文件地址:'):
                    url = line.split(':', 1)[1].strip()
                if line.startswith('Site ID:'):
                    site_id = line.split(':', 1)[1].strip()
            result['publish'] = {
                'code': code, 'site_id': site_id, 'url': url,
                'tail': out.strip().splitlines()[-5:] if out.strip() else [],
            }
            if code == 0 and site_id:
                state[STATE_KEY] = {
                    'site_id': site_id, 'url': url,
                    'updated': dt.datetime.now().isoformat(timespec='seconds'),
                }
                dr.save_state(state)
            else:
                result['problems'].append('发布失败')

    result['finished'] = dt.datetime.now().isoformat(timespec='seconds')
    result['ok'] = not result['problems']
    out_json = dr.RELEASE_DIR / f'{dt.date.today():%Y-%m-%d}_single_exe.json'
    out_json.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')

    print('\n===== 结果 =====')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print(f'记录: {out_json}')
    url = (state.get(STATE_KEY) or {}).get('url')
    if url:
        print(f'single_exe: {url}')
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
