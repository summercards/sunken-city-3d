#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验 sea 风格化形体语言：零方正（references/stylized-form-grammar.md）。

核心只有一条：任何有体量的构件，上下必须不对称。ρ=0 判失败，
没有"默认方正"的件，没有整体豁免。

用法：
  python check_stylized_form.py --plan art_source/scenes/<套件>/v###/component_plan.json
  python check_stylized_form.py --selftest

退出码：0 通过；1 有超限；2 参数/文件问题。
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC_PATH = HERE.parent / "references" / "stylized_form_variants.json"

EPS = 1e-9

# 靠倾斜出效果的挂件族（tilt_coverage 的分母）
HANGER_KINDS = {
    "sign", "blade_sign", "menu", "poster", "notice",
    "canopy", "awning", "roof_sheet",
    "carton", "bin", "stool", "planter", "planter_trough",
    "flat_attached", "leaning_panel", "box_lid",
}

# 结构族：同栋必须同符号
STRUCTURE_KINDS = {"shell", "vertical_structure"}


class Result:
    def __init__(self) -> None:
        self.fail: list[tuple[str, str]] = []
        self.notes: list[str] = []
        self.skipped: list[str] = []

    def ok(self, code: str, label: str, detail: str) -> None:
        self.notes.append(f"OK   [{code}] {label}: {detail}")

    def bad(self, code: str, label: str, detail: str) -> None:
        self.fail.append((code, f"FAIL [{code}] {label}: {detail}"))

    def check(self, cond: bool, code: str, label: str, detail: str) -> bool:
        if cond:
            self.ok(code, label, detail)
        else:
            self.bad(code, label, detail)
        return cond

    def info(self, text: str) -> None:
        self.notes.append("     " + text)

    def skip(self, text: str) -> None:
        self.skipped.append("- " + text)


def load_spec() -> dict:
    with SPEC_PATH.open(encoding="utf-8") as fh:
        return json.load(fh)


def rho_of(bottom, top):
    if bottom in (None, 0) or top is None:
        return None
    return 1.0 - float(top) / float(bottom)


def f(x, n=3):
    return f"{x:.{n}f}"


# --------------------------------------------------------------------------
# 扁平件 / 细长体的变形轴推导（第 3.1 节）
# --------------------------------------------------------------------------
def longest_axis(extent):
    """锥度必须沿最长轴渐变，改变的是垂直于它的截面尺寸。

    这样绝对改变量落在截面（短边）上、分摊在最长轴上，角度最小：
    9.09×2.28 的招牌，2% 落在 2.28 上只有 4.6cm，摊在 9.09 米上是 0.29° —— 看不出来但不再是方块；
    若反过来在 9.09 上收 18cm 摊在 2.28 米上，就是 4.5° 的歪梯形，一眼假。
    """
    pairs = list(zip(extent, "xyz"))
    vmax, amax = max(pairs)
    if vmax <= 0:
        return None, None
    cross = sorted([(v, a) for v, a in pairs if a != amax], reverse=True)
    return amax, (cross[0][1] if cross else None)


# --------------------------------------------------------------------------
# 接缝：不许面贴面，不许穿模（第 5.1 节）
# --------------------------------------------------------------------------
CONTACT_OK = {"inset", "clearance", "boolean_cut", "miter"}
CONTACT_FORBIDDEN = {
    "coplanar": "两个面共面 → 深度冲突，着色会闪",
    "face_to_face": "面贴面 → 同上，且拆件时会互相切到",
    "interpenetrate": "互相穿过 → 接缝处永远有一条假的交界线",
    "overlap": "重叠 → 同上",
    "flush": "齐平 → 没有缝也没有槽，读作两块板叠在一起",
}
GAP_MIN = 0.002
GAP_MAX = 0.020


