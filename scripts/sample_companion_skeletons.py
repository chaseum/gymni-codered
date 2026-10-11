import bpy
import json
import gzip
from pathlib import Path

base = Path(__file__).resolve().parents[1] / 'blender-companions' / 'animated'
output = base / 'skeleton-samples'
output.mkdir(exist_ok=True)
report = {}
for name in ('pip', 'atlas', 'flex'):
    bpy.ops.wm.open_mainfile(filepath=str(base / name / (name + '-animated.blend')))
    rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    joints = [b.name for b in rig.pose.bones]
    samples = []
    for frame in range(bpy.context.scene.frame_start, bpy.context.scene.frame_end + 1):
        bpy.context.scene.frame_set(frame)
        values = []
        for b in rig.pose.bones:
            matrix = b.parent.matrix.inverted_safe() @ b.matrix if b.parent else b.matrix
            t, q, s = matrix.decompose()
            values.append([*t, q.w, q.x, q.y, q.z, *s])
        samples.append(values)
    data = {'joints': joints, 'start_frame': 1, 'samples': samples}
    with gzip.open(output / (name + '.json.gz'), 'wt', encoding='utf-8') as stream:
        json.dump(data, stream)
    report[name] = {'frames': len(samples), 'joints': len(joints), 'mid_idle': samples[60][0:2]}
result = report
