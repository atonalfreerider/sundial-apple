# Draft App Store screenshots

**These are drafts.** They are rendered on Linux from SundialKit's own drawing code
(`sundial-render`, through SundialSVG and headless Chrome), not captured from the app. The CI's
simulator screenshots replace them: the `Apple` workflow (`.github/workflows/apple.yml`) runs
`Apps/SundialUITests/ScreenshotTests.swift` on an iPhone 17 Pro Max and an iPad Pro 13-inch,
captures the watch app on an Apple Watch Ultra, and uploads everything as the
`app-store-screenshots` artifact, with the same file names. Upload those to App Store Connect, not
these. The PNGs are not committed: `render.sh` writes them here.

What the drafts lack, and the simulator screenshots will have:

- the app around the instrument: the tuck-menu buttons in three corners, the open settings,
  calendars and astrology panels (`6-settings`, `7-astrology-menu`, `8-calendars` and the iPad's
  `4-astrology-menu` exist only from the simulator), and the iOS status bar;
- the sample calendar events of the Play screenshots (Harvest festival, Autumn road trip, Winter
  break, Morning run, Lunch with Sam…): `sundial-render` has no option for events;
- safe areas: on an iPhone with a Dynamic Island or a notch, the app starts the instrument below
  it in portrait (a black strip at the top), so its clock and the Earth view's caption stay visible.

Everything else is the instrument exactly as the apps draw it: the same scene, style, moment,
reading and layout code.

## Scenes

All at **Friday 25 September 2026, 20:30 in Los Angeles**, the moment the UI tests freeze the app
at (`-screenshotInstant 2026-09-26T03:30:00Z -screenshotZone America/Los_Angeles`). The scenes are
the Play listing's (`sundial-android-native/play/graphics`), with its sample reader: an Aries born
18 April 1990, and its reading.

| File | View | Style | Zodiac | Clock | `-screenshotScene` |
|---|---|---|---|---|---|
| `iPhone-6.9-1-solar-view` | solar | Crimson Nebula | off | | `heliocentric-crimson-astronomy` |
| `iPhone-6.9-2-earth-view` | Earth | Crimson Nebula | off | | `geocentric-crimson-astronomy` |
| `iPhone-6.9-3-brass-astrology` | solar | Brass Watch | on, with the reading | | `heliocentric-brass-astrology` |
| `iPhone-6.9-4-brass-earth-view` | Earth | Brass Watch | off | | `geocentric-brass-astronomy` |
| `iPhone-6.9-5-galactic` | galactic | Deep Space Blue | off | | `galactic-blue-astronomy` |
| `iPad-13-1-brass-astrology` | solar | Brass Watch | on, with the reading | | `heliocentric-brass-astrology` |
| `iPad-13-2-earth-view` | Earth | Crimson Nebula | off | | `geocentric-crimson-astronomy` |
| `iPad-13-3-solar-view` | solar | Deep Space Blue | off | | `heliocentric-blue-astronomy` |
| `iPad-13-landscape-1…3` | as the three above, in landscape | | | | |
| `Watch-Ultra-1-brass-astrology` | solar | Brass Watch | on | on | `heliocentric-brass-astrology` |
| `Watch-Ultra-2-brass-earth-view` | Earth | Brass Watch | off | off | `geocentric-brass-astronomy` |
| `Watch-Ultra-3-solar-view` | solar | Crimson Nebula | off | off | `heliocentric-crimson-astronomy` |
| `Watch-Ultra-4-earth-view` | Earth | Deep Space Blue | off | off | `geocentric-blue-astronomy` |
| `Watch-Ultra-5-galactic` | galactic | Cosmic Violet | off | off | `galactic-violet-astronomy` |

The watch app starts with its clock on (as the Wear OS app does), but only the first watch
screenshot shows it: Apple Watch apps must not look like a watch face (App Review 4.2.4), so the
rest show the instrument alone (CI launches them with `-screenshotClock off`).

## Sizes

| Display class in App Store Connect | Pixels | Rendered as |
|---|---|---|
| iPhone 6.9" | 1320 × 2868 | the phone layout, 440 × 956 pt at 3× |
| iPad 13" | 2064 × 2752 (and 2752 × 2064) | the phone layout, 1032 × 1376 pt at 2× |
| Apple Watch Ultra 3 | 422 × 514 | the rectangular watch layout, 211 × 257 pt at 2×, clock on in the first only |

The PNGs are 8-bit RGB without alpha. On a tall iPhone the reading splits into cards above and
below the dial; in iPad portrait it sits on the dial's lower edge, and in landscape beside the
dial, as on the Play tablet screenshots, which is why the iPad set comes in both orientations.

## Rendering them again

```bash
export PATH=~/swift/swift-6.4.0-RELEASE-ubuntu26.04/usr/bin:$PATH   # or any Swift 6 toolchain
AppStore/screenshots-draft/render.sh                                 # needs Chrome or Chromium
```
