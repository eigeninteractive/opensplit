# The brand

Everything visual comes from **one seed colour** and **one vector mark**. If you
need a colour, read it off the `ColorScheme`; if you need the logo, use an SVG
from `assets/brand/`. Nothing else is brand.

This folder is the designer's kit, kept for the next round of design work. What
the app and the site actually ship lives elsewhere in the tree and is listed
below; nothing here is built or served.

## Colour

The seed is Material indigo 500, `Colors.indigo` (`#3F51B5`): `_seed` in
`lib/presentation/theme.dart`, expanded by `ColorScheme.fromSeed` for both
brightnesses. On Android 12 and later a wallpaper scheme replaces it unless the
user turns that off, harmonised so error and the money colours shift toward
the wallpaper too.

Hex values are written out only where a build config cannot call Dart: the
adaptive icon background (`#DEE0FF`, light `primaryContainer`), the splash and
web loader backgrounds, the web `theme-color`, the static site's tokens at the
top of `site/site.css`, and `tool/store_graphics.py`. Each is the generated value,
from `ColorScheme.fromSeed`, including light surface `#FBF8FF` and dark
surface `#121318`. The seed is a source colour; the generated primary is
`#515B92` in light mode and `#BAC3FF` in dark mode.

Money has two colours of its own, `BalanceColors` in the same file. Owed to you
is a green harmonised toward the seed, and you owe is the scheme's `error`.

Automatic avatars use a stable choice of the app's primary, secondary, or
tertiary container. They follow wallpaper colours. Choosing a hue explicitly
keeps that personal choice, harmonised with the current app palette. The
picture picker offers **Automatic** to return to the theme.

## Type

- All text is **Google Sans Flex**, applied to Material 3's unmodified type scale.
- Every amount is Google Sans Flex with **tabular figures**, through
  `moneyStyle`, so amounts line up in a column and hold still as they change.
  An amount's prominence comes from the type scale step it is set in, not
  from a second face.
- There is no second face. The sign-in email sets its code the same way, and
  the static site leaves inline code to the reader's own monospace.

The face is bundled under `assets/google_fonts/` rather than fetched; see the
comments in `pubspec.yaml`. The static site serves the same files from
`/fonts`, so the pages and the app cannot drift onto different cuts of it.

## The mark

The **slashed O**: a ring with one diagonal cut. One shape, one stroke weight,
legible at 16 px. The cut is a knockout, so on a coloured surface the surface
shows through it.

| File | Use |
|---|---|
| `assets/brand/mark.svg` | generated brand primary (`#515B92`) |
| `assets/brand/mark-mono.svg` | `currentColor`, tinted at runtime; the only variant bundled into the app (`BrandMark`) |
| `assets/brand/mark-neutral.svg` | pre-stroked `#E4E1E9`, a light neutral |
| `assets/brand/mark-on-dark.svg` | pre-stroked `#BAC3FF`, for dark surfaces |
| `assets/brand/mark-on-primary-container.svg` | pre-stroked `#DEE0FF` |
| `assets/brand/mark-1024-light.png`, `-dark.png` | rasters for the icon and splash generators |
| `assets/brand/lockup-horizontal.svg`, `lockup-vertical.svg` | mark and wordmark: "Open" regular, "Split" semibold |
| `site/favicon.svg` | the browser tab |

The lockups name Google Sans Flex rather than carrying outlines, so convert the
text to outlines before using one anywhere the font is not loaded: a store
listing, a social preview.

Clear space is one stroke width on every side, and the minimum size is 16 px.
Never recolour the mark outside its tonal family, never give it a shadow, and
never set it on a photograph.

## Icons and splash

Generated, never edited by hand:

| Command | Writes | From |
|---|---|---|
| `python3 tool/brand_artwork.py` | the PNG sources in `assets/brand/`, `assets/icon/` and `assets/splash/` | the canonical mark SVG and the generated palette |
| `dart run flutter_launcher_icons` | Android, iOS and web icons | `assets/icon/`, configured in `flutter_launcher_icons.yaml` |
| `dart run tool/brand_icons.dart` | root web icons, the favicon and the notification icon, after the command above | the transparent artwork in `assets/icon/` |
| `dart run flutter_native_splash:create` | the native splash screens | `assets/splash/`, configured in `flutter_native_splash.yaml` |
| `flutter test tool/screenshots_test.dart` | `site/store/screenshot-*.png` and `web-app.png` | the real screens over demo data |
| `python3 tool/store_graphics.py` | `site/store/og-card.png` and `feature-graphic.jpg`, and `site/email/wordmark.png` for the sign-in email | the balances screenshot, the mark's geometry and the bundled font |

`assets/icon/icon.png` is opaque because iOS and legacy Android icons cannot
carry alpha. The adaptive foreground keeps the mark inside the circle a
launcher masks it to. The splash icon is 1152 px with the mark at 640 px, so that
Android 12's masked circle does not crop it, and there is no wordmark on the
splash for the same reason.

## Play listing

| Asset | Size | File |
|---|---|---|
| Hi-res icon | 512 × 512, opaque | `assets/icon/icon.png`, resized |
| Feature graphic | 1024 × 500, JPEG | `site/store/feature-graphic.jpg` |
| Phone screenshots | 1080 × 1920, PNG | `site/store/screenshot-1-groups.png` to `-5-insights.png`, in that order |

All of it is generated (above). To package the committed assets and Cider notes:

```sh
dart run tool/play_metadata.dart --output=build/play-metadata
```

The tool uses Fastlane's `en-US` metadata layout, resizing the icon to an opaque
512 × 512 PNG. The release workflow prepares this tree before building and
saves it as a separate release artifact. Fastlane uploads the artwork with the
bundle and notes, skipping unchanged images by checksum. The screenshots replace the
phone gallery in their listed order. Listing images apply across Play tracks,
even when the bundle is sent to closed testing; listing text is left alone.

The output must be new or empty, so stale images cannot slip into a release.
The tool checks image dimensions and opacity and fails if anything is missing.
Feature graphics are JPEG because Play rejects a PNG with an alpha channel,
even a fully opaque one.

The screenshots are the app itself, rendered by a widget test with the bundled
fonts, so a UI change is a rerun rather than a redesign. The demo data is a
London-based Ana with a trip to Lisbon in euros and pounds, a flat in pounds
and a family trip in rupees: several currencies, because keeping them apart is
the point.

## The design canvases

The `.dc.html` files are the designer's working documents, as their authoring
tool wrote them, with `support.js` as that tool's runtime. Their image paths
point at the committed assets above.

They are where the brand started, not where the site is now: the landing page,
the document pages and the store images have since been redesigned in code, in
`site/` and the generators above. The October 2026 update keeps the mark and
uses indigo with Google Sans Flex. The original canvases remain historical
references; this document describes the shipped identity.

| File | What it is |
|---|---|
| `Brand Directions.dc.html` | the directions explored before this one was chosen |
| `OpenSplit Brand Kit.dc.html` | this document's visual form: the mark, colours, icons and splash |
| `Terms.dc.html` | the first design of the document pages |
| `Play Store Assets.dc.html` | the first feature graphics and mockup screenshots, before both were generated |

To view one, serve the repository root and open it from there, since the tool's
runtime fetches the page it is on and a `file://` page cannot:

```sh
python3 -m http.server 8000      # then open http://localhost:8000/docs/brand/
```

Biome leaves them alone (`biome.jsonc`): they are a tool's output, and
reformatting them would only make the next round's diff unreadable.