def check_contacts(spec: dict, block: dict, res: Result) -> None:
    contacts = block.get("contacts")
    comps = block.get("components") or []

    # 声明了附着关系的件必须有接缝记录
    attached = [c.get("id", "?") for c in comps if c.get("attached_to")]
    by_pair = set()
    if contacts:
        for ct in contacts:
            by_pair.add(ct.get("a"))
            by_pair.add(ct.get("b"))
    missing = [cid for cid in attached if cid not in by_pair]
    if attached:
        res.check(not missing, "contact_declared", "附着件接缝记录",
                  f"{len(attached) - len(missing)}/{len(attached)} 件有记录"
                  + ("" if not missing else
                     f" → 缺 {missing}；附着件必须写清是开槽、留缝还是布尔开洞"))

    if not contacts:
        res.skip("接缝：没有 contacts 块（本资产未声明接缝关系）")
        return

    for ct in contacts:
        a, b = ct.get("a", "?"), ct.get("b", "?")
        rel = str(ct.get("relation", "")).lower()
        tag = f"{a} ↔ {b}"
        if rel in CONTACT_FORBIDDEN:
            res.bad("no_overlap", tag,
                    f"relation={rel} → {CONTACT_FORBIDDEN[rel]}")
            continue
        if rel not in CONTACT_OK:
            res.bad("no_overlap", tag,
                    f"relation='{rel}' 未登记；只允许 "
                    f"{'、'.join(sorted(CONTACT_OK))}")
            continue

        if rel == "boolean_cut":
            ok = bool(ct.get("cut_verified"))
            res.check(ok, "boolean_cut_verified", tag,
                      "布尔开洞已核验（无残留内部面）" if ok else
                      "布尔开洞必须写 cut_verified: true，并确认洞里没有残留面")
            continue

        gap = ct.get("gap_m")
        if gap is None:
            res.bad("no_overlap", tag,
                    f"relation={rel} 必须给 gap_m（{GAP_MIN*1000:.0f}–"
                    f"{GAP_MAX*1000:.0f}mm）")
            continue
        gap = float(gap)
        ok = GAP_MIN - EPS <= gap <= GAP_MAX + EPS
        res.check(ok, "no_overlap", tag,
                  f"{rel}，gap {gap*1000:.1f}mm ∈ [{GAP_MIN*1000:.0f}, "
                  f"{GAP_MAX*1000:.0f}]mm"
                  + ("" if ok else
                     " → 小于 2mm 仍会共面闪；大于 20mm 要改成开槽或布尔"))


# --------------------------------------------------------------------------
# 主体
# --------------------------------------------------------------------------
def check_body(spec: dict, block: dict, res: Result) -> None:
    body = block.get("body") or {}
    lim = spec["limits"]
    if not body:
        res.skip("主体：没有 body 块")
        return

    rhos = {}
    for key in ("width", "depth"):
        r = rho_of(body.get(f"{key}_base"), body.get(f"{key}_top"))
        if r is not None:
            rhos[key] = r
    if not rhos:
        res.skip("主体：缺 width_*/depth_* 尺寸")
        return

    tapered = 0
    for key, r in rhos.items():
        ar = abs(r)
        if ar <= EPS:
            res.bad("no_square_volume", f"主体 {key}",
                    "ρ=0 → 方盒，主体至少一轴必须收")
        elif ar < lim["rho_abs_min"] - EPS:
            res.bad("no_square_volume", f"主体 {key}",
                    f"|ρ|={f(ar)} < {lim['rho_abs_min']:.2f} → 肉眼看不出，等于方盒")
        elif ar > lim["rho_abs_max"] + EPS:
            res.bad("rho_abs_max", f"主体 {key}",
                    f"|ρ|={f(ar)} > {lim['rho_abs_max']:.2f} → 成锥塔")
        else:
            res.ok("no_square_volume", f"主体 {key}",
                   f"|ρ|={f(ar)} ∈ [{lim['rho_abs_min']:.2f}, {lim['rho_abs_max']:.2f}]")
            tapered += 1

    res.check(tapered >= 1, "body_tapered", "主体收分轴数",
              f"{tapered} 轴 ≥ 1（主体至少一轴必须收）")
    res.info("主体读数 " + " / ".join(f"{k}={f(v)}" for k, v in rhos.items()))

    h, w = body.get("height"), body.get("width_base")
    if h and w and "width" in rhos and abs(rhos["width"]) > EPS:
        beta = math.degrees(math.atan(abs(rhos["width"]) * float(w) / float(h)))
        cap = math.tan(math.radians(lim["wall_tilt_max_deg"])) * float(h) / float(w)
        res.check(beta <= lim["wall_tilt_max_deg"] + EPS, "wall_tilt",
                  "墙面倾角", f"β={f(beta, 2)}° ≤ {lim['wall_tilt_max_deg']:.2f}°"
                  f"（本墙宽可用 ρ 上限 {f(cap)}）")

    if block.get("body_tilt_deg") not in (None, 0):
        res.bad("body_tilt_forbidden", "主体倾斜",
                f"γ={block['body_tilt_deg']}° → 墙壳/楼层体量属结构件，不许歪")


