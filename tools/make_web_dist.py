#!/usr/bin/env python3
"""把 Godot 的 Web 导出目录打成可发布的静态站点。

为什么需要这一步：内网发布的白名单里没有 .pck，但 Godot 的 web 引擎默认按
`${executable}.pck` 取包。引擎支持 `mainPack` 配置项，所以把包改名成 .bin
（在白名单内）再在 index.html 的 GODOT_CONFIG 里显式指定即可。
"""
import json
import pathlib
import re
import shutil
import sys

SRC = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/Users/summercards/WorkBuddy/sea/godot/build/web")
DST = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "/Users/summercards/WorkBuddy/sea/godot/build/upload")

if not (SRC / "index.html").exists():
    raise SystemExit(f"{SRC}/index.html 不存在，先跑 --export-release")

if DST.exists():
    shutil.rmtree(DST)
shutil.copytree(SRC, DST, ignore=shutil.ignore_patterns("*.import", "*.uid"))

pck = DST / "index.pck"
if pck.exists():
    pck.rename(DST / "index.bin")

html = (DST / "index.html").read_text(encoding="utf-8")
m = re.search(r"const GODOT_CONFIG = (\{.*?\});", html, re.S)
if not m:
    raise SystemExit("找不到 GODOT_CONFIG")
cfg = json.loads(m.group(1))
cfg["mainPack"] = "index.bin"
sizes = {}
for k, v in (cfg.get("fileSizes") or {}).items():
    sizes["index.bin" if k.endswith(".pck") else k] = v
cfg["fileSizes"] = sizes
html = html[:m.start(1)] + json.dumps(cfg, ensure_ascii=False, separators=(",", ":")) + html[m.end(1):]
(DST / "index.html").write_text(html, encoding="utf-8")

# PWA 的 service worker 里把 index.pck 写死了（CACHEABLE_FILES），跟着改名，
# 否则刷新仍会整包重下 195MB。
sw = DST / "index.service.worker.js"
if sw.exists():
    sw.write_text(sw.read_text(encoding="utf-8").replace("index.pck", "index.bin"), encoding="utf-8")

total = sum(f.stat().st_size for f in DST.iterdir() if f.is_file())
print(f"ok -> {DST}  files={len(list(DST.iterdir()))}  total={total/1e6:.1f}MB")
for f in sorted(DST.iterdir()):
    print(f"  {f.name:32s} {f.stat().st_size/1e6:8.2f}MB")
