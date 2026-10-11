"""Weld native Blockbench GLBs and package one USDZ animation bank per companion.

Tooling only: numpy, scipy, Pillow, usd-core. None is an iOS dependency.
"""
import copy
import base64
import io
import json
import math
import struct
import tempfile
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdSkel, UsdUtils, Vt
from scipy.spatial.transform import Rotation, Slerp

from prepare_companions import GLB, HERE, SOURCES


class Writer:
    def __init__(self, doc):
        self.doc = doc
        self.doc["accessors"], self.doc["bufferViews"] = [], []
        self.binary = bytearray()
        self.shared = {}

    def view(self, raw):
        self.binary.extend(b"\0" * (-len(self.binary) % 4))
        index = len(self.doc["bufferViews"])
        self.doc["bufferViews"].append({"buffer": 0, "byteOffset": len(self.binary), "byteLength": len(raw)})
        self.binary.extend(raw)
        return index

    def array(self, values, component=5126, kind=None):
        dtype = {5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[component]
        values = np.array(values, dtype=dtype)
        columns = values.shape[1] if values.ndim > 1 else 1
        kind = kind or {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4", 16: "MAT4"}[columns]
        raw = values.tobytes()
        key = (component, kind, values.shape, raw)
        if key in self.shared:
            return self.shared[key]
        index = len(self.doc["accessors"])
        acc = {"bufferView": self.view(raw), "componentType": component, "count": len(values), "type": kind}
        if component == 5126 and kind in ("SCALAR", "VEC3"):
            acc["min"] = np.atleast_1d(values.min(axis=0)).astype(float).tolist()
            acc["max"] = np.atleast_1d(values.max(axis=0)).astype(float).tolist()
        self.doc["accessors"].append(acc)
        self.shared[key] = index
        return index

    def save(self, path):
        self.binary.extend(b"\0" * (-len(self.binary) % 4))
        self.doc["buffers"] = [{"byteLength": len(self.binary)}]
        header = json.dumps(self.doc, separators=(",", ":")).encode()
        header += b" " * (-len(header) % 4)
        raw = struct.pack("<4sII", b"glTF", 2, 28 + len(header) + len(self.binary))
        raw += struct.pack("<I4s", len(header), b"JSON") + header
        raw += struct.pack("<I4s", len(self.binary), b"BIN\0") + self.binary
        path.write_bytes(raw)


def simplify_track(times, values, rotation):
    tolerance = .0014 if rotation else .00015
    keep = {0, len(times) - 1}

    def visit(a, b):
        if b - a <= 1:
            return
        fraction = (times[a + 1:b] - times[a]) / (times[b] - times[a])
        if rotation:
            expected = Slerp(times[[a, b]], Rotation.from_quat(values[[a, b]]))(times[a + 1:b]).as_quat()
            error = 2 * np.arccos(np.clip(np.abs(np.sum(expected * values[a + 1:b], axis=1)), 0, 1))
        else:
            expected = values[a] + fraction[:, None] * (values[b] - values[a])
            error = np.max(np.abs(expected - values[a + 1:b]), axis=1)
        largest = int(np.argmax(error))
        if error[largest] > tolerance:
            pivot = a + 1 + largest
            keep.add(pivot)
            visit(a, pivot)
            visit(pivot, b)

    visit(0, len(times) - 1)
    indices = sorted(keep)
    return times[indices], values[indices]


def optimize(path, manifest):
    source = GLB(path)
    doc = copy.deepcopy(source.doc)
    writer = Writer(doc)
    mesh_nodes = [i for i, n in enumerate(doc["nodes"]) if "mesh" in n]
    old_primitives = [p for i in mesh_nodes for p in source.doc["meshes"][source.doc["nodes"][i]["mesh"]]["primitives"]]
    assert all(np.allclose(source.world[i], source.world[mesh_nodes[0]]) for i in mesh_nodes)
    assert all(s["joints"] == source.doc["skins"][0]["joints"] for s in source.doc["skins"])
    assert all(p.get("material", 0) == old_primitives[0].get("material", 0) for p in old_primitives)
    names = sorted(old_primitives[0]["attributes"])
    assert all(sorted(p["attributes"]) == names for p in old_primitives)
    arrays = [np.concatenate([source.accessor(p["attributes"][name]) for p in old_primitives]) for name in names]
    assert all(np.isfinite(a).all() for a in arrays)
    old_indices, offset = [], 0
    for p in old_primitives:
        old_indices.append(source.accessor(p["indices"]).ravel().astype(int) + offset)
        offset += source.doc["accessors"][p["attributes"]["POSITION"]]["count"]
    joined = np.column_stack(arrays)
    _, first, reverse = np.unique(joined, axis=0, return_index=True, return_inverse=True)
    prim = {"mode": 4, "material": old_primitives[0].get("material", 0), "attributes": {}}
    for name, array in zip(names, arrays):
        old_acc = source.doc["accessors"][old_primitives[0]["attributes"][name]]
        prim["attributes"][name] = writer.array(array[first], old_acc["componentType"], old_acc["type"])
    prim["indices"] = writer.array(reverse[np.concatenate(old_indices)], 5123 if len(first) <= 65535 else 5125)
    doc["meshes"] = [{"name": manifest["character"].title() + "Geometry", "primitives": [prim]}]
    for i in mesh_nodes:
        if i == mesh_nodes[0]:
            doc["nodes"][i]["mesh"], doc["nodes"][i]["skin"] = 0, 0
        else:
            doc["nodes"][i].pop("mesh", None)
            doc["nodes"][i].pop("skin", None)
    doc["skins"] = [copy.deepcopy(source.doc["skins"][0])]
    doc["skins"][0]["inverseBindMatrices"] = writer.array(source.accessor(source.doc["skins"][0]["inverseBindMatrices"]), kind="MAT4")
    for old_animation, animation in zip(source.doc["animations"], doc["animations"]):
        for index, (old, sampler) in enumerate(zip(old_animation["samplers"], animation["samplers"])):
            assert old.get("interpolation", "LINEAR") == "LINEAR"
            times = source.accessor(old["input"]).ravel().astype(float)
            values = source.accessor(old["output"]).astype(float)
            channels = [c for c in old_animation["channels"] if c["sampler"] == index]
            rotation = any(c["target"]["path"] == "rotation" for c in channels)
            new_t, new_v = simplify_track(times, values, rotation)
            sampler["input"] = writer.array(new_t)
            sampler["output"] = writer.array(new_v)
    project = json.loads(path.with_suffix('.bbmodel').read_text())
    bitmap = base64.b64decode(project['textures'][0]['source'].split(',', 1)[1])
    palette = Image.open(io.BytesIO(bitmap)).convert('RGB')
    assert palette.size == tuple(manifest['texture_size']) and np.asarray(palette).max() > 100
    assert len(doc['images']) == 1 and len(doc['textures']) == 1
    # Native glTF export can capture its PBR canvas before it has drawn the image.
    doc['images'][0]['bufferView'] = writer.view(bitmap)
    for material in doc["materials"]:
        material.pop("emissiveTexture", None)
        material.pop("alphaCutoff", None)
        material["alphaMode"] = "OPAQUE"
        if manifest["character"] == "pip":
            material.setdefault("extensions", {})["KHR_materials_clearcoat"] = {"clearcoatFactor": .24, "clearcoatRoughnessFactor": .26}
            if "KHR_materials_clearcoat" not in doc.setdefault("extensionsUsed", []):
                doc['extensionsUsed'].append('KHR_materials_clearcoat')
    writer.save(path)
    optimized = GLB(path)
    assert len(optimized.doc["animations"]) == 20
    assert len(optimized.doc["skins"]) == 1
    return optimized


def trs(node):
    t = np.array(node.get("translation", [0, 0, 0]), dtype=float)
    r = np.array(node.get("rotation", [0, 0, 0, 1]), dtype=float)
    s = np.array(node.get("scale", [1, 1, 1]), dtype=float)
    return t, r, s


def matrix(t, r, s):
    m = np.eye(4)
    m[:3, :3] = Rotation.from_quat(r).as_matrix() @ np.diag(s)
    m[:3, 3] = t
    return Gf.Matrix4d(m.T.tolist())


def sample(glb, animation, time):
    values = {i: list(trs(node)) for i, node in enumerate(glb.doc["nodes"])}
    for channel in animation["channels"]:
        sampler = animation["samplers"][channel["sampler"]]
        times = glb.accessor(sampler["input"]).ravel().astype(float)
        output = glb.accessor(sampler["output"]).astype(float)
        t = float(np.clip(time, times[0], times[-1]))
        path = channel["target"]["path"]
        if path == "rotation":
            v = Slerp(times, Rotation.from_quat(output))([t]).as_quat()[0]
        else:
            v = np.array([np.interp(t, times, output[:, j]) for j in range(output.shape[1])])
        values[channel["target"]["node"]][{"translation": 0, "rotation": 1, "scale": 2}[path]] = v
    return values


def package_usdz(glb, folder, manifest):
    character = manifest["character"]
    doc = glb.doc
    skin = doc["skins"][0]
    joint_nodes = skin["joints"]
    joint_set = set(joint_nodes)
    paths = {}

    def joint_path(index):
        if index not in paths:
            parent = glb.parents.get(index)
            name = doc["nodes"][index]["name"]
            paths[index] = (joint_path(parent) + "/" if parent in joint_set else "") + name
        return paths[index]

    joint_paths = [joint_path(n) for n in joint_nodes]
    topology = UsdSkel.Topology(Vt.TokenArray(joint_paths))
    assert topology.Validate()[0], topology.Validate()
    bind = glb.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    mesh_node = next(n for n in doc["nodes"] if n.get("skin") == 0)
    primitive = doc["meshes"][mesh_node["mesh"]]["primitives"][0]
    assert len(doc["meshes"][mesh_node["mesh"]]["primitives"]) == 1
    attrs = primitive["attributes"]
    points = glb.accessor(attrs["POSITION"]).astype(float)
    normals = glb.accessor(attrs["NORMAL"]).astype(float)
    uv = glb.accessor(attrs["TEXCOORD_0"]).astype(float)
    uv[:, 1] = 1 - uv[:, 1]
    indices = glb.accessor(primitive["indices"]).ravel().astype(int)
    joints = glb.accessor(attrs["JOINTS_0"]).astype(int)
    weights = glb.accessor(attrs["WEIGHTS_0"]).astype(float)
    assert np.allclose(weights.sum(axis=1), 1, atol=1e-4)
    assert joints.max() < len(joint_nodes)
    assert indices.max() < len(points) and len(indices) // 3 == manifest["triangles"]
    bounds = np.array([points.min(axis=0), points.max(axis=0)])
    with tempfile.TemporaryDirectory(prefix="gymni-usd-") as temporary:
        directory = Path(temporary)
        stage = Usd.Stage.CreateNew(str(directory / (character + ".usdc")))
        UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
        UsdGeom.SetStageMetersPerUnit(stage, 1)
        stage.SetTimeCodesPerSecond(24)
        stage.SetFramesPerSecond(24)
        stage.SetStartTimeCode(0)
        root = UsdSkel.Root.Define(stage, "/Companion")
        stage.SetDefaultPrim(root.GetPrim())
        skeleton = UsdSkel.Skeleton.Define(stage, "/Companion/Skeleton")
        skeleton.CreateJointsAttr(Vt.TokenArray(joint_paths))
        skeleton.CreateRestTransformsAttr(Vt.Matrix4dArray([matrix(*trs(doc["nodes"][n])) for n in joint_nodes]))
        skeleton.CreateBindTransformsAttr(Vt.Matrix4dArray([Gf.Matrix4d(np.linalg.inv(m).T.tolist()) for m in bind]))
        mesh = UsdGeom.Mesh.Define(stage, "/Companion/Geometry")
        mesh.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(points.astype(np.float32)))
        mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3] * (len(indices) // 3)))
        mesh.CreateFaceVertexIndicesAttr(Vt.IntArray(indices.tolist()))
        mesh.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(normals.astype(np.float32)))
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        mesh.CreateDoubleSidedAttr(True)
        mesh.CreateExtentAttr(Vt.Vec3fArray.FromNumpy(bounds.astype(np.float32)))
        UsdGeom.PrimvarsAPI(mesh).CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex).Set(Vt.Vec2fArray.FromNumpy(uv.astype(np.float32)))
        binding = UsdSkel.BindingAPI.Apply(mesh.GetPrim())
        binding.CreateSkeletonRel().SetTargets([skeleton.GetPath()])
        binding.CreateGeomBindTransformAttr(Gf.Matrix4d(1))
        binding.CreateJointIndicesPrimvar(False, 4).Set(Vt.IntArray(joints.ravel().tolist()))
        binding.CreateJointWeightsPrimvar(False, 4).Set(Vt.FloatArray(weights.ravel().tolist()))
        material = UsdShade.Material.Define(stage, "/Companion/Material")
        shader = UsdShade.Shader.Define(stage, "/Companion/Material/Surface")
        shader.CreateIdAttr("UsdPreviewSurface")
        shader.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(manifest["roughness"])
        shader.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0)
        shader.CreateInput("clearcoat", Sdf.ValueTypeNames.Float).Set(.24 if character == "pip" else 0)
        material.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), "surface")
        image = doc["images"][0]
        view = doc["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        (directory / "palette.png").write_bytes(glb.binary[start:start + view["byteLength"]])
        texture = UsdShade.Shader.Define(stage, "/Companion/Material/Texture")
        texture.CreateIdAttr("UsdUVTexture")
        texture.CreateInput("file", Sdf.ValueTypeNames.Asset).Set(Sdf.AssetPath("palette.png"))
        texture.CreateInput("sourceColorSpace", Sdf.ValueTypeNames.Token).Set("sRGB")
        reader = UsdShade.Shader.Define(stage, "/Companion/Material/UV")
        reader.CreateIdAttr("UsdPrimvarReader_float2")
        reader.CreateInput("varname", Sdf.ValueTypeNames.Token).Set("st")
        reader.CreateOutput("result", Sdf.ValueTypeNames.Float2)
        texture.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(reader.ConnectableAPI(), "result")
        texture.CreateOutput("rgb", Sdf.ValueTypeNames.Float3)
        shader.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).ConnectToSource(texture.ConnectableAPI(), "rgb")
        UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(material)
        bank = UsdSkel.Animation.Define(stage, "/Companion/AnimationBank")
        bank.CreateJointsAttr(Vt.TokenArray(joint_paths))
        translation_attr, rotation_attr, scale_attr = bank.CreateTranslationsAttr(), bank.CreateRotationsAttr(), bank.CreateScalesAttr()
        cursor, ranges = 0, []
        for animation, clip in zip(doc["animations"], manifest["clips"]):
            assert animation["name"] == clip["name"]
            frames = math.ceil(clip["duration"] * 24)
            for frame in range(frames + 1):
                values = sample(glb, animation, clip["duration"] * frame / frames)
                translation_attr.Set(Vt.Vec3fArray([Gf.Vec3f(*values[n][0]) for n in joint_nodes]), cursor + frame)
                rotation_attr.Set(Vt.QuatfArray([Gf.Quatf(float(values[n][1][3]), Gf.Vec3f(*values[n][1][:3])) for n in joint_nodes]), cursor + frame)
                scale_attr.Set(Vt.Vec3hArray([Gf.Vec3h(*values[n][2]) for n in joint_nodes]), cursor + frame)
            ranges.append({"name": clip["name"], "start": cursor / 24, "end": (cursor + frames) / 24, "loop": clip["loop"]})
            cursor += frames + 1
        UsdSkel.BindingAPI.Apply(skeleton.GetPrim()).CreateAnimationSourceRel().SetTargets([bank.GetPath()])
        root.GetPrim().SetCustomDataByKey("clipRangesJSON", json.dumps(ranges))
        stage.SetEndTimeCode(cursor - 1)
        stage.GetRootLayer().Save()
        path = folder / (character + ".usdz")
        assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(directory / (character + ".usdc"))), str(path))
    loaded = Usd.Stage.Open(str(path))
    cache = UsdSkel.Cache()
    cache.Populate(UsdSkel.Root(loaded.GetPrimAtPath("/Companion")), Usd.PrimDefaultPredicate)
    query = cache.GetSkelQuery(UsdSkel.Skeleton(loaded.GetPrimAtPath("/Companion/Skeleton")))
    assert query and query.GetAnimQuery()
    checks = []
    for clip, interval in zip(manifest["clips"], ranges):
        start_frame, end_frame = interval["start"] * 24, interval["end"] * 24
        a = np.asarray(query.ComputeSkinningTransforms(start_frame))
        b = np.asarray(query.ComputeSkinningTransforms(end_frame))
        middle = np.asarray(query.ComputeSkinningTransforms(start_frame + (end_frame - start_frame) * .375))
        seam = float(np.max(np.abs(a - b)))
        assert seam < 1e-4 and np.isfinite(middle).all(), (character, clip["name"], seam)
        assert np.max(np.abs(a - middle)) > 1e-6, (character, clip["name"], "no animated skeleton")
        checks.append({"name": clip["name"], "seam": seam})
    manifest.update({"glb_bytes": (folder / (character + ".glb")).stat().st_size, "usdz_bytes": path.stat().st_size,
                     "mobile_vertices": len(points), "usd_clip_ranges": ranges, "usd_validation": checks})
    (folder / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def previews(character):
    folder = HERE / character
    font = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 20)
    board = Image.new("RGB", (1200, 5 * 250), "#101a20")
    draw = ImageDraw.Draw(board)
    for i, path in enumerate(sorted((folder / "review").glob("*-0.5.png"))):
        cell = Image.open(path).convert("RGBA")
        cell.thumbnail((290, 215))
        x, y = (i % 4) * 300, (i // 4) * 250
        board.paste(cell, (x + (300 - cell.width) // 2, y), cell)
        draw.text((x + 12, y + 220), path.stem.replace("-0.5", "").replace("_", " "), fill="white", font=font)
    board.save(folder / "all-animations.jpg", quality=90)
    for name in ("float", "coaching", "celebrate", "stretch"):
        frames = []
        for path in sorted((folder / "review" / name).glob("*.png")):
            img = Image.open(path).convert("RGBA")
            img.thumbnail((400, 400))
            base = Image.new("RGB", img.size, "#101a20")
            base.paste(img, (0, 0), img)
            frames.append(base)
        duration = next(c["duration"] for c in json.loads((folder / "manifest.json").read_text())["clips"] if c["name"] == name)
        frames[0].save(folder / (name + ".gif"), save_all=True, append_images=frames[1:], duration=round(duration * 1000 / len(frames)), loop=0, optimize=True)


def ios_archive():
    clips = {}
    with zipfile.ZipFile(HERE / 'gymni-companions-ios.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for character in SOURCES:
            folder = HERE / character
            manifest = json.loads((folder / 'manifest.json').read_text())
            archive.write(folder / (character + '.usdz'), character + '.usdz')
            clips[character] = {'asset': character + '.usdz', 'bank': 'AnimationBank',
                                'samples_per_second': 24, 'clips': manifest['usd_clip_ranges']}
        archive.writestr('ios-clips.json', json.dumps(clips, indent=2) + '\n')
        archive.writestr('README.txt', 'Unzip before adding assets to the iOS target. Ship only needed USDZ files and ios-clips.json.\n'
                          'Each USDZ has one skeletal animation bank. Trim the imported bank to the named start/end seconds; repeat only loop=true clips.\n'
                          'Stop competing procedural body/orbit motion. Honor Reduce Motion and pause offscreen.\n'
                          'Validated with OpenUSD on Windows; RealityKit import, clip trimming, materials and device performance remain untested.\n')


if __name__ == "__main__":
    for character in SOURCES:
        folder = HERE / character
        manifest = json.loads((folder / "manifest.json").read_text())
        glb = optimize(folder / (character + ".glb"), manifest)
        package_usdz(glb, folder, manifest)
        previews(character)
        print(character, manifest["glb_bytes"], "GLB bytes;", manifest["usdz_bytes"], "USDZ bytes", flush=True)
    ios_archive()