# --------------------------------------------------------------------------
# 组件：逐件零方正
# --------------------------------------------------------------------------
def check_components(spec: dict, block: dict, res: Result) -> None:
    comps = block.get("components") or []
    if not comps:
        res.skip("组件：没有 components 块")
        return

    lim = spec["limits"]
    fams = spec["families"]
    style = block.get("form_style", spec["defaults"]["form_style"])
    preset = spec["presets"].get(style, spec["presets"]["SF-B"])
    cyl_max = preset.get("cylinder_ratio_max", lim["cylinder_diameter_ratio_max"])
    tilt_lim = spec["tilt"]["by_kind"]
    forbidden = set(spec["tilt"]["structural_forbidden"])

    total = squares = 0
    structure_signs: dict[str, int] = {}
    pos = neg = 0
    hanger_total = tilted_hangers = 0

    for c in comps:
        cid = c.get("id", "?")
        kind = c.get("kind", "")
        if not kind:
            res.bad("missing_kind", f"组件 {cid}", "缺 kind，无法判断是否构成体量")
            continue
        if kind not in fams and kind != "no_volume":
            res.bad("unknown_kind", f"组件 {cid}",
                    f"kind='{kind}' 不在族表（{', '.join(fams)}, no_volume）")
            continue

        fam = fams.get(kind, {})

        # --- 植物与柔性件：豁免 ρ，但要人眼确认轮廓非矩形 ---
        if fam.get("rho_exempt"):
            res.info(f"豁免 {cid}（{kind}）：{fam.get('note', '不套刚体锥度')}")
            continue

        total += 1

        # --- 豁免件 ---
        if kind == "no_volume":
            res.check(bool(c.get("no_volume")), "no_volume_declared",
                      f"豁免件 {cid}",
                      "必须写 no_volume: true"
                      if not c.get("no_volume") else "已声明不构成体量")
            bev = c.get("bevel")
            res.check(bev is not None and float(bev) > 0, "micro_bevel",
                      f"豁免件 {cid}",
                      f"倒角 {bev}（要求 0.008–0.02）"
                      if bev else "豁免锥度但必须倒角")
            thick = c.get("thickness")
            if thick is not None:
                ok = float(thick) <= lim["no_volume_max_thickness"] + EPS
                res.check(ok, "no_volume_thickness", f"豁免件 {cid}",
                          f"厚 {f(float(thick))} ≤ {lim['no_volume_max_thickness']:.2f}"
                          + ("" if ok else " → 超过 0.02 就是体量，不能豁免"))
            continue

        # --- 线性构件：按径比 ---
        if kind == "linear":
            d0, d1 = c.get("d_bottom"), c.get("d_top")
            if d0 and d1:
                ratio = float(d1) / float(d0)
                ok = ratio <= cyl_max + EPS
                res.check(ok, "cylinder_taper", f"线性件 {cid}",
                          f"d_top/d_bottom = {f(ratio)} ≤ {f(cyl_max)}"
                          f"（ρ={f(1 - ratio)}）"
                          + ("" if ok else " → 这是直筒杆"))
                if ok and 1 - ratio > 0:
                    pos += 1
            else:
                res.bad("cylinder_taper", f"线性件 {cid}",
                        "缺 d_bottom/d_top，无法核变径")
            continue

        # --- 体量件 ---
        # 先核锥度方向：必须沿最长轴渐变，改变的是截面尺寸
        extent = c.get("extent")
        taper_along = c.get("taper_along")
        if extent is not None:
            if not (isinstance(extent, (list, tuple)) and len(extent) == 3):
                res.bad("taper_along_rule", f"体量件 {cid}",
                        f"extent 必须是 [x, y, z] 三个数，实得 {extent}")
            else:
                vals = [float(v) for v in extent]
                if min(vals) <= 0:
                    res.bad("taper_along_rule", f"体量件 {cid}", "extent 含 0 或负数")
                else:
                    want, cross = longest_axis(vals)
                    got = str(taper_along) if taper_along else "未声明"
                    idx_of = {"x": 0, "y": 1, "z": 2}
                    # 最长轴并列时任一都算对（正方形平面没有"长边"）
                    ok = (got in idx_of
                          and vals[idx_of[got]] >= max(vals) - 1e-9)
                    ratio = max(vals) / sorted(vals)[-2]
                    res.check(ok, "taper_along_rule", f"体量件 {cid} 锥度方向",
                              f"({f(vals[0],2)}, {f(vals[1],2)}, {f(vals[2],2)})"
                              f" 长宽比 {f(ratio, 2)} → 应沿 {want} 渐变、改截面 {cross}，"
                              f"实得 {got}"
                              + ("" if ok else
                                 "；在最长轴上收分会把两条长边拉成不平行，一眼是歪的"))
        elif taper_along:
            res.bad("taper_along_rule", f"体量件 {cid}",
                    "声明了 taper_along 但没给 extent，无法验证方向")

        r = rho_of(c.get("bottom"), c.get("top"))
        if r is None:
            res.bad("no_square_volume", f"体量件 {cid}", "缺 bottom/top，无法算 ρ")
            continue
        inside = lim["rho_abs_min"] - EPS <= abs(r) <= lim["rho_abs_max"] + EPS
        if not inside:
            squares += 1
            if abs(r) <= EPS:
                res.bad("no_square_volume", f"体量件 {cid}（{kind}）",
                        "ρ=0 → 方盒/直筒，必须做上下不对称")
            elif abs(r) < lim["rho_abs_min"] - EPS:
                res.bad("no_square_volume", f"体量件 {cid}（{kind}）",
                        f"|ρ|={f(abs(r))} < {lim['rho_abs_min']:.2f}"
                        " → 肉眼看不出，等于方盒")
            else:
                res.bad("rho_abs_max", f"体量件 {cid}（{kind}）",
                        f"|ρ|={f(abs(r))} > {lim['rho_abs_max']:.2f} → 成锥塔")
        else:
            if r > 0:
                pos += 1
            elif r < 0:
                neg += 1

        # --- 族符号规则 ---
        if fam.get("sign") == "negative":
            res.check(r < -lim["rho_abs_min"] + EPS, "sign_family",
                      f"独立体 {cid}",
                      f"应倒梯形，实测 ρ={f(r)}"
                      + ("" if r < 0 else " → 做成直筒或正锥，丢掉识别度"))
        if kind in STRUCTURE_KINDS or c.get("role") == "structure":
            key = "+" if r > 0 else "-" if r < 0 else "0"
            structure_signs[key] = structure_signs.get(key, 0) + 1

        # --- 倾斜 ---
        tilt = c.get("tilt_deg")
        tilt = abs(float(tilt)) if tilt is not None else None
        if kind in HANGER_KINDS or c.get("tilt_kind") in tilt_lim:
            hanger_total += 1
        if tilt is not None and tilt > EPS:
            key = c.get("tilt_kind") or kind
            band = tilt_lim.get(key)
            limit = max(lim["tilt_abs_max_deg"], band[1] if band else 0)
            res.check(tilt <= limit + EPS, "tilt", f"组件 {cid} 倾斜",
                      f"γ={f(tilt, 1)}° ≤ {f(limit, 1)}°"
                      + (f"（{key} 带 {band[0]}–{band[1]}°）" if band else ""))
            if kind in forbidden or c.get("id") in forbidden:
                res.bad("structural_tilt_forbidden", f"组件 {cid}",
                        "结构件不许倾斜")
            else:
                tilted_hangers += 1

    if total == 0:
        res.skip("组件：空清单")
        return

    # --- 结构族同向 ---
    if len(structure_signs) > 1:
        res.bad("sign_consistency", "结构族同向",
                "结构族出现多种符号 " + str(structure_signs)
                + " → 同栋墙柱必须同向，否则像随机歪")
    elif structure_signs:
        res.ok("sign_consistency", "结构族同向",
               "全部结构件符号一致 " + str(structure_signs))

    # --- 非结构族需正负共存 ---
    waiver = block.get("sign_mix_waived_reason")
    if waiver:
        res.info(f"正负共存豁免：{waiver}")
    else:
        res.check(neg > 0, "sign_mix", "倒梯形件",
                  f"{neg} 件 > 0" if neg else
                  "0 件 → 全栋都是上小下大，会变金字塔；"
                  "至少给一件倒梯形（花盆/桶/箱天然如此）")

    # --- 倾斜覆盖 ---
    min_tilt = max(lim["tilt_coverage_floor"],
                   math.ceil(hanger_total * lim["tilt_coverage_min"]))
    if hanger_total:
        res.check(tilted_hangers >= min_tilt, "tilt_coverage", "倾斜件数",
                  f"{tilted_hangers} 件 ≥ {min_tilt}（挂件 {hanger_total} 件的 "
                  f"{lim['tilt_coverage_min'] * 100:.0f}%）"
                  + ("" if tilted_hangers >= min_tilt else
                     " → 全楼没有一件歪着；招牌/篷/靠墙板正是靠倾斜出效果的"))
    else:
        res.skip("倾斜件数：该栋没有挂件")

    res.info(f"体量件 {total} 件，方正 {squares} 件，目标 0 件")
    res.check(squares == 0, "square_count", "方正件计数",
              f"{squares} 件 → {'零方正达成' if squares == 0 else '还有方盒没改'}")


