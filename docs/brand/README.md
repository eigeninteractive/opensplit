# The brand

Everything visual comes from **one seed colour** and **one vector mark**. If you
need a colour, read it off the `ColorScheme`; if you need the logo, use an SVG
from `assets/brand/`. Nothing else is brand.

This folder is the designer's kit, kept for the next round of design work. What
the app and the site actually ship lives elsewhere in the tree and is listed
below; nothing here is built or served.

## Colour

The seed is `#5B5891`, a muted violet: `_seed` in
`lib/presentation/theme.dart`, expanded by `ColorScheme.fromSeed` for both
brightnesses. On Android 12 and later a wallpaper scheme replaces it unless the
user turns that off, harmonised so error and the money colours shift toward
the wallpaper too.

Hex values are written out only where a build config cannot call Dart: the
adaptive icon background (`#E3DFFF`, light `primaryContainer`), the splash and
web loader backgrounds, and the web `theme-color`. Each is the generated value,
not the kit's: the kit quotes the light surface as `#FBF8FF`, where
`fromSeed` produces `#FCF8FF`, and the generated one wins.

Money has two colours of its own, `BalanceColors` in the same file. Owed to you
is a green harmonised toward the seed, and you owe is the scheme's `error`.

## Type

- All text is **Instrument Sans**, applied to Material 3's unmodified type scale.
- Every amount is **JetBrains Mono** with tabular figures, through `moneyStyle`.

Both faces are bundled under `assets/google_fonts/` rather than fetched; see the
comments in `pubspec.yaml`.

## The mark

The **slashed O**: a ring with one diagonal cut. One shape, one stroke weight,
legible at 16 px. The cut is a knockout, so on a coloured surface the surface
shows through it.

| File | Use |
|---|---|
| `assets/brand/mark.svg` | brand violet |
| `assets/brand/mark-mono.svg` | `currentColor`, tinted at runtime; the only variant bundled into the app (`BrandMark`) |
| `assets/brand/mark-neutral.svg` | pre-stroked `#E4E1E9`, a light neutral |
| `assets/brand/mark-on-dark.svg` | pre-stroked `#C4C0FF`, for dark surfaces |
| `assets/brand/mark-on-primary-container.svg` | pre-stroked `#E3DFFF` |
| `assets/brand/mark-1024-light.png`, `-dark.png` | rasters for generators; `tool/og_image.py` reads the light one |
| `assets/brand/lockup-horizontal.svg`, `lockup-vertical.svg` | mark and wordmark: "Open" regular, "Split" semibold |
| `site/favicon.svg` | the browser tab |

The lockups name Instrument Sans rather than carrying outlines, so convert the
text to outlines before using one anywhere the font is not loaded: a store
listing, a social preview.

Clear space is one stroke width on every side, and the minimum size is 16 px.
Never recolour the mark outside its tonal family, never give it a shadow, and
never set it on a photograph.

## Icons and splash

Generated, never edited by hand:

| Command | Writes | From |
|---|---|---|
| `dart run flutter_launcher_icons` | Android, iOS and web icons | `assets/icon/`, configured in `flutter_launcher_icons.yaml` |
| `dart run tool/brand_icons.dart` | the favicon and the notification icon, after the command above | the transparent artwork in `assets/icon/` |
| `dart run flutter_native_splash:create` | the native splash screens | `assets/splash/`, configured in `flutter_native_splash.yaml` |
| `python3 tool/og_image.py` | `site/store/og-card.png`, the social card | the mark and the bundled font |

`assets/icon/icon.png` is opaque because iOS and legacy Android icons cannot
carry alpha. The adaptive foreground keeps the mark inside the circle a
launcher masks it to. The splash icon is 1152 px with the mark at 640 px, so that
Android 12's masked circle does not crop it, and there is no wordmark on the
splash for the same reason.

## Play listing

| Asset | Size | File |
|---|---|---|
| Hi-res icon | 512 × 512, opaque | `assets/icon/icon.png`, resized |
| Feature graphic | 1024 × 500, JPEG | `site/store/feature-graphic-light.jpg`; `feature-graphic-dark.jpg` here is the unused alternative, since Play takes one |
| Phone screenshots | 1080 × 1920, PNG | `site/store/screenshot-*.png` |

Feature graphics are JPEG because Play rejects a PNG with an alpha channel, even
a fully opaque one. The screenshots are mockups drawn from the theme, not
captures, and Play requires screenshots that show the real UI: replace them
with device captures, and the landing page's copies with them.

## The design canvases

The `.dc.html` files are the designer's working documents, as their authoring
tool wrote them, with `support.js` as that tool's runtime. Their image paths
point at the committed assets above, so they show the artwork as it ships.

| File | What it is |
|---|---|
| `Brand Directions.dc.html` | the directions explored before this one was chosen |
| `OpenSplit Brand Kit.dc.html` | this document's visual form: the mark, colours, icons and splash |
| `Landing Page.dc.html` | the design `site/index.html` was built from |
| `Terms.dc.html` | the design of the document pages |
| `Play Store Assets.dc.html` | the source of the feature graphics and screenshots |

To view one, serve the repository root and open it from there, since the tool's
runtime fetches the page it is on and a `file://` page cannot:

```sh
python3 -m http.server 8000      # then open http://localhost:8000/docs/brand/
```

Biome leaves them alone (`biome.jsonc`): they are a tool's output, and
reformatting them would only make the next round's diff unreadable.
