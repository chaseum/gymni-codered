"""Render lightweight review frames from the actual animated Blender sources."""
import json
from pathlib import Path
import bpy

BASE = Path(__file__).resolve().parents[1] / 'blender-companions' / 'animated'

def main():
    for name in ('pip', 'atlas', 'flex'):
        folder = BASE / name
        bpy.ops.wm.open_mainfile(filepath=str(folder / (name + '-animated.blend')))
        scene = bpy.context.scene
        scene.render.engine = 'CYCLES'
        scene.cycles.samples = 16
        scene.cycles.use_denoising = True
        scene.render.resolution_x = scene.render.resolution_y = 256
        scene.render.resolution_percentage = 100
        scene.render.film_transparent = True
        scene.render.image_settings.file_format = 'PNG'
        scene.render.image_settings.color_mode = 'RGBA'
        scene.camera.data.ortho_scale *= 1.12
        output = folder / 'smooth-frames'
        output.mkdir(exist_ok=True)
        clips = json.loads((folder / 'manifest.json').read_text())['clips']
        for clip in clips:
            count = round(clip['duration'] * 30)
            for index in range(count):
                frame = clip['start_frame'] + index
                scene.frame_set(int(frame), subframe=frame % 1)
                scene.render.filepath = str(output / (clip['name'] + f'-{index:03}.png'))
                bpy.ops.render.render(write_still=True)
    return {'review': str(BASE), 'frames_per_second': 30}

if __name__ == '__main__':
    main()
