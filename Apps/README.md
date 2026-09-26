# Sundial for iPhone, iPad and Apple Watch

The Apple apps: an iOS app (iPhone and iPad) with Home Screen and Lock Screen widgets, and a
watchOS app with complications, all drawing the instrument from SundialKit, the Swift package at
the repository root. The architecture and the contracts between the parts are in
[`docs/APPS.md`](../docs/APPS.md); releasing is in [`docs/RELEASE.md`](../docs/RELEASE.md).

| Target | Platform | Bundle id |
|---|---|---|
| `Sundial` | iOS 17+, iPhone and iPad | `com.metavirtuoso.sundial` |
| `SundialWidgets` | iOS WidgetKit extension, embedded in Sundial | `com.metavirtuoso.sundial.widgets` |
| `SundialWatch` | watchOS 10+ app, embedded in Sundial, also runs on its own | `com.metavirtuoso.sundial.watchkitapp` |
| `SundialWatchWidgets` | watchOS WidgetKit extension (complications), embedded in SundialWatch | `com.metavirtuoso.sundial.watchkitapp.widgets` |
| `SundialUITests` | iOS UI tests that capture the App Store screenshots (not shipped) | `com.metavirtuoso.sundial.uitests` |

## What you need

- A Mac with **Xcode 27** (Xcode 26 or later is required: the iOS app links Apple's Foundation
  Models framework, which older SDKs do not have). The apps still run on iOS 17 and watchOS 10.
- **XcodeGen** 2.46 or later: `brew install xcodegen`.
- For devices: an Apple Account signed in to Xcode (Settings → Accounts). A free account can run
  the apps on your own devices; TestFlight and the App Store need the Apple Developer Program
  (see `docs/RELEASE.md`).

There are no remote package dependencies: SundialKit is referenced by path, so nothing is
downloaded.

## Open the project

The Xcode project is generated from [`project.yml`](project.yml); do not edit the `.xcodeproj`
by hand. From the repository root:

```bash
xcodegen generate --spec Apps/project.yml
open Apps/Sundial.xcodeproj
```

Run `xcodegen generate` again whenever files are added, removed or renamed (in Xcode, a file
added by hand disappears on the next generation). Generation also writes each target's
`Info.plist` and `.entitlements` under `Resources/<Target>/` from `project.yml`: change them in
`project.yml`, not in the generated files.

The generated project is **committed**: CI (`.github/workflows/apple.yml`) builds
`Apps/Sundial.xcodeproj` as it is, without XcodeGen, and so can anyone without it. After
regenerating, commit the project together with `Resources/*/Info.plist` and `*.entitlements`.

### Signing

Signing is automatic and the team is left empty on purpose. Put your ten-character Team ID
(developer.apple.com → Account → Membership details, or Xcode → Settings → Accounts) in
`project.yml`:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: ABCDE12345
```

and regenerate. (Choosing the team in each target's Signing & Capabilities tab works too, until
the next generation.) Xcode then registers the four bundle ids and the App Group
`group.com.metavirtuoso.sundial` for you on the first device build, if your role in the team
allows it. Simulator builds usually work without a team; if Xcode asks for one, choose your
personal team (the command-line builds below turn signing off altogether).

## Run

| To try | Scheme | Destination |
|---|---|---|
| The iPhone / iPad app | `Sundial` | an iPhone or iPad simulator, or a device |
| The watch app | `SundialWatch` | a watch simulator (paired with an iPhone simulator), or a paired Apple Watch |
| Home and Lock Screen widgets | `Sundial`, then add the widget; or `SundialWidgets` | iPhone or iPad |
| Complications | `SundialWatch`, then edit a face; or `SundialWatchWidgets` | watch |

- **First run on a device:** turn on Developer Mode (Settings → Privacy & Security → Developer
  Mode on the iPhone; the same on the watch after the first install attempt) and trust the
  developer if asked.
- **The watch app** is embedded in the iPhone app, so installing `Sundial` on an iPhone offers it
  to the paired watch; running `SundialWatch` installs it directly (the first install on a real
  watch can take several minutes).
- **Widgets:** long-press the Home Screen → Edit → Add Widget (iOS 17: the + button) → Sundial;
  Lock Screen: long-press the Lock Screen → Customize → Lock Screen → the widget area. The widget
  schemes ask which app to launch; choose the Home Screen (or the watch face) and add the widget
  there. SwiftUI previews in the widget files are quicker for layout.
- **Complications:** on the watch (or simulator), long-press the face → Edit → Complications →
  Sundial.
- **Calendars:** the simulator's Calendar app starts empty; add a few events there first. The
  access prompt appears when you choose to show calendars in the calendar menu. To see it again:
  `xcrun simctl privacy booted reset calendar com.metavirtuoso.sundial`.
- **Horoscopes** (astrology menu) are written by Apple's on-device Foundation Models: iOS 26 or
  later on a device with Apple Intelligence turned on (or a simulator on a Mac that has Apple
  Intelligence turned on). Elsewhere the panel explains why no reading is available, as the
  Android app does without Gemini Nano.
- **Settings** are shared between the app and its widgets through the App Group
  `group.com.metavirtuoso.sundial`, and between the watch app and its complications in the same
  way on the watch. The iPhone's and the watch's App Group containers are separate, as the Wear
  OS app keeps its own settings.

### From the command line

```bash
xcodegen generate --spec Apps/project.yml
# The iOS app with its widgets and the embedded watch app (all four targets), unsigned:
xcodebuild -project Apps/Sundial.xcodeproj -scheme Sundial \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
# The watch app on its own:
xcodebuild -project Apps/Sundial.xcodeproj -scheme SundialWatch \
  -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The package's own tests run anywhere, including Linux: `swift test` at the repository root.

