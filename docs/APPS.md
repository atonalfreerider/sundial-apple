# The Apple apps

Four targets share SundialKit (this package), generated into `Apps/Sundial.xcodeproj` by
XcodeGen from `Apps/project.yml`:

| Target | Platform | Bundle id | Ports |
|---|---|---|---|
| Sundial | iOS 17+ (iPhone, iPad) | `com.metavirtuoso.sundial` | the Android app: `app/…/MainActivity.kt`, `TuckMenuHost`, `SettingsPanel`, `CalendarPanel`, `AstrologyPanel`, `BirthDateInput`, `BirthTimeInput`, `CalendarRepository`, `HoroscopeGenerator`, `ReadingReporter` |
| SundialWidgets | iOS 17+ WidgetKit extension | `com.metavirtuoso.sundial.widgets` | the Android celestial wallpaper (`DailyWallpaper`): iOS cannot set wallpapers, so the instrument lives on the Home and Lock Screens as widgets |
| SundialWatch | watchOS 10+ | `com.metavirtuoso.sundial.watchkitapp` | the Wear OS app: `wear/…/WatchActivity.kt`, `WatchSettingsActivity.kt`, `WatchPreferences.kt` |
| SundialWatchWidgets | watchOS 10+ WidgetKit extension | `com.metavirtuoso.sundial.watchkitapp.widgets` | the Wear OS watch face: Apple has no custom faces, so the instrument comes to any face as complications |

All four join the App Group `group.com.metavirtuoso.sundial` (`UserDefaults(suiteName:)` handed
to SundialCore's `SettingsStore`): on the iPhone or iPad the app and its widgets share one set of
settings, and on the watch the watch app and its complications share another. The two devices'
containers are separate and not synced, as the Wear OS app keeps its own settings.

## Code layout

```
Apps/
  project.yml
  Shared/           compiled into every target that needs it
    SundialResources.swift   fonts, earth texture, App Group settings
    InstrumentModel.swift    ObservableObject owning an Instrument; redraw scheduling
    InstrumentView.swift     SwiftUI Canvas + gestures + accessibility (iOS and watchOS)
    InstrumentImage.swift    renders an Instrument to a CGImage (widgets, previews)
  Sundial/          the iOS app (SundialApp, ContentView, tuck menus, panels, services)
  SundialWidgets/
  SundialWatch/
  SundialWatchWidgets/
  Resources/        Assets.xcassets (AppIcon), fonts, earth texture, privacy manifests
```

## Shared contracts

- **Fonts**: `sundial_condensed.ttf` (Sundial Condensed, the Android app's face: an Archivo
  instance under the SIL Open Font License 1.1, whose text `sundial-condensed-OFL.txt` ships
  beside it) is bundled in every target, listed in `UIAppFonts` and registered at launch with
  `CTFontManagerRegisterFontsForURL` (`SundialResources.registerFonts()`); SundialCoreGraphics'
  `FontLibrary` looks it up by PostScript name (`FontLibrary.condensedPostScriptName`, which must
  be `SundialCondensed`).
- **Earth texture**: `earth_texture.png` in every target that draws the globe; loaded once into a
  `PixelImage` (straight ARGB) by `SundialResources.earthTexture(downsampled:)`, downsampled 2×
  on the watch and in widgets as Android does on Wear OS.
- **Drawing**: `InstrumentView` draws with a SwiftUI `Canvas`, bridging to Core Graphics through
  `GraphicsContext.withCGContext`, wrapping the context in `CGCanvas` and calling
  `instrument.draw(canvas)`. Canvas units are points, so the Instrument is created with
  `density: 1`.
- **Time and redraws**: the view is driven by a `TimelineView`. While the Instrument reports
  `nextRedrawDelay == 0` (a camera flight) it animates every frame; otherwise it ticks at
  `nextRedrawDelay` (0.25 s with the clock, 1 s without); on the watch in always-on mode
  (`isLuminanceReduced`) once a minute with `setAmbient(true)`.
- **Touch**: a zero-distance `DragGesture` feeds `pointerDown/pointerMove/pointerUp`; a task
  fires `longPressElapsed()` when `longPressDeadline` passes with the finger still down; the
  Instrument's callbacks (`onHoroscopeTapped`, `onLongPress`, `onControlsChanged`,
  `onCalendarSelectionChanged`, `onRedrawRequested`) are wired by the host.
