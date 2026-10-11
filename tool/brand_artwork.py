"""Render launcher and splash source PNGs from the canonical vector mark.

Run before the Flutter icon/splash generators after changing the brand palette.
The colours are build-time copies of ColorScheme roles, checked by theme tests.
"""

import math
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

SVG = '{http://www.w3.org/2000/svg}'
root = ET.parse('assets/brand/mark.svg').getroot()
circle = root.find(f'{SVG}circle')
cut = root.find(f'{SVG}defs/{SVG}mask/{SVG}rect[@transform]')
PRIMARY = '#515B92'
DARK_PRIMARY = '#BAC3FF'
CONTAINER = '#DEE0FF'
SURFACE = '#FBF8FF'
DARK_SURFACE = '#121318'
DARK_CONTAINER = '#1F1F25'
S = 4


def render(path, size, ring_width, colour, background=None):
    """Keep the mark's vector geometry at the original safe-zone dimensions."""
    radius = float(circle.attrib['r'])
    stroke = float(circle.attrib['stroke-width'])
    scale = ring_width / (radius * 2 + stroke) * S
    centre = size * S / 2
    mask = Image.new('L', (size * S, size * S))
    draw = ImageDraw.Draw(mask)
    outer = (radius + stroke / 2) * scale
    inner = (radius - stroke / 2) * scale
    draw.ellipse((centre - outer, centre - outer,
                  centre + outer, centre + outer), fill=255)
    draw.ellipse((centre - inner, centre - inner,
                  centre + inner, centre + inner), fill=0)
    x, y = float(cut.attrib['x']), float(cut.attrib['y'])
    width, height = float(cut.attrib['width']), float(cut.attrib['height'])
    angle = math.radians(float(cut.attrib['transform'].split('(')[1].split()[0]))
    cx, cy = float(circle.attrib['cx']), float(circle.attrib['cy'])
    points = []
    for px, py in ((x, y), (x + width, y),
                   (x + width, y + height), (x, y + height)):
        dx, dy = px - cx, py - cy
        points.append((centre + (dx * math.cos(angle) - dy * math.sin(angle)) * scale,
                       centre + (dx * math.sin(angle) + dy * math.cos(angle)) * scale))
    draw.polygon(points, fill=0)
    mask = mask.resize((size, size), Image.Resampling.LANCZOS)
    # Lanczos can add faint pixels outside the vector's exact bounds. Keep
    # the safe zone identical to the original launcher and splash artwork.
    left = (size - ring_width) // 2
    bounds = (left, left, left + ring_width, left + ring_width)
    bounded = Image.new('L', (size, size))
    bounded.paste(mask.crop(bounds), (left, left))
    mark = Image.new('RGBA', (size, size), colour)
    mark.putalpha(bounded)
    image = Image.new('RGBA', (size, size), background or (0, 0, 0, 0))
    image.alpha_composite(mark)
    if background:
        image = image.convert('RGB')
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output)
    print(path)


if __name__ == '__main__':
    render('assets/brand/mark-1024-light.png', 1024, 600, PRIMARY, SURFACE)
    render('assets/brand/mark-1024-dark.png', 1024, 600, DARK_PRIMARY, DARK_SURFACE)
    render('assets/icon/icon.png', 1024, 600, PRIMARY, CONTAINER)
    render('assets/icon/icon-dark.png', 1024, 600, DARK_PRIMARY, DARK_CONTAINER)
    render('assets/icon/icon-foreground.png', 1024, 470, PRIMARY)
    render('assets/icon/icon-monochrome.png', 1024, 470, '#000000')
    render('assets/splash/splash-icon.png', 1152, 640, PRIMARY)
    render('assets/splash/splash-icon-dark.png', 1152, 640, DARK_PRIMARY)