The App Store screenshots come from `SundialUITests/ScreenshotTests` (the `Sundial` scheme's test
action), which launches the app in its screenshot mode; CI runs it on an iPhone 17 Pro Max and
an iPad Pro 13-inch simulator (see the test's header and `docs/RELEASE.md`). Locally:

```bash
xcodebuild test -project Apps/Sundial.xcodeproj -scheme Sundial \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:SundialUITests/ScreenshotTests CODE_SIGNING_ALLOWED=NO
```

The screenshots are attachments in the result bundle (Xcode → Report navigator). The watch app
has the same screenshot mode (`Shared/ScreenshotScene.swift`); CI launches it on a watch simulator
with `xcrun simctl launch … -screenshotScene heliocentric-brass-astrology -screenshotInstant …
-screenshotZone …` and captures the screen with `simctl io`.

## Layout

```
Apps/
  project.yml            the XcodeGen spec (targets, settings, Info.plist keys, entitlements)
  Shared/                the instrument's model, view, screenshot mode (both apps), resources and
                         bitmap renderer (all four targets)
  Sundial/               the iOS app
  SundialWidgets/        the iOS widgets
  SundialWatch/          the watch app
  SundialWatchWidgets/   the complications
  SundialUITests/        ScreenshotTests: the App Store screenshots, in the Sundial scheme's test action
  Resources/
    Assets.xcassets      AppIcon (one 1024 px image for iOS and watchOS), AccentColor (the
                         Android panels' brass, #FFB34A), LaunchBackground and WidgetBackground (black)
    sundial_condensed.ttf, sundial-condensed-OFL.txt
                         the Android app's label face, Sundial Condensed (Archivo, SIL Open Font
                         License 1.1), and its licence, bundled in all four targets
    earth_texture.png    a copy of ../Assets/, bundled in all four targets
    <Target>/            PrivacyInfo.xcprivacy (hand-written); Info.plist and <Target>.entitlements
                         (generated from project.yml)
```

`Shared/` is compiled whole into both apps. The two widget extensions, which are built with
`APPLICATION_EXTENSION_API_ONLY`, take only `SundialResources.swift` and `InstrumentImage.swift`
(listed in `project.yml`'s `WidgetExtension` template): code in those two files must not use
`UIApplication.shared` or other app-only API, and a new Shared file reaches the extensions only if
it is listed there too. Resources belong in `Resources/` and `project.yml`, never in `Shared/` or a target
folder twice, or Xcode reports "Multiple commands produce".

If the texture or the icon change in `../Assets/`, or the font in the Android app, copy them again:

```bash
cp Assets/earth_texture.png Apps/Resources/
cp Assets/AppIcon-1024.png Apps/Resources/Assets.xcassets/AppIcon.appiconset/
cp ../sundial-android-native/core/src/main/res/font/sundial_condensed.ttf \
   ../sundial-android-native/licenses/sundial-condensed-OFL.txt Apps/Resources/
```

## Troubleshooting

- **"No such module 'SundialCore'"** or a package error: File → Packages → Reset Package
  Caches, then build again. The package must build for iOS and watchOS (`Package.swift` declares
  both).
- **"Provisioning profile doesn't include the App Groups entitlement"**: the App Group is not
  registered for that bundle id yet; see `docs/RELEASE.md` → Identifiers, or let Xcode fix it
  under Signing & Capabilities.
- **The watch app does not appear on the watch**: open the Watch app on the iPhone → My Watch →
  Available Apps → Sundial → Install, or run the `SundialWatch` scheme on the watch.
- **Widgets show old content after a code change**: remove the widget and add it again, or
  restart the simulator; WidgetKit caches timelines.
