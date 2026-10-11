"""Replace vertex-colour materials in companion USDZs with plain per-tone materials.

Atlas and Flex colour their bodies through a `UsdPrimvarReader_float3` on a white base colour. RealityKit builds
that shader graph asynchronously, so the first time a companion appears it renders the white fallback (grey on
screen) until the scene is rebuilt. This script groups each such material's vertex colours into a few tones,
assigns every triangle to its nearest tone through `materialBind` GeomSubsets, and gives each tone a constant-
colour copy of the material, so no primvar reader is left. Meshes, skeletons and animations are untouched.

Run after re-exporting companions (needs only macOS's usdcat/usdzip):
    python3 scripts/bake_companion_vertex_colours.py ios/GymAndAI/Mascot/Resources/{Atlas,Flex}Animated.usdz
"""
import collections
import re
import subprocess
import sys
import tempfile
from pathlib import Path

MIN_TONE_SHARE = 0.05  # a colour must cover 5% of a material's vertices to become its own tone


def block_end(text: str, start: int) -> int:
    """Index just past the `}` closing the first `{` at or after `start`."""
    depth, i = 0, text.index("{", start)
    while True:
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        i += 1
        if depth == 0:
            return i


def array(body: str, name: str, pattern: str) -> list:
    match = re.search(rf"\b{re.escape(name)} = \[([^\]]*)\]", body)
    return re.findall(pattern, match.group(1)) if match else []


