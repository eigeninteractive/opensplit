# OpenSplit — brand & theme

Everything below is generated from **one seed** plus **one vector mark**. If you need a
colour, read it off `ColorScheme`; if you need the logo, use the SVG. Nothing else is brand.

## Seed

| | |
|---|---|
| Seed | `0xFF5B5891` (muted violet) |
| Light primary | `#5B5891` · container `#E3DFFF` · surface `#FBF8FF` |
| Dark primary | `#C4C0FF` · container `#434078` · surface `#131318` |
| Dynamic colour | **on** for Android 12+, and switchable off in Settings; `harmonized()` shifts the *error* roles toward the wallpaper's primary. Nothing else — once a wallpaper palette exists it replaces the seed outright. |
| Contrast | pass the platform setting into `contrastLevel` — standard/medium/high come free |

Hex values are only hardcoded where a build config can't call Dart: launcher background,
splash background, web `theme_color`. Everywhere else the runtime scheme is authoritative.

## Semantic roles

| Meaning | Role |
|---|---|
| Owed to you | `primary` |
| You owe | `error` |
| Computed by the app | `tertiary` |
| Settled | `onSurfaceVariant` |

See `lib/theme/money_semantics.dart`. No custom colours — this is what survives Material You.

## Type

- All text: **Instrument Sans** via `google_fonts`, applied to M3's unmodified type scale.
- All currency amounts: **JetBrains Mono** with `FontFeature.tabularFigures()` — use
  `AppTheme.amount(context)`.

## Mark

The **slashed O** — a ring with one diagonal cut. One shape, one stroke weight, legible at 16px.
The cut is a *knockout*, so on a coloured surface it shows that surface through.

| File | Use |
|---|---|
| `assets/brand/mark.svg` | app-side logo, brand violet |
| `assets/brand/mark-mono.svg` | `currentColor` — inherits when inlined (`SvgPicture`, themed icon). An `<img>` tag cannot tint it. |
| `assets/brand/mark-on-dark.svg` | pre-stroked `#C4C0FF` for dark surfaces |
| `assets/brand/mark-on-primary-container.svg` | pre-stroked `#E3DFFF` |
| `assets/brand/lockup-horizontal.svg` | app bar, README, web header |
| `assets/brand/lockup-vertical.svg` | onboarding, about screen, store listing |
| `site/favicon.svg` | browser tab |

Lockup SVGs reference Instrument Sans by name. Convert the `<text>` to outlines before
shipping anywhere the font isn't loaded (store listings, GitHub social preview).

Clear space: one stroke-width on all sides. Minimum size: 16px. Never re-colour the mark
outside the tonal family, never add a shadow, never place it on a photo.

## Icons — flutter_launcher_icons

```sh
flutter pub add dev:flutter_launcher_icons
dart run flutter_launcher_icons
```

Config: `flutter_launcher_icons.yaml`. Inputs:

| File | Layer |
|---|---|
| `assets/icon/icon.png` (1024, opaque) | iOS / web / desktop / legacy Android |
| `assets/icon/icon-foreground.png` (1024, transparent) | Android adaptive foreground — mark is 470px, inside the 676px safe circle |
| `assets/icon/icon-monochrome.png` (1024, transparent black) | Android 13+ themed icon |
| `adaptive_icon_background: "#E3DFFF"` | flat colour, no image layer needed |

`assets/icon/icon-dark.png` is provided for store listings that want a dark variant;
Android adaptive icons themselves have no dark form.

## Splash — flutter_native_splash

```sh
flutter pub add dev:flutter_native_splash
dart run flutter_native_splash:create
```

Config: `flutter_native_splash.yaml`. `assets/splash/splash-icon.png` is 1152×1152 with the
mark at 640px, which keeps it inside the Android 12 masked circle. No wordmark on the splash —
Android 12+ crops it. The "free & open source" line belongs on the first in-app screen.

## Web

- `web/manifest.json` — name, theme colour, 192/512 + maskable 192/512.
- `web/index-head-snippet.html` — paste into `<head>`; includes light/dark `theme-color`.
- `site/favicon.svg` + `site/favicon.png`.

## pubspec

```yaml
dependencies:
  dynamic_color: ^1.7.0
  google_fonts: ^6.2.1

flutter:
  assets:
    - assets/brand/
    - assets/icon/
    - assets/splash/
```
