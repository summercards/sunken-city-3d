#!/usr/bin/env python3
"""把 UI 里直接 new SystemFont 的地方改成走 UiFont 工厂（Web 端用内置中文字体）。"""
import re, pathlib, sys

ROOT = pathlib.Path("/Users/summercards/WorkBuddy/sea/godot")
CONST_LINE = 'const UiFontLib = preload("res://src/ui/ui_font.gd")'

FILES = ["src/ui/hud.gd", "src/interaction/interact_prompt.gd", "src/salvage/salvage_panel.gd",
         "src/orders/order_panel.gd", "src/camera/camera_panel.gd", "src/rendering/color_grade_panel.gd",
         "src/inventory/backpack_grid.gd", "src/interaction/hover_card.gd"]

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
