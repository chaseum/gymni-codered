"""Copy only runtime assets and compact clip metadata into the iOS handoff."""
import json
import shutil
from pathlib import Path

BASE = Path(__file__).resolve().parents[1] / 'blender-companions' / 'animated'


def main():
    validation = json.loads((BASE / 'validation.json').read_text())
    assert validation['passed']
    folder = BASE / 'ios-package'
    folder.mkdir(exist_ok=True)
    clips = {}
    for name in ('atlas', 'flex', 'pip'):
        manifest = json.loads((BASE / name / 'manifest.json').read_text())
        source = BASE / name / (name + '-animated.usdz')
        assert source.stat().st_size == manifest['usdz_bytes']
        shutil.copy2(source, folder / (name.capitalize() + 'Animated.usdz'))
        clips[name] = [{k: clip[k] for k in ('name', 'duration', 'loop', 'trim_start', 'trim_end')}
                       for clip in manifest['clips']]
    (folder / 'CompanionClips.json').write_text(json.dumps(clips, separators=(',', ':')) + '\n')
    assert len(list(folder.iterdir())) == 4
    size = sum(p.stat().st_size for p in folder.iterdir())
    assert size < 6_000_000
    resources = BASE.parents[1] / 'ios' / 'GymAndAI' / 'Mascot' / 'Resources'
    for name in ('atlas', 'flex', 'pip'):
        destination = 'Pip.usdz' if name == 'pip' else name.capitalize() + 'Animated.usdz'
        shutil.copy2(folder / (name.capitalize() + 'Animated.usdz'), resources / destination)
    shutil.copy2(folder / 'CompanionClips.json', resources / 'CompanionClips.json')
    print(f'{folder}: {size:,} bytes; three USDZs and one clip manifest')


if __name__ == '__main__':
    main()
