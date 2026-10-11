"""Import the selected GLBs into lightweight, animated Blockbench projects.

Run with the repository Python (numpy, scipy, Pillow, fast-simplification).
Sources are read only. Animation editing and final GLB export happen in Blockbench.
"""
import base64
import hashlib
import io
import json
import math
import struct
import uuid
from pathlib import Path

import fast_simplification
import numpy as np
from PIL import Image
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree
from scipy.spatial.transform import Rotation

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SOURCES = {"atlas": "atlas-mobile.glb", "flex": "flex.glb", "pip": "pip-refined.glb"}
CLIPS = [
    ("idle", 4, True, "Home / ready, quiet presence"),
    ("float", 4, True, "Optional floating showcase"),
    ("greeting", 2.4, False, "Welcome / onboarding"),
    ("ready", 1.6, False, "Camera calibrated, workout ready"),
    ("listening", 3, True, "User speaking / preferences"),
    ("thinking", 3, True, "Plan or coach reply loading"),
    ("coaching", 2.4, True, "Coach speech, explanatory gesture"),
    ("rep_good", 1.2, False, "Backend commits a good rep"),
    ("form_correct", 2, False, "Nonjudgmental form cue"),
    ("encourage", 2, False, "Effort encouragement"),
    ("countdown", 3, False, "Three-second start cue"),
    ("set_complete", 2.4, False, "Set finished"),
    ("celebrate", 2.8, False, "Milestone / Today tap"),
    ("rest", 5, True, "Between sets / rest screen"),
    ("breathe", 6, True, "Slow recovery breathing visual"),
    ("stretch", 4, True, "Warmup / cooldown companion stretch"),
    ("pause", 3, True, "Workout paused"),
    ("reconnect", 3, True, "Connection stale / camera lost"),
    ("workout_complete", 3.2, False, "Recap / workout finished"),
    ("goodbye", 2.4, False, "Finish / leave workout"),
]


def uid(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "gymni-blockbench/" + name))


