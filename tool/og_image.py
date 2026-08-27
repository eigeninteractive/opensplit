"""Generates the Open Graph card at site/store/og-card.png.

The Play feature graphic could not simply be reused. It is 1024x500 (aspect
2.048) where Open Graph wants 1200x630 (1.905), and it cannot be padded or
cropped into shape: the phone bleeds off the bottom edge over a rounded corner,
so repeating the last row seams, and the subline text runs to x=514 while the
lilac circle starts at x=550, so there is no vertical line to cut along either.

So the card is composed from the same primitives the feature graphic uses --
the same background, the same lilac, the same mark, the same bundled Instrument
Sans -- at the size social cards actually want.

    python3 tool/og_image.py

Pinned by test/og_image_test.dart, because a wrong-sized card fails silently:
it renders badly in a preview nobody on this side of the link ever sees.
"""

from PIL import Image, ImageDraw, ImageFont

W, H = 1200, 630
BG = (251, 248, 255)        # #FBF8FF, the site background
LILAC = (227, 223, 255)     # #E3DFFF, the hero's circle
INK = (27, 27, 33)          # #1B1B21
MUTED = (71, 70, 79)        # #47464F
FRAME = (27, 27, 33)

# Height of the Play caption band baked into the store screenshots.
CAPTION_BAND = 241

FONTS = 'assets/google_fonts'
REGULAR = f'{FONTS}/InstrumentSans-Regular.ttf'
SEMIBOLD = f'{FONTS}/InstrumentSans-SemiBold.ttf'


def rounded(image, radius):
    """Clips `image` to a rounded rectangle, returning it with alpha."""
    mask = Image.new('L', image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (image.size[0] - 1, image.size[1] - 1)], radius, fill=255)
    out = image.convert('RGBA')
    out.putalpha(mask)
    return out


def mark(size):
    """The brand mark, cropped out of the 1024px master and scaled.

    The master is padded and sits on this same background colour, so the
    crop composites onto the card with its antialiased edges intact and
    needs no alpha channel of its own.
    """
    src = Image.open('assets/brand/mark-1024-light.png').convert('RGB')
    return src.crop(_content_box(src)).resize((size, size), Image.LANCZOS)


def _content_box(image):
    pixels = image.load()
    w, h = image.size
    left, top, right, bottom = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            if max(abs(a - b) for a, b in zip(pixels[x, y], BG)) > 6:
                left, right = min(left, x), max(right, x)
                top, bottom = min(top, y), max(bottom, y)
    return (left, top, right + 1, bottom + 1)


def build():
    card = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(card)

    # The hero's circle, bleeding off the top-right corner.
    r = 340
    draw.ellipse([(W - 60 - r, -150), (W - 60 + r, -150 + 2 * r)], fill=LILAC)

    # The phone, bleeding off the bottom edge exactly as the hero does.
    #
    # The top 241px is a Play caption band -- marketing copy, which inside a
    # device frame reads as if the app said it -- so it is cropped away.
    #
    # The rest is used at full height rather than trimmed to where the rows
    # stop. Trimming was tried: the content region is wide and short, so a
    # frame sized to it becomes a stub floating in the corner. Kept whole, the
    # phone is phone-shaped, starts near the top of the card, and runs off the
    # bottom edge the way the hero's do.
    shot = Image.open('site/store/screenshot-1-groups.png').convert('RGB')
    shot = shot.crop((0, CAPTION_BAND, shot.width, shot.height))

    body_w, pad = 350, 9
    screen_w = body_w - 2 * pad
    screen_h = round(shot.height * screen_w / shot.width)
    shot = shot.resize((screen_w, screen_h), Image.LANCZOS)

    body = Image.new('RGB', (body_w, screen_h + 2 * pad), FRAME)
    clipped = rounded(shot, 24)
    body.paste(clipped, (pad, pad), clipped)

    # Sits so the screen's last row of content lands on the card's bottom edge.
    phone_x = W - body_w - 72
    phone_y = H - screen_h - pad
    framed = rounded(body, 34)
    card.paste(framed, (phone_x, phone_y), framed)

    # Wordmark: "Open" regular, "Split" semibold, as the lockup sets it.
    x = 88
    glyph = 74
    card.paste(mark(glyph), (x, 150))

    open_font = ImageFont.truetype(REGULAR, 52)
    split_font = ImageFont.truetype(SEMIBOLD, 52)
    wx = x + glyph + 20
    draw.text((wx, 187), 'Open', font=open_font, fill=INK, anchor='ls')
    wx += draw.textlength('Open', font=open_font)
    draw.text((wx, 187), 'Split', font=split_font, fill=INK, anchor='ls')

    draw.text((x, 300), 'Open source. No fees. No ads.',
              font=ImageFont.truetype(SEMIBOLD, 44), fill=INK, anchor='ls')
    draw.text((x, 352), 'Split bills with friends and roommates —',
              font=ImageFont.truetype(REGULAR, 22), fill=MUTED, anchor='ls')
    draw.text((x, 384), 'free forever, open source, self-hostable.',
              font=ImageFont.truetype(REGULAR, 22), fill=MUTED, anchor='ls')

    headline_end = x + draw.textlength(
        'Open source. No fees. No ads.',
        font=ImageFont.truetype(SEMIBOLD, 44))
    print(f'text ends at x={headline_end:.0f}, phone starts at x={phone_x}')

    out = 'site/store/og-card.png'
    card.save(out, optimize=True)
    print(f'{out}: {card.size[0]}x{card.size[1]}')


if __name__ == '__main__':
    build()