- **Accessibility**: the Canvas carries `accessibilityLabel(instrument.accessibilityDescription)`
  and the panels are ordinary SwiftUI controls.
- **Horoscopes**: generated on device with Apple's Foundation Models framework
  (`LanguageModelSession`, iOS 26+, Apple Intelligence devices), using SundialCore's prompt and
  clean-up from the Android `HoroscopeGenerator`; unavailable devices show why, as Android does
  when Gemini Nano is missing. Every reading can be reported (SundialCore's report form, posted
  with `URLSession`), as on Android.

## Where the apps differ from Android

Only where the platform requires it:

- **Wallpaper → widgets.** iOS cannot set the wallpaper. Android's Home wallpaper (the solar
  view, redrawn daily) and Lock wallpaper (the Earth view, every 15 minutes) become two Home
  Screen / StandBy widgets, *Sundial* and *Sundial Earth View*, both redrawn every quarter hour;
  the Lock Screen gets tinted accessory summaries (the year dial, the Moon, the season). A widget
  extension has about 30 MB, so the widgets let their Instrument go after every image and draw
  the solar view at no more than 2× and the Earth view at 1× (softer than the screen): SundialKit's
  sweep-gradient rings and their CGImages are cached process-wide, outlive every Instrument, and
  under the Earth view's zoomed camera are far larger than the widget. On a tinted or clear Home
  Screen (iOS 18+) the instrument keeps its full colour. Unlike the wallpaper, the widgets do not
  show today's reading yet: SundialKit's wallpaper path titles its second card "CONTINUED ·
  CELESTIAL WALLPAPER", with no AI disclosure, and a widget cannot report it. Like the wallpaper,
  they always draw the northern hemisphere: the phone's SOUTHERN HEMISPHERE switch lives in the
  view only and is not saved, as on Android.
- **Watch face → complications.** Apple Watch has no custom faces.
- **Gemini Nano → Apple Foundation Models** (iOS 26+, Apple Intelligence devices).
- **Calendar access.** EventKit's prompt instead of Android's permission flow. The button on the
  explanation shown before iOS's own alert says CONTINUE (Android: ALLOW CALENDAR ACCESS), and
  once iOS no longer asks, OPEN SETTINGS (Android: ALLOW IN SETTINGS): the HIG and App Review
  (Guideline 5.1.1(iv)) do not allow "Allow" on a screen ahead of a permission alert.
- **Birth fields.** The number pad has no return key, so its keyboard bar carries NEXT (Android's
  IME_ACTION_NEXT: month → day → year → hour → minute) and DONE.
- **Top safe area.** In portrait on an iPhone with a Dynamic Island or a notch the instrument
  starts below it, so the clock and the Earth view's zone caption stay visible (Android's small
  punch-hole camera sits in the clock's gap). Elsewhere it fills the screen.
- **Today's reading in the menu** (not in the Android app). On those shorter instruments (the
  6.1- and 6.3-inch iPhones with an island or a notch, such as the 14, 15, 16, 16e and 17, and in
  the Earth view larger ones such as the 16 Plus and the Air) the band above the dial is under
  the horoscope card's 92-pt minimum, so SundialKit falls back to a single card with no "WRITTEN
  BY ON-DEVICE AI · TAP TO REPORT" caption and the reading cut to about four lines.
  The astrology menu therefore shows the whole reading under TODAY'S HOROSCOPE, with "Written by
  on-device AI · tap REPORT THIS READING to report", until SundialKit's fallback card keeps the
  caption and fits the reading.
- **Midnight** (not in the Android app, which looks again only on resume). The app keeps the
  screen on, and every AI reading shown must stay reportable, so at a new day, a new time zone or
  a clock change it takes down yesterday's reading and writes the new day's.
- **No QUIT** (iOS apps do not quit), and the WALLPAPER switches become a note on adding widgets
  (its Home Screen steps follow the system: Edit → Add Widget from iOS 18, the + button on 17).
