"""Assert export integrity and budgets. Requires usd-core in the tooling venv."""
import json
import math
import struct
from pathlib import Path
from pxr import Usd, UsdGeom, UsdSkel, UsdShade

BASE = Path(__file__).resolve().parents[1] / 'blender-companions' / 'animated'


def components(array):
    values = []
    for item in array:
        if hasattr(item, 'GetReal'):
            values.extend([item.GetReal(), *item.GetImaginary()])
        else:
            values.extend(item)
    return values


def read_glb(path):
    data = path.read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    doc = json.loads(data[20:20 + length])
    binary = data[28 + length:]

    def accessor(index):
        entry = doc['accessors'][index]
        view = doc['bufferViews'][entry['bufferView']]
        assert entry['componentType'] == 5126
        width = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[entry['type']]
        offset = view.get('byteOffset', 0) + entry.get('byteOffset', 0)
        stride = view.get('byteStride', width * 4)
        return [struct.unpack_from('<' + 'f' * width, binary, offset + i * stride)
                for i in range(entry['count'])]
    return doc, accessor


def main():
    (BASE / 'validation.json').unlink(missing_ok=True)
    reports = []
    for name in ('pip', 'atlas', 'flex'):
        folder = BASE / name
        manifest = json.loads((folder / 'manifest.json').read_text())
        doc, values = read_glb(folder / (name + '-animated.glb'))
        expected = {c['name']: c for c in manifest['clips']}
        assert set(expected) == {'idle', 'encouraging', 'celebration', 'rest', 'happy', 'sad'}
        assert len(doc['animations']) == len(expected) == 6
        moved = []
        for animation in doc['animations']:
            clip = expected[animation['name']]
            has_motion = False
            for sampler in animation['samplers']:
                times = [v[0] for v in values(sampler['input'])]
                samples = values(sampler['output'])
                assert abs(times[0]) < .001, (name, clip['name'], times[0])
                assert abs(times[-1] - clip['duration']) < .04, (name, clip['name'], times[-1])
                assert all(math.isfinite(v) for row in samples for v in row)
                assert all(abs(a - b) < .002 for a, b in zip(samples[0], samples[-1])), (name, clip['name'], 'endpoint mismatch')
                has_motion |= any(any(abs(a - b) > .0001 for a, b in zip(samples[0], row)) for row in samples)
            assert has_motion, (name, clip['name'], 'static animation')
            moved.append(clip['name'])
        stage = Usd.Stage.Open(str(folder / (name + '-animated.usdz')))
        assert stage
        assert UsdGeom.GetStageUpAxis(stage) == 'Y'
        skeletons = [p for p in stage.Traverse() if p.IsA(UsdSkel.Skeleton)]
        animations = [p for p in stage.Traverse() if p.IsA(UsdSkel.Animation)]
        assert len(skeletons) == len(animations) == 1
        skel = UsdSkel.Skeleton(skeletons[0])
        joints = skel.GetJointsAttr().Get()
        assert len(joints) == manifest['bones']
        animation = UsdSkel.Animation(animations[0])
        times = sorted({t for attribute in (animation.GetTranslationsAttr(), animation.GetRotationsAttr(), animation.GetScalesAttr())
                        for t in attribute.GetTimeSamples()})
        assert len(times) > 100
        assert times[0] <= 1 and times[-1] >= manifest['clips'][-1]['end_frame']
        for attr in (animation.GetTranslationsAttr(), animation.GetRotationsAttr(), animation.GetScalesAttr()):
            for clip in manifest['clips']:
                first = components(attr.Get(clip['start_frame']))
                last = components(attr.Get(clip['end_frame']))
                assert all(abs(a - b) < .002 for a, b in zip(first, last)), (name, clip['name'], attr.GetName(), 'USD endpoint mismatch')
                if not clip['loop']:
                    assert all(abs(a - b) < .002 for a, b in zip(components(attr.Get()), first)), (name, clip['name'], 'non-neutral one shot')
        meshes = [UsdGeom.Mesh(p) for p in stage.Traverse() if p.IsA(UsdGeom.Mesh)]
        for mesh in meshes:
            assert not mesh.GetPointsAttr().GetTimeSamples(), (name, mesh.GetPath(), 'baked mesh frames')
            binding = UsdSkel.BindingAPI(mesh.GetPrim())
            indices = binding.GetJointIndicesPrimvar()
            weights = binding.GetJointWeightsPrimvar()
            assert indices and weights, (name, mesh.GetPath(), 'unbound mesh')
            assert max(indices.Get()) < len(joints)
            width = weights.GetElementSize()
            numbers = weights.Get()
            assert all(abs(sum(numbers[i:i + width]) - 1) < .002 for i in range(0, len(numbers), width))
            color = next((key for key in ('CompanionColour', 'RubberColour')
                          if UsdGeom.PrimvarsAPI(mesh).HasPrimvar(key)), None)
            if color:
                material, _ = UsdShade.MaterialBindingAPI(mesh.GetPrim()).ComputeBoundMaterial()
                source = material.ComputeSurfaceSource()[0].GetInput('diffuseColor').GetConnectedSource()
                assert source and UsdShade.Shader(source[0].GetPrim()).GetIdAttr().Get() == 'UsdPrimvarReader_float3'
                assert UsdShade.Shader(source[0].GetPrim()).GetInput('varname').Get() == color
        materials = [p for p in stage.Traverse() if p.IsA(UsdShade.Material)]
        assert len(materials) <= 6, (name, 'excess material batches', len(materials))
        assert manifest['usd_sample_rate'] == 30
        assert len(times) == stage.GetEndTimeCode() - stage.GetStartTimeCode() + 1
        reports.append({'character': name, 'clips_checked': len(moved), 'matching_endpoints': True,
                        'all_clips_move': True, 'usd_skeletons': len(skeletons),
                        'usd_meshes': len(meshes), 'baked_mesh_frames': False,
                        'usd_matching_endpoints': True, 'materials': len(materials),
                        'usd_animation_samples': len(times), 'usdz_bytes': manifest['usdz_bytes']})
    total = sum(r['usdz_bytes'] for r in reports)
    assert total < 6_000_000, total
    result = {'passed': True, 'total_usdz_bytes': total, 'characters': reports,
              'native_ios': 'Not verified on Windows; requires RealityKit/device check'}
    (BASE / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
