"""Rebuild Pip with Blender: blender --background --python scripts/build_pip.py."""

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


REPO = Path(__file__).resolve().parents[1]
SOURCE = REPO / "docs/design/models/pip"
RESOURCES = REPO / "ios/GymAndAI/Mascot/Resources"
PREVIEW = REPO / "ios/GymAndAI/Assets.xcassets/PipPreview.imageset"
BODY_PROFILE = [
    (0.00, 0.012, 0.012, 0.00),
    (0.08, 0.32, 0.30, 0.00),
    (0.23, 0.51, 0.43, 0.00),
    (0.43, 0.52, 0.46, -0.025),
    (0.63, 0.40, 0.36, -0.08),
    (0.80, 0.28, 0.27, -0.09),
    (0.91, 0.20, 0.20, -0.015),
    (0.97, 0.13, 0.14, 0.08),
    (1.00, 0.012, 0.012, 0.13),
]
BODY_BASE = 0.23
BODY_HEIGHT = 1.44


def linear_channel(value):
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def material(name, rgb, roughness):
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    color = tuple(linear_channel(channel / 255) for channel in rgb) + (1,)
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = 0
    shader.inputs["Coat Weight"].default_value = 0.40
    shader.inputs["Coat Roughness"].default_value = 0.18
    result.diffuse_color = color
    return result


def group(name, parent=None, location=(0, 0, 0)):
    result = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(result)
    result.parent = parent
    result.location = location
    return result


def finish_mesh(obj, name, surface, parent):
    obj.name = name
    obj.parent = parent
    obj.data.materials.append(surface)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def ellipsoid(name, location, scale, surface, parent):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=20)
    result = finish_mesh(bpy.context.object, name, surface, parent)
    result.location = location
    result.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return result


def smooth_profile(points, fraction):
    segment = min(int(fraction * (len(points) - 1)), len(points) - 2)
    offset = fraction * (len(points) - 1) - segment
    samples = [points[max(0, min(len(points) - 1, segment + step))] for step in (-1, 0, 1, 2)]
    return [
        0.5 * (
            2 * samples[1][axis]
            + (-samples[0][axis] + samples[2][axis]) * offset
            + (2 * samples[0][axis] - 5 * samples[1][axis] + 4 * samples[2][axis] - samples[3][axis]) * offset**2
            + (-samples[0][axis] + 3 * samples[1][axis] - 3 * samples[2][axis] + samples[3][axis]) * offset**3
        )
        for axis in range(4)
    ]


