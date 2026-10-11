"""Read-only acceptance checks for the Blockbench delivery."""
import base64
import hashlib
import io
import json
import zipfile

import numpy as np
from PIL import Image, ImageChops
from pxr import Usd, UsdSkel

from prepare_companions import GLB, HERE, ROOT, SOURCES


def check(character):
    folder = HERE / character
    manifest = json.loads((folder / 'manifest.json').read_text())
    source = ROOT / 'blender-companions' / character / SOURCES[character]
    assert hashlib.sha256(source.read_bytes()).hexdigest() == manifest['source_sha256']
    model = json.loads((folder / (character + '.bbmodel')).read_text())
    glb = GLB(folder / (character + '.glb'))
    names = [c['name'] for c in manifest['clips']]
    assert len(names) == len(set(names)) == 20
    assert names == [a['name'] for a in glb.doc['animations']] == [a['name'] for a in model['animations']]
    assert len(glb.doc['skins']) == len(glb.doc['meshes']) == 1
    primitive = glb.doc['meshes'][0]['primitives'][0]
    indices = glb.accessor(primitive['indices'])
    assert indices.size // 3 == manifest['triangles'] < 50000
    positions = glb.accessor(primitive['attributes']['POSITION'])
    assert indices.min() >= 0 and indices.max() < len(positions)
    for accessor in primitive['attributes'].values():
        assert np.isfinite(glb.accessor(accessor)).all()
    weights = glb.accessor(primitive['attributes']['WEIGHTS_0'])
    assert np.allclose(weights.sum(axis=1), 1, atol=1e-5)
    view = glb.doc['bufferViews'][glb.doc['images'][0]['bufferView']]
    start = view.get('byteOffset', 0)
    image = glb.binary[start:start + view['byteLength']]
    authored = base64.b64decode(model['textures'][0]['source'].split(',', 1)[1])
    assert image == authored, 'Embedded texture differs from the editable source'
    assert Image.open(io.BytesIO(image)).size == tuple(manifest['texture_size'])
    for animation, clip in zip(glb.doc['animations'], manifest['clips']):
        has_motion = False
        for sampler in animation['samplers']:
            times = glb.accessor(sampler['input']).ravel()
            values = glb.accessor(sampler['output'])
            assert np.all(np.diff(times) > 0) and times[0] == 0
            assert abs(times[-1] - clip['duration']) < 1e-5 and np.isfinite(values).all()
            assert np.allclose(values[0], values[-1], atol=1e-5)
            has_motion |= np.max(np.abs(values - values[0])) > 1e-5
        assert has_motion, clip['name']
    usd_path = folder / (character + '.usdz')
    with zipfile.ZipFile(usd_path) as package:
        assert package.testzip() is None
        palettes = [name for name in package.namelist() if name.split('/')[-1] == 'palette.png']
        assert len(palettes) == 1 and package.read(palettes[0]) == image
        assert all(i.compress_type == zipfile.ZIP_STORED for i in package.infolist())
    stage = Usd.Stage.Open(str(usd_path))
    cache = UsdSkel.Cache()
    cache.Populate(UsdSkel.Root(stage.GetPrimAtPath('/Companion')), Usd.PrimDefaultPredicate)
    query = cache.GetSkelQuery(UsdSkel.Skeleton(stage.GetPrimAtPath('/Companion/Skeleton')))
    assert query.GetAnimQuery()
    previous_end = -1
    for interval in manifest['usd_clip_ranges']:
        assert interval['start'] > previous_end
        previous_end = interval['end']
        a = np.asarray(query.ComputeSkinningTransforms(interval['start'] * 24))
        b = np.asarray(query.ComputeSkinningTransforms(interval['end'] * 24))
        middle = np.asarray(query.ComputeSkinningTransforms((interval['start'] * .625 + interval['end'] * .375) * 24))
        assert np.isfinite(middle).all() and np.max(np.abs(a - b)) < 1e-4
        assert np.max(np.abs(a - middle)) > 1e-6
    for path in [folder / 'neutral.png', *(folder / 'review').glob('*.png')]:
        assert Image.open(path).convert('RGBA').getchannel('A').getbbox(), str(path)
    for name in ('float', 'coaching', 'celebrate', 'stretch'):
        gif = Image.open(folder / (name + '.gif'))
        assert gif.n_frames > 4
        first = gif.convert('RGB')
        gif.seek(gif.n_frames // 4)
        assert ImageChops.difference(first, gif.convert('RGB')).getbbox(), name
    snapshot = json.loads((HERE / 'comparison/blender/snapshot.json').read_text())
    assert hashlib.sha256((HERE / 'comparison/blender' / (character + '.glb')).read_bytes()).hexdigest() == snapshot[character]
    assert usd_path.stat().st_size == manifest['usdz_bytes']
    return {'character': character, 'clips': len(names), 'triangles': manifest['triangles'],
            'glb_bytes': manifest['glb_bytes'], 'usdz_bytes': manifest['usdz_bytes'], 'passed': True}


if __name__ == '__main__':
    result = [check(c) for c in SOURCES]
    with zipfile.ZipFile(HERE / 'gymni-companions-ios.zip') as archive:
        assert archive.testzip() is None
        clips = json.loads(archive.read('ios-clips.json'))
        for character in SOURCES:
            assert archive.read(character + '.usdz') == (HERE / character / (character + '.usdz')).read_bytes()
            assert len(clips[character]['clips']) == 20
    (HERE / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
