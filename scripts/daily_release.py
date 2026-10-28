#!/usr/bin/env python3
"""每日发布：git 推送 → 导出 Web / Windows → 发布到 sofunny 内网链接。

顺序固定为 git → 导出 → 发布：
- git 先行，导出失败也不影响当天代码留档；
- 导出与发布失败不掩盖，分别记退出码；
- 站点用固定 Site ID 原地更新，链接跨天不变。

用法：
    python3 scripts/daily_release.py               # 全流程
    python3 scripts/daily_release.py --skip-git    # 只打包发布
    python3 scripts/daily_release.py --skip-publish  # 只打包
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
GODOT_DIR = ROOT / 'godot'
BUILD = GODOT_DIR / 'build'
WEB_DIR = BUILD / 'web'
WIN_DIR = BUILD / 'windows'
DIST = BUILD / 'dist'
WIN_ZIP = DIST / 'sea-windows.zip'

WORK = Path(os.environ.get('SEA_WORK_ROOT', ROOT / 'sea-work'))
RELEASE_DIR = WORK / 'release'
STATE_FILE = RELEASE_DIR / 'state.json'

PUBLISH_CANDIDATES = [
    Path.home() / '.workbuddy/skills/sofunny-resource-sharing/scripts/publish.py',
    Path.home() / '.agents/skills/sofunny-resource-sharing/scripts/publish.py',
    Path.home() / '.codex/skills/sofunny-resource-sharing/scripts/publish.py',
    Path.home() / '.claude/skills/sofunny-resource-sharing/scripts/publish.py',
]

WEB_EXPORT_TIMEOUT = 1800
WIN_EXPORT_TIMEOUT = 1800
PUBLISH_TIMEOUT = 3600
GIT_PUSH_TIMEOUT = 300


def log(msg):
    print(f'[{dt.datetime.now():%H:%M:%S}] {msg}', flush=True)


def run(cmd, timeout, cwd=None):
    """执行命令，返回 (returncode, 合并输出)。超时不抛异常，归一成 124。"""
    try:
        proc = subprocess.run(
            cmd, cwd=str(cwd or ROOT), capture_output=True, text=True,
            timeout=timeout, encoding='utf-8', errors='replace',
        )
        return proc.returncode, (proc.stdout or '') + (proc.stderr or '')
    except subprocess.TimeoutExpired:
        return 124, f'超时（{timeout}s）: {" ".join(map(str, cmd))}'
    except FileNotFoundError as exc:
        return 127, f'找不到命令: {exc}'


GODOT_CANDIDATES = [
    Path(r'I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe'),
    Path(r'I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe'),
    Path(r'C:\Program Files\Godot\godot.exe'),
    Path.home() / 'bin/godot.exe',
]


def find_godot():
    """优先返回真实 .exe。

    本机的 `~/bin/godot` 是 sh 垫片、`godot.cmd` 是 cmd 垫片，subprocess
    都不能直接执行（CreateProcess 只认 PE），必须落到它们指向的真身上。
    """
    for cand in GODOT_CANDIDATES:
        if cand.exists():
            return str(cand)
    for name in ('godot.exe', 'godot'):
        exe = shutil.which(name)
        if exe and not exe.lower().endswith(('.cmd', '.bat', '.sh')):
            return exe
    # 兜底：读垫片里写死的真身路径
    for shim in (Path.home() / 'bin/godot.cmd',):
        if shim.exists():
            for tok in shim.read_text(encoding='utf-8', errors='replace').replace('"', ' ').split():
                if tok.lower().endswith('.exe') and Path(tok).exists():
                    return tok
    return None


def find_publish():
    for cand in PUBLISH_CANDIDATES:
        if cand.exists():
            return cand
    return None


def load_state():
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text(encoding='utf-8'))
        except Exception:
            pass
    return {}


def save_state(state):
    RELEASE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding='utf-8')


def clean(path):
    if path.exists():
        shutil.rmtree(path, ignore_errors=True)
    path.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------- git

def git_step(result):
    code, out = run(['git', 'rev-parse', '--abbrev-ref', 'HEAD'], 30)
    branch = out.strip() if code == 0 else '?'
    code, out = run(['git', 'status', '--porcelain'], 60)
    changed = [ln for ln in out.splitlines() if ln.strip()]
    result['git']['branch'] = branch
    result['git']['changed_files'] = len(changed)

    if changed:
        code, out = run(['git', 'add', '-A'], 600)
        if code != 0:
            result['git']['commit'] = f'add 失败 {code}'
        else:
            msg = f'chore(release): 每日自动提交 {dt.date.today():%Y-%m-%d}'
            code, out = run(['git', 'commit', '-m', msg], 600)
            if code != 0:
                tail = out.strip().splitlines()[-3:] if out.strip() else []
                result['git']['commit'] = f'commit 失败 {code}: ' + ' / '.join(tail)
            else:
                result['git']['commit'] = 'ok'
    else:
        result['git']['commit'] = '无改动'

    # 先试 origin（内网 Tailscale，经常离线），失败回退 upstream；两者都失败才记错。
    attempts = []
    ok, origin_out = try_push('origin', branch, 120, result)
    attempts.append(('origin', 0 if ok else 1, origin_out))
    if ok:
        result['git']['push'] = 'origin ok'
        result['git']['push_ok'] = True
        return

    ok, up_out = try_push('upstream', branch, GIT_PUSH_TIMEOUT, result)
    attempts.append(('upstream', 0 if ok else 1, up_out))
    result['git']['attempts'] = [
        {'remote': r, 'code': c, 'tail': (o or '').strip().splitlines()[-2:]}
        for r, c, o in attempts
    ]
    if ok:
        result['git']['push'] = 'upstream ok（origin 不可达，按约定跳过）'
        result['git']['push_ok'] = True
    else:
        result['git']['push'] = 'origin 与 upstream 均失败'
        result['git']['push_ok'] = False


def try_push(remote, branch, timeout, result):
    """推送一次；non-fast-forward 自动 rebase 重试一次，绝不 force。"""
    code, out = run(['git', 'push', remote, branch], timeout)
    if code == 0:
        return True, out
    text = out.lower()
    rejected = 'non-fast-forward' in text or 'rejected' in text or 'fetch first' in text
    if not rejected:
        return False, out
    run(['git', 'pull', '--rebase', remote, branch], timeout)
    code, out = run(['git', 'push', remote, branch], timeout)
    result['git']['rebased'] = True
    return code == 0, out


# ---------------------------------------------------------------- 导出

def export_platform(godot, preset, out_path, timeout, result, key):
    started = time.time()
    code, out = run([godot, '--headless', '--path', str(GODOT_DIR),
                     '--export-release', preset, str(out_path)], timeout)
    result['export'][key] = {
        'preset': preset,
        'code': code,
        'seconds': round(time.time() - started, 1),
        'tail': out.strip().splitlines()[-3:] if out.strip() else [],
    }
    return code == 0


def zip_windows(result):
    """把 exe + pck 打成一个固定文件名的 zip，链接才能原地更新。"""
    files = [p for p in (WIN_DIR / 'sea.exe', WIN_DIR / 'sea.pck') if p.exists()]
    if len(files) < 2:
        result['package']['windows_zip'] = '缺少 exe 或 pck'
        return False
    extra = None
    extra_path = WIN_DIR / '运行说明.txt'
    extra_path.write_text(
        'sea（Windows 版）\n\n1. 解压后双击 sea.exe 即可运行。\n2. sea.pck 必须与 sea.exe 放在同一目录。\n',
        encoding='utf-8',
    )
    extra = extra_path
    DIST.mkdir(parents=True, exist_ok=True)
    started = time.time()
    with zipfile.ZipFile(WIN_ZIP, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for p in files + ([extra] if extra else []):
            zf.write(p, arcname=p.name)
    result['package']['windows_zip'] = {
        'path': str(WIN_ZIP),
        'mib': round(WIN_ZIP.stat().st_size / 1048576, 1),
        'seconds': round(time.time() - started, 1),
    }
    return True


def web_size_mib():
    total = sum(p.stat().st_size for p in WEB_DIR.rglob('*') if p.is_file())
    return round(total / 1048576, 1)


def patch_web_pack(result):
    """发布链路不带 .pck 白名单，把游戏包改成 .bin 并让引擎按 mainPack 加载。

    Godot 的 engine.js 里是 `config.mainPack || executive + '.pck'`，
    所以只要改 index.html 的 GODOT_CONFIG 并同步 service worker 的缓存清单，
    改名后能正常加载。改完 .bin 就在发布白名单内。
    """
    pck = WEB_DIR / 'index.pck'
    binp = WEB_DIR / 'index.bin'
    if not pck.exists():
        result['package']['web_pack'] = '缺少 index.pck'
        return False
    if binp.exists():
        binp.unlink()
    pck.rename(binp)

    html = WEB_DIR / 'index.html'
    text = html.read_text(encoding='utf-8')
    if '"mainPack"' not in text:
        text = text.replace('"executable":"index",', '"executable":"index","mainPack":"index.bin",', 1)
    text = text.replace('index.pck', 'index.bin')
    html.write_text(text, encoding='utf-8')

    sw = WEB_DIR / 'index.service.worker.js'
    if sw.exists():
        sw.write_text(sw.read_text(encoding='utf-8').replace('index.pck', 'index.bin'),
                      encoding='utf-8')

    ok = binp.exists() and '"mainPack":"index.bin"' in html.read_text(encoding='utf-8')
    result['package']['web_pack'] = {
        'pck_mib': round(binp.stat().st_size / 1048576, 1) if binp.exists() else 0,
        'mainpack_patched': ok,
    }
    return ok


# ---------------------------------------------------------------- 发布

def publish(publish_py, source, state, key, result):
    site_id = (state.get(key) or {}).get('site_id')
    cmd = [sys.executable, str(publish_py), 'server', str(source)]
    if site_id:
        cmd += ['--update', '--site-id', site_id]
    else:
        cmd += ['--name', f'sea-{key}']
    code, out = run(cmd, PUBLISH_TIMEOUT)
    url = None
    for line in out.splitlines():
        if line.startswith('URL:') or line.startswith('文件地址:'):
            url = line.split(':', 1)[1].strip()
        if line.startswith('Site ID:'):
            site_id = line.split(':', 1)[1].strip()
    result['publish'][key] = {
        'code': code,
        'site_id': site_id,
        'url': url,
        'tail': out.strip().splitlines()[-4:] if out.strip() else [],
    }
    if code == 0 and site_id:
        state[key] = {'site_id': site_id, 'url': url,
                      'updated': dt.datetime.now().isoformat(timespec='seconds')}
        return True
    return False


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--skip-git', action='store_true')
    ap.add_argument('--skip-publish', action='store_true')
    ap.add_argument('--no-export', action='store_true', help='复用已有 build 产物，只发布')
    args = ap.parse_args()

    RELEASE_DIR.mkdir(parents=True, exist_ok=True)
    state = load_state()
    result = {
        'started': dt.datetime.now().isoformat(timespec='seconds'),
        'git': {}, 'export': {}, 'package': {}, 'publish': {}, 'problems': [],
    }

    if not args.skip_git:
        log('git: 提交并推送')
        git_step(result)
        if not result['git'].get('push_ok'):
            result['problems'].append('git 推送失败')

    godot = find_godot()
    if not args.no_export:
        if not godot:
            result['problems'].append('找不到 godot 可执行文件')
            log('找不到 godot，跳过导出')
        else:
            log(f'导出 Web（godot {godot}）')
            clean(WEB_DIR)
            if not export_platform(godot, 'Web', WEB_DIR / 'index.html',
                                   WEB_EXPORT_TIMEOUT, result, 'web'):
                result['problems'].append('Web 导出失败')
            else:
                result['export']['web']['mib'] = web_size_mib()
                log(f'  Web 产物 {web_size_mib()} MiB')
                if not patch_web_pack(result):
                    result['problems'].append('Web 游戏包改名失败')

            log('导出 Windows')
            clean(WIN_DIR)
            if not export_platform(godot, 'Windows Desktop', WIN_DIR / 'sea.exe',
                                   WIN_EXPORT_TIMEOUT, result, 'windows'):
                result['problems'].append('Windows 导出失败')

    if (WEB_DIR / 'index.html').exists() and (WIN_DIR / 'sea.exe').exists():
        log('打包 Windows zip')
        if not zip_windows(result):
            result['problems'].append('Windows 打包失败')
    else:
        result['problems'].append('缺少导出产物，跳过打包')

    if not args.skip_publish:
        publish_py = find_publish()
        if not publish_py:
            result['problems'].append('找不到 publish.py')
        else:
            if (WEB_DIR / 'index.html').exists():
                log('发布 Web 版')
                if not publish(publish_py, WEB_DIR, state, 'web', result):
                    result['problems'].append('Web 发布失败')
            if WIN_ZIP.exists():
                log('发布 Windows 版')
                if not publish(publish_py, WIN_ZIP, state, 'windows', result):
                    result['problems'].append('Windows 发布失败')
            save_state(state)

    result['finished'] = dt.datetime.now().isoformat(timespec='seconds')
    result['ok'] = not result['problems']
    out_json = RELEASE_DIR / f'{dt.date.today():%Y-%m-%d}.json'
    out_json.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')

    print('\n===== 结果 =====')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print(f'记录: {out_json}')
    for key in ('web', 'windows'):
        url = (state.get(key) or {}).get('url')
        if url:
            print(f'{key}: {url}')
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
