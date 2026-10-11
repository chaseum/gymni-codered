"""Build GIFs and an offline review page from rendered Blender frames (Pillow)."""
import html
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

BASE = Path(__file__).resolve().parents[1] / 'blender-companions' / 'animated'
NAMES = ('atlas', 'flex', 'pip')
BACKGROUND = (19, 24, 29)


def effects(picture, clip, elapsed):
    """Review-only rendering of the lightweight SwiftUI overlay, not app assets."""
    layer = Image.new('RGBA', picture.size)
    draw = ImageDraw.Draw(layer)
    width, height = picture.size
    if clip == 'celebration':
        progress = min(1, elapsed / 2.4)
        alpha = round(255 * min(1, progress * 10) * max(0, 1 - progress ** 2))
        colors = ((141, 228, 235), (215, 252, 66), (245, 247, 248))
        for index in range(18):
            angle = index * math.tau / 18
            speed = .7 + index % 4 * .1
            x = width * (.5 + math.cos(angle) * .38 * speed * progress)
            y = height * (.48 - math.sin(angle) * .4 * speed * progress + .6 * progress ** 2)
            rotation = angle + progress * 5
            size = max(2, width * .015)
            points = [(x + a * math.cos(rotation) - b * math.sin(rotation),
                       y + a * math.sin(rotation) + b * math.cos(rotation))
                      for a, b in ((-size / 2, -size), (size / 2, -size),
                                   (size / 2, size), (-size / 2, size))]
            draw.polygon(points, fill=(*colors[index % 3], alpha))
    elif clip == 'rest':
        font = ImageFont.truetype('C:/Windows/Fonts/segoeuib.ttf', round(max(8, width * .1)))
        for index in range(3):
            progress = (elapsed / 3 + index / 3) % 1
            draw.text((width * (.63 + progress * .19), height * (.32 - progress * .22)),
                      'Z', font=font, anchor='mm',
                      fill=(141, 228, 235, round(255 * math.sin(math.pi * progress))))
    return Image.alpha_composite(picture.convert('RGBA'), layer).convert('RGB')


def frame(name, clip, index):
    path = BASE / name / 'smooth-frames' / f'{clip}-{index:03}.png'
    assert path.exists(), path
    picture = Image.open(path).convert('RGBA')
    result = Image.new('RGB', picture.size, BACKGROUND)
    result.paste(picture, mask=picture.getchannel('A'))
    return result


def main():
    review = BASE / 'review'
    review.mkdir(exist_ok=True)
    manifests = {n: json.loads((BASE / n / 'manifest.json').read_text()) for n in NAMES}
    rows = []
    for clip in manifests['pip']['clips']:
        images = []
        count = round(clip['duration'] * 30)
        for index in range(count):
            canvas = Image.new('RGB', (768, 288), BACKGROUND)
            draw = ImageDraw.Draw(canvas)
            for column, name in enumerate(NAMES):
                picture = effects(frame(name, clip['name'], index), clip['name'], index / 30)
                canvas.paste(picture, (column * 256, 24))
                draw.text((column * 256 + 12, 9), name.upper(), fill=(209, 228, 233))
            images.append(canvas)
        filename = clip['name'] + '-effects-v3.gif'
        palette_source = Image.new('RGB', (768, 288 * 3))
        for row, index in enumerate((0, count // 3, count * 2 // 3)):
            palette_source.paste(images[index], (0, row * 288))
        palette = palette_source.quantize(colors=256)
        indexed = [image.quantize(palette=palette, dither=Image.Dither.NONE) for image in images]
        duration = clip['duration'] * 1000
        delays = [round((i + 1) * duration / count / 10) * 10 - round(i * duration / count / 10) * 10 for i in range(count)]
        indexed[0].save(review / filename, save_all=True, append_images=indexed[1:],
                        duration=delays, loop=0, optimize=True)
        rows.append(f'<article><h2>{html.escape(clip["name"])} <small>{clip["duration"]:g}s · '
                    f'{"loop" if clip["loop"] else "one shot"}</small></h2>'
                    f'<p>{html.escape(clip["context"])}</p>'
                    f'<img loading="lazy" src="{filename}" alt="Atlas, Flex and Pip: {clip["name"]}"></article>')
    cards = ''.join(f'<li><strong>{n.title()}</strong>: {manifests[n]["triangles"]:,} triangles, '
                    f'{manifests[n]["usdz_bytes"] / 1_000_000:.2f} MB USDZ, 6 clips</li>' for n in NAMES)
    page = '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
    page += '<title>Gym&I companion animation review</title><style>body{background:#13181d;color:#e0edf1;font:16px system-ui;max-width:840px;margin:32px auto;padding:16px}h1{font-size:30px}h2{font-size:20px;margin-bottom:6px}small{font-size:14px;color:#9dafb6}article{border-top:1px solid #354047;margin-top:24px;padding-top:12px}img{width:100%;height:auto}p{line-height:1.5;color:#b7c8cf}li{margin:8px 0}</style>'
    page += '<h1>Gym&I · companion motions</h1><p>Atlas: steady fuzzy strength coach. Flex: springy matte ribbon for muscle building. Pip: buoyant glossy fitness companion.</p>'
    page += '<p>Six reusable animations per companion: float / idle, encouraging, celebration, sleep / rest, happy and sad. Every preview and exported skeletal animation is sampled at 30 fps. Previews repeat for comparison; one-shot clips play once in the app. App integration and physical iPhone testing are pending.</p>'
    page += '<ul>' + cards + '</ul><p>Bundle only the three USDZ files and clip manifests. Sources, GLBs, renders and GIFs are review/editing assets.</p>'
    page += '<p>Celebration adds one 18-piece confetti burst; rest adds three floating Z letters. These preview overlays mirror the shared SwiftUI Canvas decoration. They add no USDZ size. App overlays stop when hidden and are disabled with Reduce Motion.</p>'
    page += ''.join(rows) + '</html>'
    (review / 'index.html').write_text(page, encoding='utf-8')
    (review / 'six-animations-v2.html').write_text(page, encoding='utf-8')
    (review / 'six-animations-effects-v3.html').write_text(page, encoding='utf-8')
    assert len(rows) == 6
    print(review / 'index.html')


if __name__ == '__main__':
    main()
