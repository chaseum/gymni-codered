"""Author mobile companion rigs/clips in Blender; invoked through Blender MCP.

Original artist files are read only. Outputs live in blender-companions/animated.
"""
import json
import math
import random
import struct
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

BASE = Path(__file__).resolve().parents[1] / 'blender-companions'
OUT = BASE / "animated"
FPS = 30
CLIPS = [
    ("idle", 2.4, True, "Reusable float / idle: Today, waiting, listening and active workout"),
    ("encouraging", 2, False, "Coaching, encouragement and gentle form guidance"),
    ("celebration", 2.4, False, "Set or workout completion and verified achievements"),
    ("rest", 3, True, "Reusable sleep / rest: recovery, pause and inactive companion"),
    ("happy", 2, False, "Positive acknowledgement, improved form and successful rep feedback"),
    ("sad", 2.4, False, "Gentle empathy for user-reported disappointment; never shame form or performance"),
]


def select(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def triangles(obj):
    mesh = obj.data
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def thin_carpet(obj, fraction=0.25):
    """Keep whole randomly distributed strands, never broken fur fragments."""
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    visited = set()
    rng = random.Random(71)
    remove = []
    for seed in mesh.verts:
        if seed in visited:
            continue
        component = []
        queue = [seed]
        visited.add(seed)
        while queue:
            vertex = queue.pop()
            component.append(vertex)
            for edge in vertex.link_edges:
                other = edge.other_vert(vertex)
                if other not in visited:
                    visited.add(other)
                    queue.append(other)
        if rng.random() > fraction:
            remove.extend(component)
    bmesh.ops.delete(mesh, geom=remove, context="VERTS")
    mesh.to_mesh(obj.data)
    mesh.free()


def optimize(name):
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            continue
        select(obj)
        for modifier in list(obj.modifiers):
            if modifier.type == "SUBSURF":
                obj.modifiers.remove(modifier)
        if "CarpetPile" in obj.name:
            thin_carpet(obj)
        if 'CarpetPile' in obj.name:
            budget = 14000 if obj.name.startswith('Body') else 2000 if 'Foot' in obj.name else 2400
        else:
            budget = 14000 if obj.name == "RibbonBody" else 8500 if obj.name == "BodyMesh" else 1500
        if triangles(obj) > budget:
            modifier = obj.modifiers.new("Mobile silhouette budget", "DECIMATE")
            modifier.ratio = budget / triangles(obj)
            modifier.use_collapse_triangulate = True
            if obj.modifiers[0] != modifier:
                bpy.ops.object.modifier_move_up(modifier=modifier.name)
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    count = sum(triangles(o) for o in bpy.context.scene.objects if o.type == "MESH")
    assert count < 45000, (name, count)
    return count


def consolidate_atlas_materials():
    """Retain the artist's colour gradient without dozens of material batches."""
    for role in ('Carpet', 'Body'):
        objects = [o for o in bpy.context.scene.objects if o.type == 'MESH'
                   and (('CarpetPile' in o.name) if role == 'Carpet' else o.name.endswith('Mesh'))]
        material = bpy.data.materials.new('AtlasMobile' + role)
        material.use_nodes = True
        shader = material.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value = (1, 1, 1, 1)
        shader.inputs['Roughness'].default_value = .88 if role == 'Carpet' else .75
        color = material.node_tree.nodes.new('ShaderNodeVertexColor')
        color.layer_name = 'CompanionColour'
        material.node_tree.links.new(color.outputs['Color'], shader.inputs['Base Color'])
        for obj in objects:
            colors = obj.data.color_attributes.new(name='CompanionColour', type='FLOAT_COLOR', domain='POINT')
            sums = [[0, 0, 0, 0] for _ in obj.data.vertices]
            counts = [0 for _ in obj.data.vertices]
            for polygon in obj.data.polygons:
                old = obj.data.materials[polygon.material_index]
                rgba = old.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value
                for index in polygon.vertices:
                    sums[index] = [a + b for a, b in zip(sums[index], rgba)]
                    counts[index] += 1
                polygon.material_index = 0
            for index, values in enumerate(sums):
                colors.data[index].color = [v / max(counts[index], 1) for v in values]
            obj.data.materials.clear()
            obj.data.materials.append(material)
            obj.data.color_attributes.active_color = colors


def rigid_bind(obj, rig, bone):
    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.matrix_world = world
    obj.vertex_groups.clear()
    obj.vertex_groups.new(name=bone).add(list(range(len(obj.data.vertices))), 1, "REPLACE")
    for modifier in list(obj.modifiers):
        if modifier.type == "ARMATURE":
            obj.modifiers.remove(modifier)
    modifier = obj.modifiers.new("Companion skeleton", "ARMATURE")
    modifier.object = rig


def make_rig(name):
    root = bpy.data.objects[name.capitalize() + "Root"]
    rig = next((o for o in root.children_recursive if o.type == "ARMATURE"), None)
    if rig is None:
        rig = bpy.data.objects.new("PipAnimationRig", bpy.data.armatures.new("PipAnimationSkeleton"))
        bpy.context.collection.objects.link(rig)
        rig.parent = root
    select(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    bones = rig.data.edit_bones
    motion = bones.new("Motion")
    motion.head, motion.tail = (0, 0, 0), (0, 0, .2)
    for bone in bones:
        if bone != motion and bone.parent is None:
            bone.parent = motion
    if name == "pip":
        torso = bones.new("Torso")
        torso.head, torso.tail, torso.parent = (0, 0, .25), (0, 0, 1.2), motion
    if name != "flex":
        for part in ("LeftArm", "RightArm", "LeftFoot", "RightFoot", "Orbit"):
            pivot = bpy.data.objects.get(part)
            if pivot is None:
                continue
            bone = bones.new(part)
            bone.head = rig.matrix_world.inverted() @ pivot.matrix_world.translation
            bone.tail = bone.head + Vector((0, 0, .22))
            bone.parent = bones["Torso"] if "Arm" in part else motion
    smile = bpy.data.objects['Smile']
    center = sum((v.co for v in smile.data.vertices), Vector()) / len(smile.data.vertices)
    center = rig.matrix_world.inverted() @ smile.matrix_world @ center
    for part, x in (('Smile', 0), ('MouthLeft', -.08), ('MouthRight', .08)):
        bone = bones.new(part)
        bone.head = center + Vector((x, 0, 0))
        bone.tail = bone.head + Vector((0, 0, .08))
        bone.parent = bones['Smile'] if x else bones['Ribbon04'] if name == 'flex' else bones.get('Head', bones['Torso'])
    for part in ("LeftEye", "RightEye"):
        obj = bpy.data.objects[part]
        bone = bones.new(part)
        # Face origins are at the capsule centers, preserving a small blink scale.
        bone.head = rig.matrix_world.inverted() @ obj.matrix_world.translation
        bone.tail = bone.head + Vector((0, 0, .08))
        bone.parent = bones["Ribbon04"] if name == "flex" else bones.get("Head", bones["Torso"])
    bpy.ops.object.mode_set(mode="OBJECT")
    for obj in list(root.children_recursive):
        if obj.type != "MESH":
            continue
        if obj.name == 'Smile':
            rigid_bind(obj, rig, 'Smile')
            left = obj.vertex_groups.new(name='MouthLeft')
            right = obj.vertex_groups.new(name='MouthRight')
            xs = [v.co.x for v in obj.data.vertices]
            low, high = min(xs), max(xs)
            for vertex in obj.data.vertices:
                u = (vertex.co.x - low) / (high - low)
                lw, rw = max(0, 1 - 2 * u) ** 1.5, max(0, 2 * u - 1) ** 1.5
                left.add([vertex.index], lw, 'REPLACE')
                right.add([vertex.index], rw, 'REPLACE')
                obj.vertex_groups['Smile'].add([vertex.index], 1 - lw - rw, 'REPLACE')
        elif obj.name in ("LeftEye", "RightEye"):
            rigid_bind(obj, rig, obj.name)
        elif name == "pip":
            parent = obj.parent
            while parent and parent.name not in rig.data.bones:
                parent = parent.parent
            rigid_bind(obj, rig, parent.name if parent else "Torso")
        elif name == "atlas" and not any(m.type == "ARMATURE" for m in obj.modifiers):
            rigid_bind(obj, rig, obj.parent.name)
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
    return root, rig


def pose(name, clip, u, rig):
    for b in rig.pose.bones:
        b.location = (0, 0, 0)
        b.rotation_euler = (0, 0, 0)
        b.scale = (1, 1, 1)
    # One shots settle with zero velocity/acceleration; loops share their tangents.
    envelope = math.sin(math.pi * u) ** 4
    wave = math.sin(2 * math.pi * u)
    soft = (1 - math.cos(2 * math.pi * u)) / 2
    material = {"atlas": .55, "flex": 1.15, "pip": .9}[name]
    lift = sway = nod = gesture = stretch = mouth = 0.0
    blink = 1.0
    if clip == "idle":
        lift = (.055 if name == "atlas" else .105) * soft
        sway, stretch = .035 * wave, .01 * soft
    elif clip == "encouraging":
        gesture = -.28 * envelope
        nod = .06 * math.sin(2 * math.pi * u) * envelope
        sway, stretch = .025 * wave * envelope, .018 * envelope
        mouth = .012 * envelope
    elif clip == "celebration":
        lift = .14 * math.sin(2 * math.pi * u) ** 2 * envelope
        gesture = -.48 * envelope
        sway = .07 * wave * envelope
        stretch = -.035 * math.cos(4 * math.pi * u) * envelope
        mouth, blink = .018 * envelope, 1 - .25 * envelope
    elif clip == "rest":
        stretch, nod = .012 * soft, .035
        gesture, blink = .04, .14
    elif clip == "happy":
        lift, stretch, gesture = .05 * envelope, .02 * envelope, -.14 * envelope
        nod, mouth, blink = -.035 * envelope, .018 * envelope, 1 + .1 * envelope
    elif clip == "sad":
        stretch, nod, gesture = -.025 * envelope, .085 * envelope, .08 * envelope
        mouth, blink = -.075 * envelope, 1 - .45 * envelope
    else:
        raise ValueError(clip)
    motion = rig.pose.bones["Motion"]
    # Bone local Y is Blender world Z for the vertical Motion bone.
    motion.location.y = lift * material
    motion.rotation_euler.z = sway * material
    torso = rig.pose.bones.get("Torso")
    if torso:
        torso.scale = (1 - stretch * material * .5, 1 + stretch * material, 1 - stretch * material * .5)
        torso.rotation_euler.x = nod * .55
        head = rig.pose.bones.get("Head")
        if head:
            head.rotation_euler.x = nod * .45
        for side, sign in (("RightArm", 1), ("LeftArm", -1)):
            rig.pose.bones[side].rotation_euler.z = sign * gesture * material
            rig.pose.bones[side].rotation_euler.x = gesture * .2
    else:
        # A continuous ribbon: counterbend the two sides to keep the open arch.
        for part, sign in (("Ribbon03", 1), ("Ribbon06", -1)):
            rig.pose.bones[part].rotation_euler.z = stretch * sign * 1.2
        rig.pose.bones["Ribbon04"].rotation_euler.x = nod * .5
        rig.pose.bones["HandRight"].rotation_euler.z = gesture * .8
        rig.pose.bones["HandLeft"].rotation_euler.z = -gesture * .5
    if name == "pip":
        orbit = rig.pose.bones["Orbit"]
        orbit.rotation_euler.x = .045 * wave
        orbit.rotation_euler.y = .09 * wave
    # Blinks are small skeletal scale changes, without morph targets or textures.
    if clip not in ("rest", "sad"):
        blink *= 1 - .9 * math.exp(-((u - .72) / .035) ** 2) * math.sin(math.pi * u) ** 2
    for part in ("LeftEye", "RightEye"):
        rig.pose.bones[part].scale.y = blink
    for part in ("MouthLeft", "MouthRight"):
        rig.pose.bones[part].location.y = mouth


def author(name, rig):
    rig.animation_data_clear()
    rig.animation_data_create()
    manifest = []
    cursor = 1
    for clip, seconds, loop, context in CLIPS:
        length = round(seconds * FPS)
        action = bpy.data.actions.new(clip)
        action.use_fake_user = True
        rig.animation_data.action = action
        frames = range(length + 1)
        for frame in frames:
            pose(name, clip, frame / length, rig)
            for bone in rig.pose.bones:
                for path in ("location", "rotation_euler", "scale"):
                    bone.keyframe_insert(data_path=path, frame=frame)
        track = rig.animation_data.nla_tracks.new()
        track.name = clip
        strip = track.strips.new(clip, cursor, action)
        strip.action_frame_start, strip.action_frame_end = 0, length
        strip.extrapolation = "NOTHING"
        strip.blend_type = "REPLACE"
        manifest.append({"name": clip, "duration": length / FPS, "loop": loop,
                         "start_frame": cursor, "end_frame": cursor + length,
                         "trim_start": (cursor - 1) / FPS, "trim_end": (cursor + length - 1) / FPS,
                         "context": context})
        cursor += length + 1
    rig.animation_data.action = None
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = 1, cursor - 1
    bpy.context.scene.render.fps = FPS
    return manifest


def validate_glb(path, manifest):
    data = path.read_bytes()
    assert data[:4] == b"glTF"
    length, chunk = struct.unpack_from("<II", data, 12)
    assert chunk == 0x4E4F534A
    doc = json.loads(data[20:20 + length])
    names = [a["name"] for a in doc.get("animations", [])]
    assert sorted(names) == sorted(c["name"] for c in manifest), names
    assert doc.get("skins"), "Missing mobile skeleton"
    assert all(a.get("channels") for a in doc["animations"])
    assert not doc.get("cameras")
    assert len(data) < 4_000_000, len(data)
    return {"bytes": len(data), "animations": len(names), "skins": len(doc["skins"])}


def build(name):
    source = {"pip": "pip-refined", "atlas": "atlas-mobile", "flex": "flex"}[name]
    bpy.ops.wm.open_mainfile(filepath=str(BASE / name / (source + ".blend")))
    if name == 'atlas':
        consolidate_atlas_materials()
    count = optimize(name)
    root, rig = make_rig(name)
    manifest = author(name, rig)
    folder = OUT / name
    folder.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(folder / (name + "-animated.blend")), compress=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [root, *root.children_recursive]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    glb = folder / (name + "-animated.glb")
    bpy.ops.export_scene.gltf(filepath=str(glb), use_selection=True, export_format="GLB",
                             export_animation_mode="NLA_TRACKS", export_anim_slide_to_zero=True,
                             export_optimize_animation_size=True, export_skins=True,
                             export_cameras=False, export_lights=False)
    metrics = validate_glb(glb, manifest)
    usd = folder / (name + "-animated.usdz")
    bpy.ops.wm.usd_export(filepath=str(usd), selected_objects_only=True, export_animation=True,
                          export_armatures=True, export_shapekeys=False, export_materials=True,
                          convert_orientation=True, export_cameras=False, export_lights=False)
    assert usd.stat().st_size < 8_000_000, (name, usd.stat().st_size)
    report = {"character": name, "source": str(BASE / name / (source + ".blend")),
              "triangles": count, "bones": len(rig.data.bones), "fps": FPS,
              "glb": metrics, "usdz_bytes": usd.stat().st_size, "clips": manifest,
              "ios_device_validation": "pending", "reduce_motion": "Use neutral frame; stop playback"}
    (folder / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    reports = [build(name) for name in ("pip", "atlas", "flex")]
    (OUT / "manifest.json").write_text(json.dumps(reports, indent=2) + "\n")
    return {r["character"]: {k: r[k] for k in ("triangles", "bones", "glb", "usdz_bytes")} for r in reports}


if __name__ == "__main__":
    print(json.dumps(main(), indent=2))
