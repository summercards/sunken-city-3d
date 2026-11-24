import json
import math
from mathutils import Matrix, Vector

import bpy


def make_materials(palette_path):
    image = bpy.data.images.load(str(palette_path), check_existing=True)
    palette = json.loads(palette_path.with_suffix(".json").read_text())
    swatches = {c["name"]: (c["column"], c["row"]) for c in palette["cells"]}
    materials = {}
    for role, roughness, metal in (
        ("Matte", .74, 0), ("Metal", .42, .28),
        ("Gloss", .20, .03), ("Emission", .37, 0),
    ):
        material = bpy.data.materials.new("SEA_" + role)
        material.use_nodes = True
        material.roughness = roughness
        tree = material.node_tree
        shader = tree.nodes.get("Principled BSDF")
        shader.inputs["Roughness"].default_value = roughness
        shader.inputs["Metallic"].default_value = metal
        uv = tree.nodes.new("ShaderNodeUVMap")
        uv.uv_map = "PaletteUV"
        texture = tree.nodes.new("ShaderNodeTexImage")
        texture.image = image
        texture.interpolation = "Closest"
        tree.links.new(uv.outputs["UV"], texture.inputs["Vector"])
        tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
        if role == "Gloss":
            shader.inputs["Alpha"].default_value = .31
            shader.inputs["Coat Weight"].default_value = .36
            material.surface_render_method = "DITHERED"
        if role == "Emission":
            tree.links.new(texture.outputs["Color"], shader.inputs["Emission Color"])
            shader.inputs["Emission Strength"].default_value = .75
        materials[role] = material
    return materials, swatches, image