class GLB:
    def __init__(self, path):
        raw = path.read_bytes()
        self.sha = hashlib.sha256(raw).hexdigest()
        assert raw[:4] == b"glTF" and struct.unpack_from("<I", raw, 4)[0] == 2
        size = struct.unpack_from("<I", raw, 12)[0]
        self.doc = json.loads(raw[20:20 + size])
        self.binary = raw[28 + size:]
        self.world = {}
        self.parents = {}

        def visit(index, parent):
            node = self.doc["nodes"][index]
            local = np.eye(4)
            if "matrix" in node:
                local = np.array(node["matrix"]).reshape(4, 4).T
            else:
                local[:3, :3] = Rotation.from_quat(node.get("rotation", [0, 0, 0, 1])).as_matrix() @ np.diag(node.get("scale", [1, 1, 1]))
                local[:3, 3] = node.get("translation", [0, 0, 0])
            self.world[index] = parent @ local
            for child in node.get("children", []):
                self.parents[child] = index
                visit(child, self.world[index])

        for index in self.doc["scenes"][self.doc.get("scene", 0)]["nodes"]:
            visit(index, np.eye(4))

    def accessor(self, index):
        acc = self.doc["accessors"][index]
        view = self.doc["bufferViews"][acc["bufferView"]]
        dtype = {5120: "i1", 5121: "u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[acc["componentType"]]
        columns = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[acc["type"]]
        width = np.dtype(dtype).itemsize
        arr = np.ndarray((acc["count"], columns), dtype, self.binary,
                         offset=view.get("byteOffset", 0) + acc.get("byteOffset", 0),
                         strides=(view.get("byteStride", width * columns), width)).copy()
        if acc.get("normalized"):
            arr = arr.astype(float) / np.iinfo(dtype).max
        return arr


def compact(points, faces):
    used, inverse = np.unique(faces, return_inverse=True)
    return points[used], inverse.reshape(-1, 3), used


def reduce_mesh(points, faces, target):
    if len(faces) <= target:
        return points, faces
    points, faces = fast_simplification.simplify(points.astype(np.float64), faces.astype(np.int32), target_count=target, agg=5)
    return compact(points, faces)[:2]


def reduce_fur(points, faces):
    # Keep entire curls rather than deleting arbitrary triangles from the carpet.
    welded, reverse = np.unique(np.round(points, 6), axis=0, return_inverse=True)
    f = reverse[faces]
    edges = np.concatenate((f[:, :2], f[:, 1:], f[:, [2, 0]]))
    adjacency = coo_matrix((np.ones(len(edges)), (edges[:, 0], edges[:, 1])), shape=(len(welded), len(welded)))
    count, labels = connected_components(adjacency, directed=False)
    face_labels = labels[f[:, 0]]
    batches = []
    for label in range(count):
        if label % 8:
            continue
        part = f[face_labels == label]
        if len(part) < 4:
            continue
        p, part, _ = compact(welded, part)
        p, part = reduce_mesh(p, part, 20)
        batches.append((p, part))
    assert batches, "No intact fur strands found"
    points_out, faces_out, offset = [], [], 0
    for p, f in batches:
        points_out.append(p)
        faces_out.append(f + offset)
        offset += len(p)
    return np.concatenate(points_out), np.concatenate(faces_out)


def srgb(linear):
    linear = np.clip(linear, 0, 1)
    return np.where(linear <= .0031308, linear * 12.92, 1.055 * linear ** (1 / 2.4) - .055)


def pose(character, clip, t, duration):
    u = t / duration
    s = math.sin(2 * math.pi * u)
    pulse = math.sin(math.pi * u) ** 2
    lift = {"atlas": .045, "flex": .10, "pip": .18}[character]
    spring = {"atlas": .35, "flex": 1.0, "pip": .65}[character]
    root_pos, root_rot, root_scale = [0., 0., 0.], [0., 0., 0.], [1., 1., 1.]
    head, body, left, right = [0., 0., 0.], [0., 0., 0.], [0., 0., 0.], [0., 0., 0.]
    eye_scale, orbit = [1., 1., 1.], [0., 0., 0.]
    if clip == "idle":
        root_pos[1] = lift * .15 * s
        body[2] = spring * 1.8 * s
        head[0] = 1.2 * s
    elif clip == "float":
        root_pos[1] = lift * (1 - math.cos(2 * math.pi * u))
        root_rot[2] = 3 * spring * s
        left[2], right[2] = -8 * s, 8 * s
    elif clip in ("greeting", "goodbye"):
        right[2] = -24 * pulse - 16 * math.sin(6 * math.pi * u) * pulse
        head[2] = 5 * pulse
        root_rot[1] = (8 if clip == "greeting" else -12) * pulse
    elif clip == "ready":
        root_scale = [1 + .025 * spring * pulse, 1 - .035 * spring * pulse, 1 + .02 * pulse]
        left[2], right[2] = -16 * pulse, 16 * pulse
        head[0] = -6 * pulse
    elif clip == "listening":
        head[2] = 6 * pulse
        head[0] = 2 * s
        root_pos[1] = lift * .04 * s
    elif clip == "thinking":
        head[1] = 9 * s
        right[0] = -15 * pulse
        right[2] = -12 * pulse
    elif clip == "coaching":
        head[0] = 4 * s
        right[2] = -15 * pulse
        right[0] = 10 * s
        left[2] = 5 * pulse
    elif clip == "rep_good":
        head[0] = 10 * math.sin(2 * math.pi * u) * pulse
        root_pos[1] = lift * .3 * pulse
        right[2] = -18 * pulse
    elif clip == "form_correct":
        body[0] = 5 * pulse
        head[2] = -5 * pulse
        right[0] = -22 * pulse
        right[2] = -10 * pulse
    elif clip == "encourage":
        left[2], right[2] = -25 * pulse, 25 * pulse
        body[0] = -5 * pulse
        root_scale[1] += spring * .035 * pulse
    elif clip == "countdown":
        beat = math.sin(3 * math.pi * u) ** 2
        head[0] = 6 * beat
        root_scale[1] -= .03 * spring * beat
        root_pos[1] = lift * .2 * beat
    elif clip in ("set_complete", "celebrate", "workout_complete"):
        power = {"set_complete": .55, "celebrate": 1, "workout_complete": .8}[clip]
        bounce = math.sin(2 * math.pi * u) ** 2 * pulse
        root_pos[1] = lift * 2 * power * bounce
        root_rot[1] = (18 if clip != "workout_complete" else 32) * math.sin(2 * math.pi * u) * pulse
        root_scale = [1 - .06 * spring * bounce, 1 + .09 * spring * bounce, 1 - .04 * spring * bounce]
        left[2], right[2] = -38 * power * pulse, 38 * power * pulse
        head[0] = -7 * pulse
    elif clip in ("rest", "breathe"):
        breath = (1 - math.cos(2 * math.pi * u)) / 2
        root_scale = [1 + .015 * breath, 1 + .025 * spring * breath, 1 + .02 * breath]
        body[0] = 3 * pulse
        head[0] = 4 * pulse
        left[2], right[2] = 5 * pulse, -5 * pulse
    elif clip == "stretch":
        body[2] = 8 * spring * s
        root_scale[1] = 1 + .05 * spring * pulse
        left[2], right[2] = -24 * pulse, 24 * pulse
        head[2] = -4 * s
    elif clip == "pause":
        head[0] = 3 * pulse
        root_pos[1] = lift * .02 * s
    elif clip == "reconnect":
        head[1] = 14 * s
        right[2] = -9 * pulse
        head[2] = 3 * pulse
    if character == "pip":
        orbit = [4 * s, 16 * s if clip not in ("pause", "rest") else 3 * s, 3 * pulse]
    elif character == "atlas":
        root_rot[2] *= .3
    blink = max(0., 1 - abs(u - .78) / .025) if clip not in ("rep_good", "ready") else 0
    eye_scale[1] = 1 - .85 * blink
    return {"Root": {"position": [x * 16 for x in root_pos], "rotation": root_rot, "scale": root_scale},
            "Body": {"rotation": body}, "Head": {"rotation": head},
            "LeftArm": {"rotation": left}, "RightArm": {"rotation": right},
            "LeftEye": {"scale": eye_scale}, "RightEye": {"scale": eye_scale},
            "Orbit": {"rotation": orbit}}


def build(character):
    source = ROOT / "blender-companions" / character / SOURCES[character]
    glb = GLB(source)
    nodes = glb.doc["nodes"]
    names = {node.get("name"): index for index, node in enumerate(nodes)}
    folder = HERE / character
    folder.mkdir(parents=True, exist_ok=True)
    armature_id = uid(character + "/rig")
    bones = {}

    def bone(name, origin, parent="Root"):
        bones[name] = {"type": "armature_bone", "name": name, "uuid": uid(character + "/" + name),
                       "origin": np.round(np.array(origin) * 16, 6).tolist(), "rotation": [0, 0, 0],
                       "length": 3, "width": .5, "connected": False, "vertex_weights": {}, "parent_name": parent}

    bone("Root", [0, 0, 0], None)
    if character == "flex":
        skin = glb.doc["skins"][0]
        joints = set(skin["joints"])
        for index in skin["joints"]:
            parent = glb.parents.get(index)
            parent_name = nodes[parent]["name"] if parent in joints else "Root"
            bone(nodes[index]["name"], glb.world[index][:3, 3], parent_name)
        face_parent = "Ribbon04"
    else:
        bone("Body", [0, .38 if character == "atlas" else .6, 0])
        bone("Head", [0, 1.30 if character == "atlas" else 1.05, 0], "Body")
        for name in ("LeftArm", "RightArm", "LeftFoot", "RightFoot", "Orbit"):
            if name in names:
                bone(name, glb.world[names[name]][:3, 3], "Body" if "Arm" in name else "Root")
        face_parent = "Head"
    for name in ("LeftEye", "RightEye"):
        index = names[name]
        prim = glb.doc["meshes"][nodes[index]["mesh"]]["primitives"][0]
        p = glb.accessor(prim["attributes"]["POSITION"])
        center = (glb.world[index] @ np.r_[p.mean(axis=0), 1])[:3]
        bone(name, center, face_parent)

    charcoal = np.array([.01444384, .01680737, .02028856] if character == "atlas" else [.01680737, .02028856, .02624122])
    cyan = np.array([0, .309468925, .445201188])
    color_basis = np.column_stack((charcoal, cyan))
    meshes, source_triangles = [], 0
    for index, node in enumerate(nodes):
        if "mesh" not in node:
            continue
        name = node["name"]
        all_points, all_faces, all_colors, all_weights = [], [], [], []
        offset = 0
        for prim in glb.doc["meshes"][node["mesh"]]["primitives"]:
            attrs = prim["attributes"]
            original = glb.accessor(attrs["POSITION"])
            points = (np.c_[original, np.ones(len(original))] @ glb.world[index].T)[:, :3]
            faces = glb.accessor(prim["indices"]).reshape(-1, 3).astype(np.int32)
            source_triangles += len(faces)
            mat = glb.doc["materials"][prim.get("material", 0)]
            rgb = np.tile(np.array(mat.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])[:3], dtype=float), (len(points), 1))
            if "COLOR_0" in attrs:
                rgb *= glb.accessor(attrs["COLOR_0"])[:, :3]
            weights = np.zeros((len(points), len(bones)))
            keys = list(bones)
            if name in ("LeftEye", "RightEye"):
                weights[:, keys.index(name)] = 1
            elif "skin" in node and "JOINTS_0" in attrs:
                source_weights = glb.accessor(attrs["WEIGHTS_0"])
                source_joints = glb.accessor(attrs["JOINTS_0"]).astype(int)
                joint_names = [nodes[j]["name"] for j in glb.doc["skins"][node["skin"]]["joints"]]
                for j, joint_name in enumerate(joint_names):
                    dest = joint_name if character == "flex" else "Body" if joint_name == "Torso" else joint_name
                    original_weight = np.sum(source_weights * (source_joints == j), axis=1)
                    weights[:, keys.index(dest)] += original_weight
            else:
                ancestor = index
                while nodes[ancestor].get("name") not in bones and ancestor in glb.parents:
                    ancestor = glb.parents[ancestor]
                assigned = nodes[ancestor].get("name", "Root")
                if name == "BodyMesh":
                    assigned = "Body"
                elif name == "Smile":
                    assigned = "Head"
                weights[:, keys.index(assigned if assigned in bones else "Root")] = 1
                if character == "pip" and name == "BodyMesh":
                    head_blend = np.clip((points[:, 1] - .78) / .48, 0, 1)
                    weights[:, keys.index("Body")] = 1 - head_blend
                    weights[:, keys.index("Head")] = head_blend
            top = np.argsort(weights, axis=1)[:, -4:]
            limited = np.zeros_like(weights)
            np.put_along_axis(limited, top, np.take_along_axis(weights, top, axis=1), axis=1)
            limited /= np.maximum(limited.sum(axis=1, keepdims=True), 1e-8)
            assert np.allclose(limited.sum(axis=1), 1), (character, name, "unweighted vertices")
            all_points.append(points)
            all_faces.append(faces + offset)
            all_colors.append(rgb)
            all_weights.append(limited)
            offset += len(points)
        p, f, rgb, weights = map(np.concatenate, (all_points, all_faces, all_colors, all_weights))
        welded, inverse = np.unique(np.round(p, 6), axis=0, return_inverse=True)
        f = inverse[f]
        if "CarpetPile" in name:
            reduced, f = reduce_fur(welded, f)
        else:
            target = 9000 if name == "RibbonBody" else 9000 if name == "BodyMesh" and character == "atlas" else 4500 if name == "BodyMesh" else 1600 if name == "OrbitMesh" else 320
            if "Eye" in name or name == "Smile":
                target = 260
            reduced, f = reduce_mesh(welded, f, target)
        distances, nearest = cKDTree(p).query(reduced, k=3)
        influence = 1 / np.maximum(distances, 1e-8)
        influence /= influence.sum(axis=1, keepdims=True)
        rgb = np.sum(rgb[nearest] * influence[:, :, None], axis=1)
        if character == "atlas" and name == "BodyMesh":
            pile_index = names["BodyCarpetPile"]
            pile_points, pile_colors = [], []
            for primitive in glb.doc["meshes"][nodes[pile_index]["mesh"]]["primitives"]:
                vertices_in = glb.accessor(primitive["attributes"]["POSITION"])
                pile_points.append((np.c_[vertices_in, np.ones(len(vertices_in))] @ glb.world[pile_index].T)[:, :3])
                color = glb.doc["materials"][primitive["material"]]["pbrMetallicRoughness"]["baseColorFactor"][:3]
                pile_colors.append(np.tile(color, (len(vertices_in), 1)))
            pile_points, pile_colors = np.concatenate(pile_points), np.concatenate(pile_colors)
            distance, nearby = cKDTree(pile_points).query(reduced, k=20)
            influence_color = 1 / np.maximum(distance, 1e-8)
            influence_color /= influence_color.sum(axis=1, keepdims=True)
            rgb = np.sum(pile_colors[nearby] * influence_color[:, :, None], axis=1)
        weights = np.sum(weights[nearest] * influence[:, :, None], axis=1)
        weights /= weights.sum(axis=1, keepdims=True)
        p = reduced
        mesh_id = uid(character + "/mesh/" + name)
        vertices = {f"v{i}": np.round(point * 16, 6).tolist() for i, point in enumerate(p)}
        faces = {}
        coefficients = np.linalg.lstsq(color_basis, rgb.T, rcond=None)[0].T.clip(0)
        brightness = coefficients.sum(axis=1).clip(.6, 1.4)
        blend = coefficients[:, 1] / np.maximum(coefficients.sum(axis=1), 1e-8)
        vertex_uv = np.column_stack((blend.clip(0, 1) * 255 + .5, (brightness - .6) / .8 * 32 + .5))
        for i, face in enumerate(f):
            v = [f"v{n}" for n in face]
            faces[f"f{i}"] = {"vertices": v, "uv": {k: vertex_uv[n].tolist() for k, n in zip(v, face)}, "texture": 0}
        meshes.append({"type": "mesh", "uuid": mesh_id, "name": name, "origin": [0, 0, 0],
                       "rotation": [0, 0, 0], "shading": "smooth", "vertices": vertices, "faces": faces})
        for j, b in enumerate(bones.values()):
            for i in np.flatnonzero(weights[:, j] > 1e-5):
                b["vertex_weights"][mesh_id[:6] + ":v" + str(i)] = round(float(weights[i, j]), 6)

    ramp = (charcoal[None, :] * (1 - np.linspace(0, 1, 256)[:, None]) + cyan[None, :] * np.linspace(0, 1, 256)[:, None])
    pixels = np.rint(srgb(ramp[None, :, :] * np.linspace(.6, 1.4, 33)[:, None, None]) * 255).astype(np.uint8)
    pixels[16, 255] = [0, 151, 178]
    image = Image.fromarray(pixels)
    image.save(folder / "palette.png")
    packed = io.BytesIO()
    image.save(packed, format="PNG")
    material_id = uid(character + "/material")
    texture = {"uuid": uid(character + "/palette"), "name": character + "_palette", "width": 256, "height": 33,
               "uv_width": 256, "uv_height": 33, "group": material_id, "pbr_channel": "color", "render_sides": "double",
               "source": "data:image/png;base64," + base64.b64encode(packed.getvalue()).decode(), "internal": True}
    roughness = {"atlas": .83, "flex": .54, "pip": .32}[character]
    group = {"uuid": material_id, "name": character + "_material", "is_material": True,
             "material_config": {"color_value": [255, 255, 255, 255], "mer_value": [0, 0, round(roughness * 255)]}}
    armature = {"type": "armature", "uuid": armature_id, "name": character.title() + "Rig", "children": []}
    elements = [armature, *meshes]

    def tree(name):
        children = [n for n, b in bones.items() if b["parent_name"] == name]
        return {"uuid": bones[name]["uuid"], "children": [tree(n) for n in children]}

    for name, b in bones.items():
        b["children"] = [v["uuid"] for v in bones.values() if v["parent_name"] == name]
        saved = {k: v for k, v in b.items() if k != "parent_name"}
        if b["parent_name"]:
            saved["origin"] = (np.array(b["origin"]) - bones[b["parent_name"]]["origin"]).tolist()
        elements.append(saved)
    animations = []
    for clip, duration, loop, context in CLIPS:
        animators = {}
        # Sparse smooth keys are resampled by Blockbench's native glTF exporter.
        times = sorted(set([round(x, 6) for x in np.linspace(0, duration, 25)] + [duration * x for x in (.75, .78, .805)]))
        samples = [pose(character, clip, t, duration) for t in times]
        if character == "flex":
            for sample in samples:
                body, head = sample.pop("Body"), sample.pop("Head")
                sample["Ribbon03"] = body
                sample["Ribbon04"] = {"rotation": [a * .55 + b * .6 for a, b in zip(body["rotation"], head["rotation"])]}
                sample["Ribbon05"] = {"rotation": [a * .3 for a in body["rotation"]]}
        for name, b in bones.items():
            channels = {ch for sample in samples for ch in sample.get(name, {})}
            frames = []
            for channel in channels:
                values = [sample.get(name, {}).get(channel, [1, 1, 1] if channel == "scale" else [0, 0, 0]) for sample in samples]
                default = [1, 1, 1] if channel == "scale" else [0, 0, 0]
                if all(np.allclose(v, default) for v in values):
                    continue
                assert np.allclose(values[0], values[-1]), (character, clip, name, "nonclosing clip")
                frames.extend({"channel": channel, "time": t, "interpolation": "catmullrom",
                               "data_points": [{axis: round(v[i], 6) for i, axis in enumerate("xyz")}]} for t, v in zip(times, values))
            if frames:
                animators[b["uuid"]] = {"name": name, "type": "armature_bone", "keyframes": frames}
        animations.append({"uuid": uid(character + "/animation/" + clip), "name": clip, "loop": "loop" if loop else "once",
                           "length": duration, "snapping": 24, "animators": animators})
    result = {"meta": {"format_version": "5.0", "model_format": "free", "box_uv": False},
              "name": character.title() + " Blockbench", "resolution": {"width": 256, "height": 33},
              "elements": elements, "outliner": [{"uuid": armature_id, "children": [tree("Root"), *[m["uuid"] for m in meshes]]}],
              "textures": [texture], "texture_groups": [group], "animations": animations}
    (folder / (character + ".bbmodel")).write_text(json.dumps(result, separators=(",", ":")))
    triangles = sum(len(m["faces"]) for m in meshes)
    assert triangles <= 50000, (character, triangles)
    manifest = {"character": character, "source": str(source.relative_to(ROOT)), "source_sha256": glb.sha,
                "source_triangles": source_triangles, "triangles": triangles, "bones": len(bones), "texture_size": [256, 33],
                "clips": [{"name": n, "duration": d, "loop": l, "context": c} for n, d, l, c in CLIPS],
                "native_ios_validation": "pending", "roughness": roughness}
    (folder / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(character, source_triangles, "->", triangles, "triangles;", len(bones), "bones; 256x33 color ramp", flush=True)


if __name__ == "__main__":
    for character in SOURCES:
        build(character)