def make_body(surface, parent):
    # Nearly circular cross sections give the curved silhouette real depth.
    rings, sides = 64, 48
    vertices = []
    for ring in range(rings + 1):
        height, width, depth, center = smooth_profile(BODY_PROFILE, ring / rings)
        for side in range(sides):
            angle = 2 * math.pi * side / sides
            vertices.append((center + width * math.cos(angle), depth * math.sin(angle), BODY_BASE + BODY_HEIGHT * height))
    faces = []
    for ring in range(rings):
        for side in range(sides):
            next_side = (side + 1) % sides
            faces.append((ring * sides + side, ring * sides + next_side, (ring + 1) * sides + next_side, (ring + 1) * sides + side))
    faces += [tuple(reversed(range(sides))), tuple(rings * sides + side for side in range(sides))]
    mesh = bpy.data.meshes.new("PipBodyMesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    result = bpy.data.objects.new("BodyMesh", mesh)
    bpy.context.collection.objects.link(result)
    finish_mesh(result, "BodyMesh", surface, parent)


def face_location(horizontal, height):
    lower, upper = 0.0, 1.0
    for _ in range(24):
        fraction = (lower + upper) / 2
        section = smooth_profile(BODY_PROFILE, fraction)
        if BODY_BASE + BODY_HEIGHT * section[0] < height:
            lower = fraction
        else:
            upper = fraction
    _, width, depth, center = section
    front = -depth * math.sqrt(max(0, 1 - ((horizontal - center) / width) ** 2))
    return (horizontal, front - 0.018, height)


def make_smile(surface, parent):
    curve = bpy.data.curves.new("SmileCurve", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.022
    curve.bevel_resolution = 3
    spline = curve.splines.new("POLY")
    spline.points.add(16)
    for index, point in enumerate(spline.points):
        offset = index / 16 * 2 - 1
        point.co = (*face_location(offset * 0.077, 0.89 + 0.035 * offset**2), 1)
    obj = bpy.data.objects.new("Smile", curve)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.data.materials.append(surface)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj.select_set(False)


def make_pip():
    charcoal = material("CharcoalGloss", (35, 39, 45), 0.27)
    turquoise = material("Brand0097B2", (0, 151, 178), 0.22)
    root = group("PipRoot")
    body = group("Body", root)
    make_body(charcoal, body)
    ellipsoid("LeftEye", face_location(-0.19, 1.06), (0.046, 0.035, 0.077), turquoise, body)
    ellipsoid("RightEye", face_location(0.15, 1.06), (0.046, 0.035, 0.077), turquoise, body)
    make_smile(turquoise, body)

    for name, position, angle in (
        ("LeftArm", (-0.46, -0.025, 0.94), -60),
        ("RightArm", (0.43, -0.025, 1.07), 40),
    ):
        pivot = group(name, body, position)
        ellipsoid(name + "Mesh", (0, 0, 0.10), (0.105, 0.115, 0.22), charcoal, pivot)
        pivot.rotation_euler[1] = math.radians(angle)

    for name, position, angle in (
        ("LeftFoot", (-0.23, -0.01, 0.15), -12),
        ("RightFoot", (0.24, 0.01, 0.13), 10),
    ):
        pivot = group(name, root, position)
        ellipsoid(name + "Mesh", (0, -0.085, 0), (0.16, 0.23, 0.115), charcoal, pivot)
        pivot.rotation_euler[1] = math.radians(angle)
        ellipsoid(name + "Leg", (0, 0, 0.10), (0.095, 0.10, 0.12), charcoal, pivot)

    orbit = group("Orbit", root, (0, 0, 0.59))
    orbit.rotation_euler = (math.radians(10), math.radians(-8), 0)
    bpy.ops.mesh.primitive_torus_add(major_segments=64, minor_segments=20, major_radius=0.73, minor_radius=0.095)
    ring = finish_mesh(bpy.context.object, "OrbitMesh", turquoise, orbit)
    ring.location = (0, 0, 0)
    ring.scale.x = 1.09
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return root


def aim(obj, point):
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


def area_light(name, location, energy, size, color):
    bpy.ops.object.light_add(type="AREA", location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.energy = energy
    obj.data.shape = "DISK"
    obj.data.size = size
    obj.data.color = color
    aim(obj, (0, 0, 0.85))


def setup_studio():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.30, 0.34, 0.40, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
    scene.view_settings.view_transform = "AgX"
    area_light("KeySoftbox", (-3, -4, 5), 480, 3, (1.0, 0.95, 0.90))
    area_light("RimSoftbox", (3, 1, 3), 600, 2, (0.80, 0.95, 1.0))
    area_light("FillSoftbox", (2, -3, 2), 180, 2, (0.85, 0.94, 1.0))
    bpy.ops.object.camera_add(location=(2.0, -6, 3.25))
    camera = bpy.context.object
    camera.name = "PreviewCamera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.05
    aim(camera, (0, 0, 0.88))
    scene.camera = camera


def export_environment():
    # A compact studio reflection map, generated rather than downloaded.
    width, height = 512, 256
    pixels = []
    for row in range(height):
        vertical = row / height
        for column in range(width):
            horizontal = column / width
            panels = sum(
                strength * math.exp(-((horizontal - center) / spread) ** 8 - ((vertical - 0.45) / 0.19) ** 8)
                for center, spread, strength in ((0.12, 0.08, 2), (0.58, 0.09, 1.4), (0.82, 0.065, 2.5))
            )
            base = 0.18 + 0.10 * (1 - vertical)
            pixels.extend((base + panels, base + panels, base + panels, 1))
    image = bpy.data.images.new("PipStudio", width=width, height=height, float_buffer=True)
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(RESOURCES / "PipStudio.hdr")
    image.file_format = "HDR"
    image.save()


def export_model(root):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [root, *root.children_recursive]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.wm.usd_export(
        filepath=str(RESOURCES / "Pip.usdz"),
        selected_objects_only=True,
        export_materials=True,
        convert_orientation=True,
        generate_preview_surface=True,
        export_cameras=False,
        export_lights=False,
    )
    triangle_count = sum(len(obj.data.polygons) * 2 for obj in root.children_recursive if obj.type == "MESH")
    print(f"Pip exported: approximately {triangle_count:,} triangles")


def main():
    bpy.context.preferences.filepaths.save_version = 0
    for folder in (SOURCE, RESOURCES, PREVIEW):
        folder.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    root = make_pip()
    setup_studio()
    export_model(root)
    export_environment()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "pip.blend"))
    bpy.context.scene.render.filepath = str(PREVIEW / "pip-preview.png")
    bpy.ops.render.render(write_still=True)
    (PREVIEW / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "pip-preview.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    catalog = PREVIEW.parent / "Contents.json"
    if not catalog.exists():
        catalog.write_text('{"info":{"author":"xcode","version":1}}\n')


if __name__ == "__main__":
    main()
