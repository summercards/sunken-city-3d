#!/usr/bin/env python3
"""把 UI 里直接 new SystemFont 的地方改成走 UiFont 工厂（Web 端用内置中文字体）。"""
import re, pathlib, sys

ROOT = pathlib.Path("/Users/summercards/WorkBuddy/sea/godot")
CONST_LINE = 'const UiFontLib = preload("res://scripts/ui/ui_font.gd")'

FILES = ["scripts/hud.gd", "scripts/ui/interact_prompt.gd", "scripts/ui/salvage_panel.gd",
         "scripts/ui/order_panel.gd", "scripts/ui/camera_panel.gd", "scripts/ui/color_grade_panel.gd",
         "scripts/ui/backpack_grid.gd", "scripts/ui/hover_card.gd"]

pat = re.compile(
    r'(?P<indent>\t*)_font = SystemFont\.new\(\)\n'
    r'\s*_font\.font_names = PackedStringArray\((?P<names>\[[^\]]*\])\)',
    re.S)

for rel in FILES:
    p = ROOT / rel
    src = p.read_text(encoding="utf-8")
    orig = src
    src = src.replace("var _font: SystemFont", "var _font: Font")
    src = src.replace("func setup(font: SystemFont,", "func setup(font: Font,")

    def rep(m):
        return f"{m.group('indent')}_font = UiFontLib.make(PackedStringArray({m.group('names')}))"

    src, n = pat.subn(rep, src)
    if n == 0 and "SystemFont.new()" in src:
        print(f"!! {rel} 未匹配到创建块")
    if "UiFontLib" in src and CONST_LINE not in src:
        # 插到第一个 const 之前，没有 const 就插到 extends/## 注释之后
        lines = src.split("\n")
        idx = next((i for i, l in enumerate(lines) if l.startswith("const ")), None)
        if idx is None:
            idx = next((i for i, l in enumerate(lines) if l.startswith("var ")), None)
        if idx is None:
            idx = next(i for i, l in enumerate(lines) if l.startswith("func "))
            lines.insert(idx, CONST_LINE + "\n")
        else:
            lines.insert(idx, CONST_LINE)
        src = "\n".join(lines)
        if not src.endswith("\n"):
            src += "\n"
    if src != orig:
        p.write_text(src, encoding="utf-8")
        print(f"ok {rel} (blocks={n})")
    else:
        print(f"skip {rel}")
