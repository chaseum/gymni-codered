"""Check the iOS companion handoff without requiring Blender or Apple SDKs."""
import hashlib
import json
import math
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'ios' / 'GymAndAI'
RESOURCES = APP / 'Mascot' / 'Resources'
FILES = {'pip': 'Pip.usdz', 'atlas': 'AtlasAnimated.usdz', 'flex': 'FlexAnimated.usdz'}
EXPECTED = {'idle', 'encouraging', 'celebration', 'rest', 'happy', 'sad'}


def main():
    metadata = RESOURCES / 'CompanionClips.json'
    companions = json.loads(metadata.read_text(encoding='utf-8'))
    assert set(companions) == set(FILES), 'Missing companion metadata'
    total = metadata.stat().st_size
    for name, filename in FILES.items():
        path = RESOURCES / filename
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None, (name, 'Corrupt USDZ')
            assert any(entry.endswith('.usdc') for entry in archive.namelist()), name
        total += path.stat().st_size
        clips = companions[name]
        assert len(clips) == 6 and {c['name'] for c in clips} == EXPECTED, name
        previous_end = -1
        for clip in clips:
            assert all(math.isfinite(clip[key]) for key in ('duration', 'trim_start', 'trim_end'))
            assert clip['duration'] > 0 and clip['trim_start'] > previous_end
            assert abs(clip['duration'] - (clip['trim_end'] - clip['trim_start'])) < .001
            assert clip['loop'] == (clip['name'] in ('idle', 'rest'))
            previous_end = clip['trim_end']
        fallback = APP / 'Assets.xcassets' / (name.capitalize() + 'Preview.imageset')
        images = json.loads((fallback / 'Contents.json').read_text(encoding='utf-8'))['images']
        assert any((fallback / image['filename']).is_file() for image in images if 'filename' in image)
        # Compare with authoring output when it exists; a fresh checkout needs only app assets.
        source = ROOT / 'blender-companions' / 'animated' / 'ios-package' / (name.capitalize() + 'Animated.usdz')
        if source.exists():
            assert hashlib.sha256(path.read_bytes()).digest() == hashlib.sha256(source.read_bytes()).digest()
    assert total < 6_000_000, total
    project = (ROOT / 'ios' / 'GymAndAI.xcodeproj' / 'project.pbxproj').read_text(encoding='utf-8')
    assert 'PBXFileSystemSynchronizedRootGroup' in project and 'fileSystemSynchronizedGroups' in project
    print(f'PASS: three USDZs, 18 clips, three fallbacks; runtime package {total:,} bytes')


if __name__ == '__main__':
    main()