def bake(usda: str) -> tuple[str, list[str]]:
    report = []
    # Materials whose diffuse colour comes from a primvar reader: material name -> primvar name.
    readers = {}
    for m in re.finditer(r'def Material "(\w+)"', usda):
        material = usda[m.start():block_end(usda, m.start())]
        varname = re.search(r'info:id = "UsdPrimvarReader_float3"\s*token inputs:varname = "(\w+)"', material)
        if varname and "inputs:diffuseColor.connect" in material:
            readers[m.group(1)] = varname.group(1)
    if not readers:
        return usda, ["no vertex-colour materials; already baked"]

    meshes = []  # (start, end, material, face colours)
    for m in re.finditer(r'def Mesh "(\w+)"', usda):
        start, end = m.start(), block_end(usda, m.start())
        body = usda[start:end]
        binding = re.search(r"rel material:binding = </root/_materials/(\w+)>", body)
        if not binding or binding.group(1) not in readers:
            continue
        primvar = readers[binding.group(1)]
        colours = [tuple(float(x) for x in c.split(",")[:3])
                   for c in array(body, f"primvars:{primvar}", r"\(([^()]*)\)")]
        assert re.search(rf'primvars:{primvar} = \[[^\]]*\] \(\s*interpolation = "vertex"', body), "vertex colours only"
        counts = [int(c) for c in array(body, "faceVertexCounts", r"-?\d+")]
        indices = [int(i) for i in array(body, "faceVertexIndices", r"-?\d+")]
        faces, cursor = [], 0
        for n in counts:
            corner = [colours[i] for i in indices[cursor:cursor + n]]
            faces.append(tuple(sum(c[k] for c in corner) / n for k in range(3)))
            cursor += n
        meshes.append((start, end, binding.group(1), faces, colours))

    # Tones per material: frequent rounded colours, averaged from the vertices that round to them.
    tones = {}
    for material in {mesh[2] for mesh in meshes}:
        vertices = [c for mesh in meshes if mesh[2] == material for c in mesh[4]]
        buckets = collections.defaultdict(list)
        for c in vertices:
            buckets[tuple(round(x, 2) for x in c)].append(c)
        frequent = [members for members in buckets.values() if len(members) >= MIN_TONE_SHARE * len(vertices)]
        tones[material] = [tuple(sum(c[k] for c in members) / len(members) for k in range(3)) for members in frequent]

    def nearest(material, colour):
        return min(range(len(tones[material])),
                   key=lambda t: sum((a - b) ** 2 for a, b in zip(tones[material][t], colour)))

    used = collections.defaultdict(set)
    for start, end, material, faces, _ in sorted(meshes, reverse=True):  # back to front keeps offsets valid
        groups = collections.defaultdict(list)
        for index, colour in enumerate(faces):
            groups[nearest(material, colour)].append(index)
        subsets = "".join(
            f'\n                    def GeomSubset "Tone{tone}" (\n'
            f'                        prepend apiSchemas = ["MaterialBindingAPI"]\n'
            f'                    )\n                    {{\n'
            f'                        uniform token elementType = "face"\n'
            f'                        uniform token familyName = "materialBind"\n'
            f'                        int[] indices = [{", ".join(map(str, faces_in_tone))}]\n'
            f'                        rel material:binding = </root/_materials/{material}Tone{tone}>\n'
            f'                    }}\n'
            for tone, faces_in_tone in sorted(groups.items()))
        used[material] |= set(groups)
        close = usda.rindex("}", start, end)
        usda = (usda[:close] + '                    uniform token subsetFamily:materialBind:familyType = "partition"\n'
                + subsets + usda[close:])
        report.append(f"{material}: mesh split into {len(groups)} tones")

    for material, primvar in readers.items():
        m = re.search(rf'def Material "{material}"', usda)
        start, end = m.start(), block_end(usda, m.start())
        original = usda[start:end]
        copies = []
        for tone in sorted(used[material]):
            r, g, b = tones[material][tone]
            copy = original.replace(f'def Material "{material}"', f'def Material "{material}Tone{tone}"')
            copy = copy.replace(f"/root/_materials/{material}/", f"/root/_materials/{material}Tone{tone}/")
            copy = re.sub(r"\n\s*color3f inputs:diffuseColor\.connect = <[^>]*>", "", copy)
            copy = re.sub(r"color3f inputs:diffuseColor = \([^)]*\)", f"color3f inputs:diffuseColor = ({r:.6f}, {g:.6f}, {b:.6f})", copy)
            reader = re.search(r'\n\s*def Shader "\w+"\s*\{\s*uniform token info:id = "UsdPrimvarReader_float3"', copy)
            copy = copy[:reader.start()] + copy[block_end(copy, reader.start()):]
            copies.append(copy)
        # The mesh-level binding is fully covered by the subsets; make it plain too so no reader is ever built.
        r, g, b = tones[material][0]
        plain = re.sub(r"\n\s*color3f inputs:diffuseColor\.connect = <[^>]*>", "", original)
        plain = re.sub(r"color3f inputs:diffuseColor = \([^)]*\)", f"color3f inputs:diffuseColor = ({r:.6f}, {g:.6f}, {b:.6f})", plain)
        reader = re.search(r'\n\s*def Shader "\w+"\s*\{\s*uniform token info:id = "UsdPrimvarReader_float3"', plain)
        plain = plain[:reader.start()] + plain[block_end(plain, reader.start()):]
        usda = usda[:start] + plain + "".join("\n\n        " + c for c in copies) + usda[end:]
    return usda, report


def main(paths):
    for path in map(Path, paths):
        with tempfile.TemporaryDirectory() as tmp:
            layer = subprocess.run(["unzip", "-Z1", path], check=True, capture_output=True, text=True).stdout.split()[0]
            source = Path(tmp) / "source.usda"
            subprocess.run(["usdcat", path, "-o", source], check=True)
            usda, report = bake(source.read_text())
            if usda == source.read_text():
                print(f"{path.name}: {report[0]}")
                continue
            (Path(tmp) / "baked.usda").write_text(usda)
            subprocess.run(["usdcat", Path(tmp) / "baked.usda", "-o", Path(tmp) / layer], check=True)
            out = Path(tmp) / "out.usdz"
            subprocess.run(["usdzip", out, layer], check=True, cwd=tmp)
            out.replace(path)
        print(f"{path.name}: " + "; ".join(report))


if __name__ == "__main__":
    main(sys.argv[1:])
