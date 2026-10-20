#!/usr/bin/env python3
"""极简 glTF 2.0 二进制（.glb）写入器。

只覆盖本项目需要的能力：三角形网格、多材质 primitive、顶点色、内嵌 PNG 贴图。
不引入第三方依赖，保证资产管线可以在任何装了 python3 的环境重跑。

约定：
  - 坐标 Y-up，单位米，与 Godot / 网页版一致（不做轴转换）。
  - COLOR_0 用线性空间 float，语义等价于 Three.js 的 material.color。
  - POSITION 必须带 min/max（glTF 规范硬要求）。
"""
import json
import struct


class Glb:
    COMP = {
        "SCALAR": 1,
        "VEC2": 2,
        "VEC3": 3,
        "VEC4": 4,
    }
    FLOAT = 5126
    UINT = 5125

    def __init__(self, generator="sea-reverse-bake"):
        self.blob = bytearray()
        self.doc = {
            "asset": {"version": "2.0", "generator": generator},
            "scene": 0,
            "scenes": [{"nodes": [0]}],
            "nodes": [{"name": "root", "children": []}],
            "meshes": [],
            "materials": [],
            "textures": [],
            "images": [],
            "samplers": [
                {"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}
            ],
            "accessors": [],
            "bufferViews": [],
            "buffers": [],
        }
        self._images = {}

    # ---------------------------------------------------------------- 基础块
    def _align(self, n=4):
        while len(self.blob) % n:
            self.blob.append(0)

    def add_view(self, data, target=None):
        self._align(4)
        offset = len(self.blob)
        self.blob.extend(data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        self.doc["bufferViews"].append(view)
        return len(self.doc["bufferViews"]) - 1

    def add_accessor(self, view, count, comp_type, type_name, minmax=None):
        acc = {
            "bufferView": view,
            "byteOffset": 0,
            "componentType": comp_type,
            "count": count,
            "type": type_name,
        }
        if minmax:
            acc["min"], acc["max"] = minmax
        self.doc["accessors"].append(acc)
        return len(self.doc["accessors"]) - 1

    def add_floats(self, values, type_name):
        n = self.COMP[type_name]
        data = struct.pack("<%df" % len(values), *values)
        view = self.add_view(data, 34962)  # ARRAY_BUFFER
        return self.add_accessor(view, len(values) // n, self.FLOAT, type_name)

    def add_indices(self, indices):
        data = struct.pack("<%dI" % len(indices), *indices)
        view = self.add_view(data, 34963)  # ELEMENT_ARRAY_BUFFER
        return self.add_accessor(view, len(indices), self.UINT, "SCALAR")

    # ---------------------------------------------------------------- 图像
    def add_image(self, png_bytes, name="texture"):
        """同一份 PNG 只内嵌一次。返回 texture 索引。"""
        key = (name, len(png_bytes))
        if key in self._images:
            return self._images[key]
        view = self.add_view(png_bytes)
        self.doc["images"].append(
            {"bufferView": view, "mimeType": "image/png", "name": name}
        )
        self.doc["textures"].append(
            {"source": len(self.doc["images"]) - 1, "sampler": 0}
        )
        idx = len(self.doc["textures"]) - 1
        self._images[key] = idx
        return idx

    # ---------------------------------------------------------------- 材质
    def add_material(self, name, tex=None, unlit=False, alpha=False, double_sided=False,
                     color=None, opacity=1.0, emissive=None, emissive_strength=0.0):
        base = [1.0, 1.0, 1.0, 1.0]
        if color is not None:
            base = [float(color[0]), float(color[1]), float(color[2]), float(opacity)]
        mat = {
            "name": name,
            "pbrMetallicRoughness": {
                "baseColorFactor": base,
                "metallicFactor": 0.0,
                "roughnessFactor": 1.0,
            },
        }
        if tex is not None:
            mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": tex}
        if emissive is not None and emissive_strength > 0.0:
            # glTF 的 emissiveFactor 上限 1.0，超过部分用 KHR_materials_emissive_strength。
            mat["emissiveFactor"] = [min(1.0, float(c)) for c in emissive]
            if emissive_strength > 1.0:
                mat.setdefault("extensions", {})["KHR_materials_emissive_strength"] = {
                    "emissiveStrength": float(emissive_strength)
                }
                used = self.doc.setdefault("extensionsUsed", [])
                if "KHR_materials_emissive_strength" not in used:
                    used.append("KHR_materials_emissive_strength")
        if alpha:
            mat["alphaMode"] = "BLEND"
        else:
            mat["alphaMode"] = "OPAQUE"
        if double_sided:
            mat["doubleSided"] = True
        if unlit:
            mat["extensions"] = {"KHR_materials_unlit": {}}
            self.doc.setdefault("extensionsUsed", [])
            if "KHR_materials_unlit" not in self.doc["extensionsUsed"]:
                self.doc["extensionsUsed"].append("KHR_materials_unlit")
        self.doc["materials"].append(mat)
        return len(self.doc["materials"]) - 1

    # ---------------------------------------------------------------- 网格
    def add_mesh(self, name, primitives):
        """primitives: [{ 'attributes': {...}, 'indices': int, 'material': int }]"""
        self.doc["meshes"].append({"name": name, "primitives": primitives})
        return len(self.doc["meshes"]) - 1

    def attach_mesh(self, mesh_index, node_name=None, translation=None):
        node = {"mesh": mesh_index}
        if node_name:
            node["name"] = node_name
        if translation:
            node["translation"] = list(translation)
        self.doc["nodes"].append(node)
        self.doc["nodes"][0]["children"].append(len(self.doc["nodes"]) - 1)
        return len(self.doc["nodes"]) - 1

    # ---------------------------------------------------------------- 输出
    def save(self, path):
        while len(self.blob) % 4:
            self.blob.append(0)
        self.doc["buffers"] = [{"byteLength": len(self.blob)}]
        js = json.dumps(self.doc, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        while len(js) % 4:
            js += b" "
        total = 12 + 8 + len(js) + 8 + len(self.blob)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A))
            f.write(js)
            f.write(struct.pack("<II", len(self.blob), 0x004E4942))
            f.write(self.blob)
        return total