# --------------------------------------------------------------------------
# 嵌入层次
# --------------------------------------------------------------------------
def check_relief(spec: dict, block: dict, res: Result) -> None:
    relief = block.get("relief") or {}
    rel = spec["relief"]
    t_wall = block.get("wall_thickness")
    emax = rel["protrusion_vs_wall_thickness_max"]

    for key, band in (("brick_protrusion", rel["brick"]["protrusion"]),
                      ("quoin_protrusion", rel["quoin"]["protrusion"])):
        e = relief.get(key)
        if e is None:
            continue
        e = float(e)
        if t_wall:
            limit = emax * float(t_wall)
            res.check(e <= limit + EPS, "relief_protrusion", key,
                      f"e={f(e)} ≤ 0.8×墙厚 = {f(limit)}")
        else:
            res.skip(f"{key}：缺 wall_thickness")
        res.check(band[0] - EPS <= e <= band[1] + EPS, "relief_band", key,
                  f"{f(e)} ∈ [{f(band[0])}, {f(band[1])}]")

    blocks = {k: int(relief.get(k, 0))
              for k in ("quoin_blocks", "brick_blocks", "grooves", "brackets")}
    total_blocks = sum(blocks.values())
    waived = block.get("relief_waived_reason")
    if waived:
        res.info(f"嵌入豁免：{waived}")
    else:
        res.check(total_blocks > 0, "relief_presence", "嵌入几何",
                  f"隅石 {blocks['quoin_blocks']} + 砖嵌 {blocks['brick_blocks']}"
                  f" + 凹槽 {blocks['grooves']} + 托架 {blocks['brackets']}"
                  f" = {total_blocks} > 0"
                  + ("" if total_blocks else
                     " → 只有参数没有几何，墙面还是平面；"
                     "不做要登记 relief_waived_reason"))

    layers = relief.get("layers")
    if layers is not None:
        ok = int(layers) <= rel["layer_max"]
        res.check(ok, "relief_layers", "嵌入层数",
                  f"{layers} ≤ {rel['layer_max']}")
        if total_blocks and int(layers) == 0:
            res.bad("relief_layers", "嵌入层数", "登记 0 层却给了块数，自相矛盾")