class Model:
    def __init__(self, collection, materials, swatches):
        self.collection = collection
        self.materials = materials
        self.swatches = swatches
        self.form = []

    def mesh(self, name, vertices, faces, colors, *, role="Matte", bevel=0, smooth=False):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(vertices, [], faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        self.collection.objects.link(obj)
        mesh.materials.append(self.materials[role])
        layer = mesh.uv_layers.new(name="PaletteUV")
        layer.active_render = True
        for polygon in mesh.polygons:
            color = colors if isinstance(colors, str) else colors[polygon.index % len(colors)]
            column, row = self.swatches[color]
            u, v = (column + .5) / 8, 1 - (row + .5) / 8
            for i, loop in enumerate(polygon.loop_indices):
                angle = 2 * math.pi * i / polygon.loop_total
                layer.data[loop].uv = (u + .035 * math.cos(angle), v + .035 * math.sin(angle))
            polygon.use_smooth = smooth
        if bevel:
            modifier = obj.modifiers.new("Real edge rounding", "BEVEL")
            modifier.width = bevel
            modifier.segments = 3
            modifier.limit_method = "ANGLE"
            modifier.harden_normals = True
            for polygon in mesh.polygons:
                polygon.use_smooth = True
            normals = obj.modifiers.new("Weighted surface normals", "WEIGHTED_NORMAL")
            normals.keep_sharp = True
        return obj

    def box(self, name, center, size, color, *, bevel=.035, rho=.021, rotation=None, role="Matte",
            kind="vertical_structure", tilt=0, record=True):
        axis = max(range(3), key=lambda i: size[i])
        cross = [i for i in range(3) if i != axis]
        matrix = rotation or Matrix.Identity(3)
        verts = []
        for end in (-1, 1):
            for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                coord = [0., 0., 0.]
                factor = 1 - rho if end == 1 else 1
                coord[axis] = end * size[axis] / 2
                coord[cross[0]] = a * size[cross[0]] / 2 * factor
                coord[cross[1]] = b * size[cross[1]] / 2 * factor
                verts.append(matrix @ Vector(coord) + Vector(center))
        faces = [(3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4),
                 (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        if axis == 1:
            faces = [tuple(reversed(face)) for face in faces]
        if record:
            self.form.append({"id": name, "kind": kind, "bottom": size[cross[0]],
                              "top": size[cross[0]] * (1 - rho), "extent": size,
                              "taper_along": "xyz"[axis], "tilt_deg": tilt})
        return self.mesh(name, verts, faces, color, role=role, bevel=min(bevel, min(size) * .48))

    def bar(self, name, a, b, width, color, *, depth=None, bevel=.025, role="Matte", kind="vertical_structure"):
        a, b = Vector(a), Vector(b)
        direction = b - a
        rotation = direction.to_track_quat("Z", "Y").to_matrix()
        return self.box(name, (a + b) / 2, (width, depth or width, direction.length), color,
                        rotation=rotation, bevel=bevel, role=role, kind=kind)

    def round(self, name, a, b, r0, r1, color, *, n=12, role="Matte", bevel=.018, kind="linear"):
        a, b = Vector(a), Vector(b)
        matrix = (b - a).to_track_quat("Z", "Y").to_matrix()
        verts = []
        for center, radius in ((a, r0), (b, r1)):
            for i in range(n):
                angle = 2 * math.pi * i / n
                verts.append(center + matrix @ Vector((radius * math.cos(angle), radius * math.sin(angle), 0)))
        faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
        faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
        if kind == "linear":
            self.form.append({"id": name, "kind": kind, "d_bottom": r0 * 2, "d_top": r1 * 2})
        elif kind != "sculpted":
            self.form.append({"id": name, "kind": kind, "bottom": r0 * 2, "top": r1 * 2})
        return self.mesh(name, verts, faces, color, role=role, bevel=bevel)

    def vessel(self, name, xy, rings, colors, *, n=24, role="Matte", kind="shell"):
        x, y = xy
        vertices = [(x+r*math.cos(math.tau*i/n), y+r*math.sin(math.tau*i/n), z)
                    for z,r in rings for i in range(n)]
        faces = [tuple(range(n-1,-1,-1))]
        for band in range(len(rings)-1):
            for i in range(n):
                a, b = band*n+i, band*n+(i+1)%n
                faces.append((a,b,b+n,a+n))
        faces.append(tuple(range((len(rings)-1)*n,len(rings)*n)))
        self.form.append({"id":name,"kind":kind,"bottom":2*rings[0][1],"top":2*rings[-1][1]})
        obj = self.mesh(name,vertices,faces,colors,role=role,smooth=True)
        obj.data.polygons[0].use_smooth = False
        obj.data.polygons[-1].use_smooth = False
        return obj

    def panel(self, name, points, thickness, color, *, bevel=.015, role="Matte"):
        front = [Vector(p) for p in points]
        normal = (front[1] - front[0]).cross(front[2] - front[0]).normalized()
        middle = sum(front, Vector()) / len(front)
        back = [middle + (p - middle) * .974 - normal * thickness for p in front]
        n = len(front)
        faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
        faces += [((i + 1) % n, i, i + n, (i + 1) % n + n) for i in range(n)]
        return self.mesh(name, front + back, faces, color, role=role, bevel=bevel)

    def leaf(self, name, start, tip, width, color):
        start, tip = Vector(start), Vector(tip)
        d = tip - start
        side = Vector((-d.y, d.x, 0)).normalized() * width
        if side.length < .001:
            side = Vector((width, 0, 0))
        mid = start.lerp(tip, .50)
        ridge = mid + Vector((0, 0, width * .43))
        verts = [start, mid + side, tip, mid - side, ridge, mid - Vector((0, 0, width * .20))]
        faces = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4),
                 (1, 0, 5), (2, 1, 5), (3, 2, 5), (0, 3, 5)]
        return self.mesh(name, verts, faces, color, smooth=True)

    def recenter(self):
        vertices = [v.co for obj in self.collection.objects for v in obj.data.vertices]
        low = Vector(tuple(min(v[i] for v in vertices) for i in range(3)))
        high = Vector(tuple(max(v[i] for v in vertices) for i in range(3)))
        origin = Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z))
        for obj in self.collection.objects:
            obj.data.transform(Matrix.Translation(-origin))
        return origin, high - low
