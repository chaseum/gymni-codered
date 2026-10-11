"""Connect exported colour primvars to USD Preview Surface (Blender omits them)."""
import json
import gzip
from pathlib import Path
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdSkel, UsdUtils

BASE = Path(__file__).resolve().parents[1] / 'blender-companions' / 'animated'


def main():
    reports = []
    for name in ('pip', 'atlas', 'flex'):
        folder = BASE / name
        path = folder / (name + '-animated.usdz')
        manifest_path = folder / 'manifest.json'
        report = json.loads(manifest_path.read_text())
        stage = Usd.Stage.Open(str(path))
        animation = next(UsdSkel.Animation(p) for p in stage.Traverse() if p.IsA(UsdSkel.Animation))
        with gzip.open(BASE / 'skeleton-samples' / (name + '.json.gz'), 'rt') as stream:
            sampled = json.load(stream)
        names = [str(j).split('/')[-1] for j in animation.GetJointsAttr().Get()]
        assert set(names) == set(sampled['joints'])
        order = [sampled['joints'].index(j) for j in names]
        attrs = (animation.GetTranslationsAttr(), animation.GetRotationsAttr(), animation.GetScalesAttr())
        for attr in attrs:
            attr.Clear()
        # Blender's sparse USD scale samples interpolate across clip boundaries.
        # Explicit joint samples preserve the authored timing without baking meshes.
        frames = set(range(sampled['start_frame'], len(sampled['samples']) + sampled['start_frame']))
        frames.update(f for clip in report['clips'] for f in (clip['start_frame'], clip['end_frame']))
        for frame in sorted(frames):
            raw = sampled['samples'][frame - sampled['start_frame']]
            rows = [raw[i] for i in order]
            values = ([Gf.Vec3f(*r[:3]) for r in rows],
                      [Gf.Quatf(r[3], Gf.Vec3f(*r[4:7])) for r in rows],
                      [Gf.Vec3h(*r[7:10]) for r in rows])
            for attr, value in zip(attrs, values):
                if frame == sampled['start_frame']:
                    attr.Set(value)
                attr.Set(value, frame)
        connected = set()
        for prim in stage.Traverse():
            if not prim.IsA(UsdGeom.Mesh):
                continue
            variables = UsdGeom.PrimvarsAPI(prim)
            color = next((key for key in ('CompanionColour', 'RubberColour') if variables.HasPrimvar(key)), None)
            if color is None:
                continue
            material, _ = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()
            shader = material.ComputeSurfaceSource()[0]
            assert shader and shader.GetIdAttr().Get() == 'UsdPreviewSurface'
            reader = UsdShade.Shader.Define(stage, material.GetPath().AppendChild('MobileColour'))
            reader.CreateIdAttr('UsdPrimvarReader_float3')
            reader.CreateInput('varname', Sdf.ValueTypeNames.Token).Set(color)
            reader.CreateOutput('result', Sdf.ValueTypeNames.Float3)
            shader.GetInput('diffuseColor').ConnectToSource(reader.ConnectableAPI(), 'result')
            connected.add(str(material.GetPath()))
        if name != 'pip':
            assert connected, (name, 'Missing preserved surface colours')
        temporary = folder / (name + '-packaging.usdc')
        stage.GetRootLayer().Export(str(temporary))
        packed = folder / (name + '-packaging.usdz')
        assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(temporary)), str(packed))
        packed.replace(path)
        temporary.unlink()
        report['usdz_bytes'] = path.stat().st_size
        report['usd_colour_bindings'] = sorted(connected)
        report['usd_joint_samples'] = len(frames)
        report['usd_sample_rate'] = 30
        manifest_path.write_text(json.dumps(report, indent=2) + '\n')
        reports.append(report)
    (BASE / 'manifest.json').write_text(json.dumps(reports, indent=2) + '\n')
    print(json.dumps({r['character']: r['usdz_bytes'] for r in reports}))


if __name__ == '__main__':
    main()