# --------------------------------------------------------------------------
# 面数
# --------------------------------------------------------------------------
def estimate_triangles(spec: dict, block: dict) -> tuple[int, dict]:
    cost = spec["triangle_cost"]
    relief = block.get("relief") or {}
    preset = spec["presets"].get(block.get("form_style", "SF-B"),
                                 spec["presets"]["SF-B"])
    n_quoin = int(relief.get("quoin_blocks", 0))
    if not n_quoin:
        n_quoin = 2 * int(preset["quoin_pairs"]) * int(block.get("corners", 4))
    n_bracket = int(relief.get("brackets", 0))
    if not n_bracket and block.get("cornice_length"):
        n_bracket = int(float(block["cornice_length"]) // preset["bracket_pitch"]) + 1
    parts = {
        "quoin": n_quoin,
        "bracket": n_bracket,
        "brick": int(relief.get("brick_blocks", 0)),
        "groove": int(relief.get("grooves", 0)),
        "brace": int(relief.get("braces", 0)),
        "patch": int(relief.get("patches", 0)),
    }
    total = (cost["beveled_cube_3seg"] * (parts["quoin"] + parts["bracket"] + parts["brick"])
             + cost["groove"] * parts["groove"]
             + cost["cylinder_12side_segment_with_caps"] * parts["brace"]
             + 8 * parts["patch"])
    return total, parts


def check_budget(spec: dict, block: dict, res: Result) -> None:
    body = block.get("body") or {}
    body_tri = body.get("triangles") or block.get("body_triangles")
    total, parts = estimate_triangles(spec, block)
    res.info("造型件 " + " + ".join(f"{k} {v}" for k, v in parts.items() if v)
             + f" = {total} tri")
    if not body_tri:
        res.skip("面数占比：缺 body.triangles")
        return
    ratio = total / float(body_tri)
    res.check(ratio <= spec["limits"]["form_extra_tri_vs_body_max"] + EPS,
              "tri_budget", "造型件面数占比",
              f"{total}/{body_tri} = {ratio * 100:.1f}% ≤ "
              f"{spec['limits']['form_extra_tri_vs_body_max'] * 100:.0f}%"
              "（锥度本身不花面数，别拿预算当不做锥度的理由）")


def evaluate(spec: dict, block: dict) -> Result:
    res = Result()
    style = block.get("form_style", spec["defaults"]["form_style"])
    res.info(f"档位 {style}（{spec['presets'][style]['label']}）"
             if style in spec["presets"] else f"档位 {style} 未登记")
    check_body(spec, block, res)
    check_components(spec, block, res)
    check_contacts(spec, block, res)
    check_relief(spec, block, res)
    check_budget(spec, block, res)
    return res


def report(res: Result, title: str) -> int:
    print(f"== {title} ==")
    for line in res.notes:
        print("  " + line)
    for line in res.skipped:
        print("  " + line)
    for _c, line in res.fail:
        print("  " + line)
    print(f"  结论：{len(res.fail)} 项超限，{len(res.skipped)} 项跳过")
    return 0 if not res.fail else 1


def run_plan(spec: dict, path: Path) -> int:
    with path.open(encoding="utf-8") as fh:
        plan = json.load(fh)
    block = plan.get("stylized_form")
    if not block:
        print(f"SKIP {path}: 没有 stylized_form 块（该资产未声明风格化形体）")
        return 0
    return report(evaluate(spec, block), str(path))


# --------------------------------------------------------------------------
# 自检
# --------------------------------------------------------------------------
def base_block():
    """8 件体量件全带 ρ（1.5%-3%），结构族同向正，独立体负，2 件挂件倾斜，
    每件都给了 extent 且变形轴选在短边，接缝全部留 3mm 缝或开槽。"""
    return {
        "form_style": "SF-B",
        "wall_thickness": 0.2,
        "slab_thickness": 0.2,
        "cornice_length": 8.0,
        "corners": 4,
        "body": {
            "width_base": 6.0, "width_top": 5.88,
            "depth_base": 5.0, "depth_top": 4.90,
            "height": 9.8, "triangles": 40000,
        },
        "components": [
            {"id": "wall_front", "kind": "shell", "role": "structure",
             "extent": [6.0, 0.2, 9.8], "taper_along": "z",
             "bottom": 6.0, "top": 5.88},
            {"id": "slab_1", "kind": "horizontal_cover",
             "extent": [5.0, 5.0, 0.2], "taper_along": "x",
             "bottom": 5.0, "top": 4.90},
            {"id": "post_a", "kind": "vertical_structure", "role": "structure",
             "extent": [0.5, 0.5, 4.9], "taper_along": "z",
             "bottom": 0.5, "top": 0.4875},
            {"id": "win_a", "kind": "opening",
             "extent": [1.2, 0.1, 1.5], "taper_along": "z",
             "bottom": 1.5, "top": 1.47},
            {"id": "tower", "kind": "freestanding",
             "extent": [1.6, 1.6, 2.0], "taper_along": "z",
             "bottom": 1.6, "top": 1.7288},
            {"id": "planter", "kind": "freestanding",
             "extent": [0.9, 0.9, 0.6], "taper_along": "x",
             "bottom": 0.9, "top": 0.972},
            {"id": "sign", "kind": "flat_attached",
             "extent": [1.8, 0.05, 1.0], "taper_along": "x",
             "bottom": 1.0, "top": 0.976,
             "tilt_deg": 7, "tilt_kind": "sign_board",
             "attached_to": "wall_front"},
            {"id": "menu", "kind": "flat_attached",
             "extent": [1.0, 0.05, 0.9], "taper_along": "x",
             "bottom": 0.9, "top": 0.878,
             "tilt_deg": 5, "tilt_kind": "sign_board"},
            {"id": "rail_post", "kind": "linear",
             "d_bottom": 0.06, "d_top": 0.056},
            {"id": "bolt", "kind": "no_volume", "no_volume": True, "bevel": 0.01},
        ],
        "contacts": [
            {"a": "sign", "b": "wall_front", "relation": "inset",
             "gap_m": 0.003, "note": "招牌背板开 6mm 浅槽嵌进墙壳"},
            {"a": "post_a", "b": "slab_1", "relation": "inset",
             "gap_m": 0.003},
        ],
        "relief": {"brick_protrusion": 0.05, "quoin_protrusion": 0.12,
                   "layers": 2, "quoin_blocks": 12, "brackets": 8},
    }


def selftest(spec: dict) -> int:
    cases: list[tuple[str, dict, str]] = []

    def mut(fn):
        b = base_block()
        fn(b)
        return b

    cases.append(("主体零收分", mut(lambda b: b["body"].update(
        {"width_top": 6.0, "depth_top": 5.0})), "no_square_volume"))

    cases.append(("主体收分超 10%", mut(lambda b: b["body"].update(
        {"width_top": 5.2, "depth_top": 4.3})), "rho_abs_max"))

    cases.append(("墙面倾角超 4°", mut(lambda b: b["body"].update(
        {"width_top": 5.3, "height": 4.0})), "wall_tilt"))

    cases.append(("主体被倾斜", mut(lambda b: b.update({"body_tilt_deg": 3})),
                  "body_tilt_forbidden"))

    cases.append(("柱子做成直筒", mut(lambda b: b["components"][2].update(
        {"top": 0.5})), "no_square_volume"))

    cases.append(("柱收分超 10%", mut(lambda b: b["components"][2].update(
        {"top": 0.42})), "rho_abs_max"))

    cases.append(("窗是正交矩形", mut(lambda b: b["components"][3].update(
        {"top": 1.5})), "no_square_volume"))

    cases.append(("窗收分小到看不出 0.5%", mut(lambda b: b["components"][3].update(
        {"top": 1.4925})), "no_square_volume"))

    cases.append(("水塔做成直筒", mut(lambda b: b["components"][4].update(
        {"top": 1.6})), "no_square_volume"))

    cases.append(("水塔做成正锥（该倒锥）", mut(lambda b: b["components"][4].update(
        {"top": 1.5})), "sign_family"))

    cases.append(("栏杆立柱做成直筒", mut(lambda b: b["components"][8].update(
        {"d_top": 0.06})), "cylinder_taper"))

    cases.append(("杆件变径不足 2%", mut(lambda b: b["components"][8].update(
        {"d_top": 0.0588})), "cylinder_taper"))

    def inconsistent(b):
        b["components"][2]["top"] = 0.52
    cases.append(("结构族符号不一致", mut(inconsistent), "sign_consistency"))

    def all_positive(b):
        b["components"][4]["top"] = 1.5
        b["components"][5]["top"] = 0.828
    cases.append(("全栋没有倒梯形", mut(all_positive), "sign_mix"))

    cases.append(("招牌倾斜 20°", mut(lambda b: b["components"][6].update(
        {"tilt_deg": 20})), "tilt"))

    cases.append(("墙被倾斜", mut(lambda b: b["components"][0].update(
        {"tilt_deg": 3, "tilt_kind": "leaning_panel"})),
        "structural_tilt_forbidden"))

    def no_tilt(b):
        for c in b["components"]:
            c.pop("tilt_deg", None)
            c.pop("tilt_kind", None)
    cases.append(("全楼没有一件倾斜", mut(no_tilt), "tilt_coverage"))

    cases.append(("登记嵌入层数却零几何", mut(lambda b: b.update(
        {"relief": {"brick_protrusion": 0.05, "quoin_protrusion": 0.12,
                    "layers": 1}})), "relief_presence"))

    cases.append(("隅石突出超 0.8 倍墙厚", mut(lambda b: b["relief"].update(
        {"quoin_protrusion": 0.30})), "relief_protrusion"))

    cases.append(("嵌入层数超 3", mut(lambda b: b["relief"].update(
        {"layers": 4, "quoin_blocks": 100})), "relief_layers"))

    cases.append(("造型面数超 35%", mut(lambda b: b["body"].update(
        {"triangles": 8000})), "tri_budget"))

    cases.append(("豁免件没给倒角", mut(lambda b: b["components"][9].pop("bevel")),
                  "micro_bevel"))

    cases.append(("薄板 0.05 厚却声明豁免", mut(lambda b: b["components"][9].update(
        {"thickness": 0.05})), "no_volume_thickness"))

    cases.append(("一堆正确里藏一件方盒", mut(lambda b: b["components"][1].update(
        {"top": 5.0})), "no_square_volume"))

    # --- 锥度方向：长边不许改 ---
    def taper_on_long_edge(b):
        sg = b["components"][6]
        sg["extent"] = [9.09, 0.47, 2.28]
        sg["taper_along"] = "z"          # 在 2.28 的高度方向渐变 9.09？
        sg["bottom"] = 9.09              # 错：把 9.09 米宽收成 8.9
        sg["top"] = 8.90
    cases.append(("招牌在 9 米宽上收分", mut(taper_on_long_edge), "taper_along_rule"))

    def taper_dir_wrong(b):
        b["components"][0]["taper_along"] = "x"   # 墙最长是 z(9.8)，却沿 x 收
    cases.append(("墙沿横向而非竖向收分", mut(taper_dir_wrong), "taper_along_rule"))

    def no_extent(b):
        b["components"][2].pop("extent")
    cases.append(("声明了方向却不给包络", mut(no_extent), "taper_along_rule"))

    # --- 接缝：不许面贴面、不许穿模 ---
    def coplanar(b):
        b["contacts"][0]["relation"] = "coplanar"
    cases.append(("两件共面贴合", mut(coplanar), "no_overlap"))

    def interpenetrate(b):
        b["contacts"][1]["relation"] = "interpenetrate"
    cases.append(("梯档穿进墙里", mut(interpenetrate), "no_overlap"))

    def tiny_gap(b):
        b["contacts"][0]["gap_m"] = 0.001
    cases.append(("只留 1mm 缝仍会闪", mut(tiny_gap), "no_overlap"))

    def no_gap(b):
        b["contacts"][0].pop("gap_m")
    cases.append(("开槽却没给缝宽", mut(no_gap), "no_overlap"))

    def cut_unverified(b):
        b["contacts"][0] = {"a": "sign", "b": "wall_front",
                            "relation": "boolean_cut"}
    cases.append(("布尔开洞未核验", mut(cut_unverified), "boolean_cut_verified"))

    def attach_no_contact(b):
        b["contacts"] = [c for c in b["contacts"] if c["a"] != "sign"]
    cases.append(("附着件没登记接缝", mut(attach_no_contact), "contact_declared"))

    ok = True
    for name, block, expect in cases:
        res = evaluate(spec, block)
        codes = [c for c, _ in res.fail]
        hit = expect in codes
        ok = ok and hit
        print(f"  {'PASS' if hit else 'MISS'} 反例「{name}」"
              + (f" → {expect} 已拦下" if hit else f" → 期望 {expect}，实得 {codes or '无'}"))

    good = evaluate(spec, base_block())
    clean = not good.fail
    ok = ok and clean
    print(f"  {'PASS' if clean else 'MISS'} 正例（8 件体量件全带 ρ + 豁免件）"
          + (" 通过" if clean else " 被误拦 " + str(good.fail)))
    print(f"  {len(cases)} 条反例 + 1 条正例，{'全部符合预期' if ok else '有断言缺口'}")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", help="component_plan.json，读其中 stylized_form 块")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    spec = load_spec()
    if args.selftest:
        print("== 断言自检 ==")
        return selftest(spec)
    if args.plan:
        return run_plan(spec, Path(args.plan))
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
