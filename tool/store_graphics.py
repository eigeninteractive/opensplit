"""Generates the raster brand images: two promotional ones from the landing
page's hero, and the lockup the sign-in email opens with.

    python3 tool/store_graphics.py

after `flutter test tool/screenshots_test.dart`, since the first two frame a
real screenshot:

- site/store/og-card.png, 1200 x 630, the link preview Open Graph asks for.
- site/store/feature-graphic.jpg, 1024 x 500, the banner on the Play listing.
  JPEG because Play rejects a PNG with an alpha channel, even an opaque one.
- site/email/wordmark.png, the lockup at three times the size the email shows
  it (server/src/email/sender.ts). Mail clients load neither SVG nor web fonts,
  so the one place the brand's type has to survive Gmail is a picture of it.

One composition at two sizes: the headline and wordmark on the left, and on the
right the brand mark drawn large in lilac with the app's balances screen across
its cut, as the hero sets it. Everything is drawn here from the brand's own
values (docs/brand/README.md) and the bundled Instrument Sans, at four times
the size and scaled down, which is how PIL gets antialiased edges.

Pinned by test/site_meta_test.dart, because a wrong-sized image fails silently:
it renders badly in a preview or a listing nobody on this side ever sees.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

PAPER = (252, 248, 255)     # #FCF8FF, surface
INK = (28, 27, 33)          # #1C1B21, onSurface
SLATE = (71, 70, 79)        # #47464F, onSurfaceVariant
VIOLET = (91, 88, 145)      # #5B5891, the seed
LILAC = (227, 223, 255)     # #E3DFFF, primaryContainer
SHADOW = (67, 64, 120)      # #434078, onPrimaryContainer

FONTS = 'assets/google_fonts'
REGULAR = f'{FONTS}/InstrumentSans-Regular.ttf'
SEMIBOLD = f'{FONTS}/InstrumentSans-SemiBold.ttf'

SCREEN = 'site/store/screenshot-3-balances.png'

# Supersampling factor.
S = 4


def mark(draw, centre, radius, stroke, colour, background):
    """The slashed O: a ring cut by a bar at 24 degrees from vertical.

    The same geometry as assets/brand/mark.svg -- r 17 and stroke 6.5 in a
    48 unit box, cut 6.5 wide -- at whatever size [radius] gives.
    """
    cx, cy = centre
    draw.ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius],
        outline=colour, width=round(stroke))

    # The cut: a long bar through the centre, as wide as the stroke, rotated.
    half_w, half_l = stroke / 2, radius * 1.6
    angle = math.radians(24)
    dx, dy = math.sin(angle), -math.cos(angle)
    nx, ny = math.cos(angle), math.sin(angle)
    corners = [
        (cx + dx * l + nx * w, cy + dy * l + ny * w)
        for l, w in [(half_l, half_w), (half_l, -half_w),
                     (-half_l, -half_w), (-half_l, half_w)]
    ]
    draw.polygon(corners, fill=background)


def rounded(image, radius):
    """`image` clipped to a rounded rectangle, with alpha."""
    mask = Image.new('L', image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (image.width - 1, image.height - 1)], radius, fill=255)
    out = image.convert('RGBA')
    out.putalpha(mask)
    return out


def lifted(canvas, image, at, radius):
    """Pastes [image] with the page's layered violet shadow under it."""
    x, y = at
    w, h = image.size
    for offset, blur, alpha in [(2 * S, 3 * S, 22), (10 * S, 24 * S, 40),
                                (36 * S, 60 * S, 56)]:
        layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).rounded_rectangle(
            [x, y + offset, x + w, y + h + offset], radius,
            fill=SHADOW + (alpha,))
        canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))
    canvas.alpha_composite(rounded(image, radius), (x, y))


def wordmark(draw, at, size):
    """The lockup: the mark, then "Open" regular and "Split" semibold."""
    x, baseline = at
    glyph = size * 1.25
    r = glyph * 17 / 48
    mark(draw, (x + glyph / 2, baseline - size * 0.36), r, glyph * 6.5 / 48,
         VIOLET, PAPER)
    x += glyph + size * 0.4
    regular = ImageFont.truetype(REGULAR, round(size))
    semibold = ImageFont.truetype(SEMIBOLD, round(size))
    draw.text((x, baseline), 'Open', font=regular, fill=INK, anchor='ls')
    x += draw.textlength('Open', font=regular)
    draw.text((x, baseline), 'Split', font=semibold, fill=INK, anchor='ls')


