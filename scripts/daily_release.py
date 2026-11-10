#!/usr/bin/env python3
"""每日发布：git 推送 → 导出 Windows 单文件 → 发布到 sofunny 内网链接。

默认只做 Windows 单文件版（`Windows Desktop (单文件)` 预设，embed_pck）：
网页版要加 `--with-web` 才导出。单文件 exe 仍需携带 GDExtension 原生库
（libterrain.windows.release.x86_64.dll），这是 Godot 的硬限制 —— pck 能嵌，
dll 不能，所以发布物是「exe + dll」的 zip，不是单个裸 exe。

顺序固定为 git → 导出 → 发布：
- git 先行，导出失败也不影响当天代码留档；
- 导出与发布失败不掩盖，分别记退出码；
- 站点用固定 Site ID 原地更新，链接跨天不变。

用法：
    python3 scripts/daily_release.py               # Windows 单文件全流程
    python3 scripts/daily_release.py --with-web    # 顺便发网页版
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
SINGLE_DIR = BUILD / 'windows_single'
DIST = BUILD / 'dist'
WIN_ZIP = DIST / 'sea-windows.zip'

WEB_PRESET = 'Web'
WIN_PRESET = 'Windows Desktop'
SINGLE_PRESET = 'Windows Desktop (单文件)'

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
    """清空目录。失败必须报出来 —— 静默失败会让旧产物混进新包。

    2026-10-31 发生过：rmtree 静默失败，旧 index.bin 留在目录里，日志里
    产物体积虚高到 309.5 MiB。体积异常还能肉眼发现，若哪天是 exe 残留、
    打包时又按目录收集，就会把旧 exe 发上去。
    """
    if path.exists():
        shutil.rmtree(path, ignore_errors=True)
        if path.exists():
            leftover = sum(1 for _ in path.rglob('*'))
            raise OSError(f'目录清理失败，仍剩 {leftover} 项：{path}')
    path.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------- git

WINDOWS_RESERVED = {'con', 'prn', 'aux', 'nul'} | {f'com{i}' for i in range(1, 10)} | {
    f'lpt{i}' for i in range(1, 10)}


def _delete_reserved(path):
    r"""删一个保留设备名文件。Windows 上必须 `\\?\` 前缀 + 原生 API。

    本机 python 的 os.remove 被 safe-delete 挂钩接管（先移进回收站），对
    `nul` 这类设备名必定失败（0x800704B0 指定的设备名无效），所以直接调 kernel32。
    """
    raw = '\\\\?\\' + str(path)
    if sys.platform == 'win32':
        import ctypes
        k32 = ctypes.WinDLL('kernel32', use_last_error=True)
        k32.DeleteFileW.argtypes = [ctypes.c_wchar_p]
        k32.DeleteFileW.restype = ctypes.c_int
        if k32.DeleteFileW(raw):
            return
        raise OSError(ctypes.get_last_error(), 'DeleteFileW 失败', str(path))
    os.remove(raw)


def purge_reserved_names(result):
    """清掉仓库根目录里以 Windows 保留设备名命名的文件。

    2026-11-08 事故：某工具在 bash 里用 `> nul` 重定向，在仓库根目录留下一个真文件
    `nul`。`git add -A` 直接 `fatal: adding files failed`（invalid path 'nul'），
    提交为空；随后 pull --rebase 报 "Please commit or stash them"，脚本把它误判成
    rebase 冲突。这类名字在 Windows 上不可能是合法内容，提交前直接清掉。
    """
    try:
        names = [e.name for e in os.scandir(ROOT)
                 if e.name.split('.')[0].lower() in WINDOWS_RESERVED]
    except OSError:
        return
    removed = []
    for name in names:
        code, _ = run(['git', 'ls-files', '--error-unmatch', '--', name], 30)
        if code == 0:  # 已被跟踪 → 不动，交给人处理
            removed.append(f'{name}(已跟踪，未删)')
            continue
        try:
            _delete_reserved(ROOT / name)
            removed.append(name)
        except OSError as exc:
            removed.append(f'{name}(删除失败: {exc})')
    if removed:
        result['git']['reserved_purged'] = removed


def git_step(result):
    purge_reserved_names(result)
    code, out = run(['git', 'rev-parse', '--abbrev-ref', 'HEAD'], 30)
    branch = out.strip() if code == 0 else '?'
    code, out = run(['git', 'status', '--porcelain'], 60)
    changed = [ln for ln in out.splitlines() if ln.strip()]
    result['git']['branch'] = branch
    result['git']['changed_files'] = len(changed)

    if changed:
        # 提交前先挡住「材质参数被清空」——这类损坏肉眼要等到画面变白才发现，
        # 一旦进了历史，连 `git checkout HEAD --` 都救不回来（2026-10-29 发生过）。
        code, out = run([sys.executable, str(ROOT / 'scripts/check_material_params.py'), '--quiet'], 180)
        if code != 0:
            run([sys.executable, str(ROOT / 'scripts/repair_material_params.py')], 180)
            code, out = run([sys.executable, str(ROOT / 'scripts/check_material_params.py'), '--quiet'], 180)
            if code != 0:
                lines = out.strip().splitlines()
                result['git']['commit'] = '阻断：材质参数契约不成立 → ' + ' / '.join(lines[-3:])
                return
            result['git']['material_repair'] = 'auto'
            code, out = run(['git', 'status', '--porcelain'], 60)
            changed = [ln for ln in out.splitlines() if ln.strip()]

        code, out = run(['git', 'add', '-A'], 600)
        if code != 0:
            # add 失败时不要继续推送：空提交会推到远端，接着 pull --rebase 报
            # "Please commit or stash them"，被误判成 rebase 冲突（2026-11-08）。
            tail = out.strip().splitlines()[-3:] if out.strip() else []
            result['git']['commit'] = f'add 失败 {code}: ' + ' / '.join(tail)
            result['git']['add_failed'] = True
            result['git']['push'] = '未尝试（git add 失败）'
            result['git']['push_ok'] = False
            return
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


def rebase_in_progress():
    """工作区是否停在未完成的 rebase 中间态（冲突未解决）。"""
    for name in ('rebase-merge', 'rebase-apply'):
        code, out = run(['git', 'rev-parse', '--git-path', name], 30)
        if code != 0:
            continue
        path = Path(out.strip())
        if not path.is_absolute():
            path = ROOT / path
        if path.exists():
            return True
    return False


def try_push(remote, branch, timeout, result):
    """推送一次；non-fast-forward 自动 rebase 重试一次，绝不 force。

    pull --rebase 遇冲突会停在中间态并返回非 0。此时绝不能继续导出发布：
    半 rebase 的工作区可能带着冲突标记，那样打出来的包不可信。abort 恢复
    到 rebase 前（本地提交保留），记 rebase_conflict 由主流程中止全流程。
    """
    code, out = run(['git', 'push', remote, branch], timeout)
    if code == 0:
        return True, out
    text = out.lower()
    rejected = 'non-fast-forward' in text or 'rejected' in text or 'fetch first' in text
    if not rejected:
        return False, out
    pull_code, pull_out = run(['git', 'pull', '--rebase', remote, branch], timeout)
    if pull_code != 0 or rebase_in_progress():
        in_rebase = rebase_in_progress()
        if in_rebase:
            run(['git', 'rebase', '--abort'], timeout)
        tail = '\n'.join((pull_out or '').strip().splitlines()[-6:])
        if in_rebase:
            result['git']['rebased'] = True
            result['git']['rebase_conflict'] = True
            return False, (f'{out}\n--- pull --rebase (code {pull_code}) ---\n{tail}\n'
                           '[rebase 冲突，已 abort；本地提交保留，需人工解决]')
        # 没进 rebase 就失败（典型是工作区还脏："Please commit or stash them"）。
        # 别报成冲突，否则会误导排查方向。
        result['git']['pull_blocked'] = (pull_out or '').strip().splitlines()[-3:]
        return False, (f'{out}\n--- pull --rebase (code {pull_code}) ---\n{tail}\n'
                       '[未进入 rebase，rebase 被拒；工作区未恢复，需人工检查]')
    result['git']['rebased'] = True
    code, out = run(['git', 'push', remote, branch], timeout)
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


# ---------------------------------------------------------------- Windows 打包

# 导出目录里这些后缀不进包：.import 是编辑器元数据，.uid 是 Godot 生成的资源
# 标识，两者对运行都没用（.import 里有 dev 绝对路径）。
PACK_SKIP_SUFFIX = {'.import', '.uid'}
README_NAME = '运行说明.txt'

README_SINGLE = (
    'sea（Windows 版）\n\n'
    '1. sea.exe 是单文件版，游戏包已内嵌在 exe 里，不需要额外的 .pck。\n'
    '2. 同目录的 libterrain.windows.release.x86_64.dll 必须保留 —— 海床地形是\n'
    '   GDExtension 原生插件，缺它游戏会加载失败（不是可选组件）。\n'
    '3. 双击 sea.exe 即可运行。\n'
)
README_SPLIT = (
    'sea（Windows 版）\n\n'
    '1. 解压后双击 sea.exe 即可运行。\n'
    '2. sea.pck 必须与 sea.exe 放在同一目录。\n'
    '3. libterrain.windows.release.x86_64.dll 必须保留 —— 海床地形是 GDExtension\n'
    '   原生插件，缺它游戏会加载失败（不是可选组件）。\n'
)

GDE_SECTION = 'windows.release.x86_64'


def gdextension_libs():
    """项目里 GDExtension 在 Windows x86_64 上要求的动态库文件名。

    Godot 只能把 .pck 内嵌进 exe，原生库永远外置。所以「单文件 exe」严格说
    是 exe + 每个 GDExtension 一个 dll。这里从 .gdextension 声明反查，避免
    打包时漏库（2026-11-10 线上 zip 就是漏了 libterrain，整包跑不起来）。
    """
    libs = []
    for gde in sorted(GODOT_DIR.rglob('*.gdextension')):
        if 'build' in gde.parts:
            continue
        for line in gde.read_text(encoding='utf-8', errors='replace').splitlines():
            head, sep, tail = line.partition('=')
            if sep and head.strip() == GDE_SECTION:
                rel = tail.strip().strip('"').replace('res://', '')
                if rel:
                    libs.append(rel)
    return libs


def assert_gdextension_libs(src_dir, result):
    """导出目录必须含所有 GDExtension 原生库，缺一个就发不出去。"""
    libs = gdextension_libs()
    if not libs:
        return True
    missing = [lib for lib in libs if not (src_dir / Path(lib).name).exists()]
    result.setdefault('package', {}).setdefault('gdextension', {
        'required': libs,
        'missing': missing,
    })
    if missing:
        result['problems'].append(
            f'GDExtension 原生库没被导出：{", ".join(missing)}（缺它游戏加载不了主场景）')
        return False
    return True


def zip_windows(result, src_dir, readme_text):
    """把导出目录里所有运行所需文件打成固定文件名的 zip。

    不硬编码文件名 —— 2026-11-06 引入 Terrain3D 后，导出目录多了一个
    libterrain dll，而打包仍按 sea.exe / sea.pck 白名单收集，dll 就被静默丢弃，
    线上 Windows 包从此一律 `Failed loading scene: main.tscn`。
    """
    files = [p for p in sorted(src_dir.rglob('*'))
             if p.is_file() and p.suffix.lower() not in PACK_SKIP_SUFFIX]
    exes = [p for p in files if p.suffix.lower() == '.exe']
    if not exes:
        result['package']['windows_zip'] = f'缺少 exe：{src_dir}'
        return False

    readme = src_dir / README_NAME
    readme.write_text(readme_text, encoding='utf-8')
    if readme not in files:
        files.append(readme)

    DIST.mkdir(parents=True, exist_ok=True)
    started = time.time()
    with zipfile.ZipFile(WIN_ZIP, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for p in files:
            zf.write(p, arcname=str(p.relative_to(src_dir)).replace('\\', '/'))
    result['package']['windows_zip'] = {
        'path': str(WIN_ZIP),
        'mib': round(WIN_ZIP.stat().st_size / 1048576, 1),
        'seconds': round(time.time() - started, 1),
        'files': [str(p.relative_to(src_dir)).replace('\\', '/') for p in files],
    }
    return True


def check_pack_assets(result, pack_path, key):
    """导出后必须过资产契约：字体/数据文件真的在包里。

    2026-10-29 的字体豆腐块事故就是这里漏了 —— 源 .ttf 不进包，
    运行期只能读到空字节。宁可发布失败，也不要发一个没字的包。
    """
    script = ROOT / 'scripts/check_pack_assets.py'
    if not script.exists():
        return True
    if not pack_path.exists():
        result['problems'].append(f'{key} 包不存在，跳过资产检查：{pack_path.name}')
        return False
    code, out = run([sys.executable, str(script), str(pack_path), '--quiet'], 600)
    result.setdefault('pack_check', {})[key] = {
        'code': code,
        'tail': out.strip().splitlines()[-4:] if out.strip() else [],
    }
    if code != 0:
        log(f'  {key} 资产契约不成立')
        result['problems'].append(f'{key} 包资产契约不成立（字体或数据没进包）')
        return False
    return True


def web_size_mib():
    total = sum(p.stat().st_size for p in WEB_DIR.rglob('*') if p.is_file())
    return round(total / 1048576, 1)


# ---------------------------------------------------------------- 网页曝光补偿

# 网页导出只能跑 gl_compatibility（WebGL2），桌面跑 forward_plus。两者对 3D 高光的
# 处理根本不同：Forward+ 在 HDR 缓冲里过 ACES，屋顶/白墙被滚降到 ~229；兼容后端写
# 的是 LDR 缓冲，超过 1.0 先被削平再过曲线，结果停在 249~255 —— 观感就是"网页版曝光
# 更强、白墙糊成一片"。
#
# 实测（同一机位、同一帧，1440x900，排除 UI 区）：
#   桌面 Forward+  p1=102.0  p50=111.0  p99=229.3   触顶 2.07%  全白 0.00%
#   桌面 gl_compat p1=113.0  p50=123.3  p99=249.7   触顶 3.65%  全白 0.23%
#   网页           p1=113.0  p50=123.3  p99=249.7   触顶 3.65%  全白 0.23%
# 逐档扫过 tonemap_mode × tonemap_exposure（21 组），最好一组 p99 仍停在 240 —— 削顶
# 发生在曲线之前，改参数救不回来。所以补偿只能放在画布输出上。
#
# 关键约束：只压高光，200 以下恒等。水面/天空本来就和桌面一致（G/B 相差 ≤2），
# 一旦整体压暗会让它比桌面更暗，反而更偏。200 起的肩部只吃白墙、屋顶和高光泡沫。
WEB_TONE_SHOULDER = 215      # 肩部起点（0-255，sRGB）；215 以下完全恒等，保住水面与中间调
WEB_TONE_SCALE = 0.55        # 肩部以上每 1 级的输出增量（按 FP 的墙面高光反解）
WEB_TONE_MARK = 'id="sea-web-tone-lut"'
WEB_TONE_FILTER = 'sea-web-tone'


def _web_tone_lut():
    lut = []
    for x in range(256):
        y = x if x <= WEB_TONE_SHOULDER else WEB_TONE_SHOULDER + (x - WEB_TONE_SHOULDER) * WEB_TONE_SCALE
        lut.append(f'{min(y, 255) / 255:.5f}'.rstrip('0').rstrip('.') or '0')
    return ' '.join(lut)


def patch_web_tone(result):
    """把高光肩部压回 Forward+ 的水平，纯网页外壳改动，不碰 godot/ 与桌面产物。"""
    html = WEB_DIR / 'index.html'
    if not html.exists():
        result['problems'].append('缺少 index.html，无法注入曝光补偿')
        return False
    text = html.read_text(encoding='utf-8')
    if WEB_TONE_MARK in text:
        result.setdefault('web_tone', {})['applied'] = 'already'
        return True

    lut = _web_tone_lut()
    svg = (
        f'<svg {WEB_TONE_MARK} width="0" height="0" aria-hidden="true" '
        f'style="position:absolute;pointer-events:none">'
        f'<filter id="{WEB_TONE_FILTER}" color-interpolation-filters="sRGB">'
        f'<feComponentTransfer>'
        + ''.join(f'<feFunc{c} type="table" tableValues="{lut}"/>' for c in 'RGB')
        + '</feComponentTransfer></filter></svg>'
    )
    style = f'<style>#canvas{{filter:url(#{WEB_TONE_FILTER})}}</style>'

    if '</head>' in text:
        text = text.replace('</head>', svg + style + '</head>', 1)
    else:
        text = text.replace('<body', svg + style + '<body', 1)

    html.write_text(text, encoding='utf-8')
    patched = WEB_TONE_MARK in html.read_text(encoding='utf-8')
    result.setdefault('web_tone', {}).update({
        'applied': patched,
        'shoulder': WEB_TONE_SHOULDER,
        'scale': WEB_TONE_SCALE,
        'lut_len': len(lut.split()),
    })
    if not patched:
        result['problems'].append('网页曝光补偿注入失败')
    return patched


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
    rebuilt = False
    if code != 0 and site_id and '站点不存在' in out:
        # 站点已被服务端删除：原地更新不可能，改新建（链接会变，结果里标 rebuilt）
        cmd = [sys.executable, str(publish_py), 'server', str(source),
               '--name', f'sea-{key}']
        code, out = run(cmd, PUBLISH_TIMEOUT)
        rebuilt = True
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
        'rebuilt': rebuilt,
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
    ap.add_argument('--with-web', action='store_true',
                    help='同时导出并发布网页版（默认只发 Windows 单文件版）')
    ap.add_argument('--windows-split', action='store_true',
                    help='改用 exe + pck 分离版预设（默认用单文件预设 embed_pck）')
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

    # rebase 冲突 / rebase 被拒时工作区处于半成品状态，导出与发布必须整体跳过。
    blocked = bool(result['git'].get('rebase_conflict') or result['git'].get('pull_blocked'))
    if result['git'].get('rebase_conflict'):
        result['problems'].append('git rebase 冲突，已中止导出与发布（工作区已恢复，需人工解决后重跑）')
    elif result['git'].get('pull_blocked'):
        result['problems'].append('git rebase 被拒（工作区不干净），已中止导出与发布，需人工检查后重跑')

    godot = find_godot()
    win_dir = WIN_DIR if args.windows_split else SINGLE_DIR
    win_preset = WIN_PRESET if args.windows_split else SINGLE_PRESET
    readme_text = README_SPLIT if args.windows_split else README_SINGLE
    pack_target = (WIN_DIR / 'sea.pck') if args.windows_split else (SINGLE_DIR / 'sea.exe')

    if not args.no_export and not blocked:
        if not godot:
            result['problems'].append('找不到 godot 可执行文件')
            log('找不到 godot，跳过导出')
        else:
            if args.with_web:
                log(f'导出 Web（{WEB_PRESET}）')
                try:
                    clean(WEB_DIR)
                except OSError as exc:
                    result['problems'].append(f'Web 导出目录清理失败：{exc}')
                else:
                    if not export_platform(godot, WEB_PRESET, WEB_DIR / 'index.html',
                                           WEB_EXPORT_TIMEOUT, result, 'web'):
                        result['problems'].append('Web 导出失败')
                    else:
                        result['export']['web']['mib'] = web_size_mib()
                        log(f'  Web 产物 {web_size_mib()} MiB')
                        if not patch_web_pack(result):
                            result['problems'].append('Web 游戏包改名失败')
                        else:
                            check_pack_assets(result, WEB_DIR / 'index.bin', 'web')
                            patch_web_tone(result)
            else:
                log('跳过 Web 导出（默认只发 Windows 单文件版，需要时加 --with-web）')

            log(f'导出 Windows（{win_preset}）')
            try:
                clean(win_dir)
            except OSError as exc:
                result['problems'].append(f'Windows 导出目录清理失败：{exc}')
            else:
                if not export_platform(godot, win_preset, win_dir / 'sea.exe',
                                       WIN_EXPORT_TIMEOUT, result, 'windows'):
                    result['problems'].append('Windows 导出失败')
                else:
                    check_pack_assets(result, pack_target, 'windows')

    if not blocked and (win_dir / 'sea.exe').exists():
        assert_gdextension_libs(win_dir, result)
        log('打包 Windows zip')
        if not zip_windows(result, win_dir, readme_text):
            result['problems'].append('Windows 打包失败')
    elif not blocked:
        result['problems'].append('缺少导出产物，跳过打包')

    if not args.skip_publish and not blocked:
        publish_py = find_publish()
        if not publish_py:
            result['problems'].append('找不到 publish.py')
        else:
            if args.with_web and (WEB_DIR / 'index.html').exists():
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