def compose(width, height, layout):
    """One image, laid out by the proportions in [layout]."""
    W, H = width * S, height * S
    canvas = Image.new('RGBA', (W, H), PAPER + (255,))
    draw = ImageDraw.Draw(canvas)

    # The mark, bleeding off the right edge, with the cut's upper end clear of
    # the screen so the shape still reads as the mark behind it.
    radius = layout['ring'] * H
    centre = (W - layout['ring_right'] * H, H * 0.56)
    mark(draw, centre, radius, radius * 6.5 / 17, LILAC, PAPER)

    # The balances screen, its top portion: the part that says what the app
    # does, cropped where a phone would run off the bottom of the image.
    shot = Image.open(SCREEN).convert('RGB')
    screen_w = round(layout['screen'] * H)
    scale = screen_w / shot.width
    shot = shot.resize((screen_w, round(shot.height * scale)), Image.LANCZOS)
    top = round(layout['screen_top'] * H)
    shot = shot.crop((0, 0, screen_w, H - top + 40 * S))
    screen_x = round(centre[0] - screen_w * 0.62)
    lifted(canvas, shot, (screen_x, top), round(screen_w * 0.09))

    # Text, left-aligned on one margin.
    margin = layout['margin'] * H
    wordmark(draw, (margin, layout['wordmark_y'] * H), layout['wordmark'] * H)
    headline = ImageFont.truetype(SEMIBOLD, round(layout['headline'] * H))
    y = layout['headline_y'] * H
    for line in ['Split expenses', 'with friends,', 'free forever.']:
        draw.text((margin, y), line, font=headline, fill=INK, anchor='ls')
        y += layout['headline'] * H * 1.02
    body = ImageFont.truetype(REGULAR, round(layout['body'] * H))
    y += layout['body'] * H * 0.9
    for line in layout['lines']:
        draw.text((margin, y), line, font=body, fill=SLATE, anchor='ls')
        y += layout['body'] * H * 1.45

    return canvas.resize((width, height), Image.LANCZOS).convert('RGB')


def email_wordmark(size, scale):
    """The lockup alone on the email card's surface, [size] px type at [scale]x.

    The mark sits centred in a box `1.25 * size` square, as [wordmark] draws
    it, and that box is the image's height: the type's ascenders and the
    descender of the "p" both fall inside it.
    """
    px = size * scale * S
    glyph = px * 1.25
    regular = ImageFont.truetype(REGULAR, round(px))
    semibold = ImageFont.truetype(SEMIBOLD, round(px))
    probe = ImageDraw.Draw(Image.new('RGB', (1, 1)))
    text = (probe.textlength('Open', font=regular)
            + probe.textlength('Split', font=semibold))
    W = math.ceil((glyph + px * 0.4 + text) / S) * S
    H = math.ceil(glyph / S) * S

    canvas = Image.new('RGB', (W, H), PAPER)
    wordmark(ImageDraw.Draw(canvas), (0, glyph / 2 + px * 0.36), px)
    return canvas.resize((W // S, H // S), Image.LANCZOS)


def build():
    og = compose(1200, 630, {
        'ring': 0.50, 'ring_right': 0.40,
        'screen': 0.62, 'screen_top': 0.10,
        'margin': 0.13, 'wordmark': 0.058, 'wordmark_y': 0.20,
        'headline': 0.118, 'headline_y': 0.42,
        'body': 0.042,
        'lines': ['Free and open source, offline and in any',
                  'currency. No ads, no tracking.'],
    })
    og.save('site/store/og-card.png', optimize=True)

    # Play crops nothing from a feature graphic but may overlay a play button
    # in the middle, so the screen keeps to the right third.
    play = compose(1024, 500, {
        'ring': 0.52, 'ring_right': 0.40,
        'screen': 0.62, 'screen_top': 0.10,
        'margin': 0.13, 'wordmark': 0.062, 'wordmark_y': 0.21,
        'headline': 0.122, 'headline_y': 0.44,
        'body': 0.044,
        'lines': ['Free and open source. No ads, no tracking.'],
    })
    play.save('site/store/feature-graphic.jpg', quality=92, optimize=True)

    for name, image in [('og-card.png', og), ('feature-graphic.jpg', play)]:
        print(f'site/store/{name}: {image.width}x{image.height}')

    email = email_wordmark(20, 3)
    os.makedirs('site/email', exist_ok=True)
    email.save('site/email/wordmark.png', optimize=True)
    print(f'site/email/wordmark.png: {email.width}x{email.height}')


if __name__ == '__main__':
    build()
