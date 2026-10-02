# Releasing Sundial on the App Store

The iOS app ships as one App Store product: `Sundial.app` (`com.metavirtuoso.sundial`) with its
widget extension and the Apple Watch app embedded (the watch app carries its complications). It
is version **3.1.0**, like the Android release; the source build number is **2**. Building and
running are in [`Apps/README.md`](../Apps/README.md). App Store answers (privacy label, privacy
manifest, age rating, review notes) are in [`AppStore/APP-PRIVACY.md`](../AppStore/APP-PRIVACY.md);
listing text is in `AppStore/metadata/en-US/`.

In order:

1. [Enrol](#1-apple-developer-program) in the Apple Developer Program.
2. [Register](#2-certificates-identifiers--profiles) the App Group and the four bundle ids.
3. [Put the Team ID](#3-signing-in-the-project) in `Apps/project.yml`.
4. [Create the app](#4-the-app-store-connect-record) in App Store Connect and fill in its
   information, privacy and age rating.
5. [Archive and upload](#5-archive-and-upload) a build.
6. [Test it](#6-testflight) with TestFlight, internally and then externally.
7. [Add screenshots](#7-screenshots), the [review notes](#8-app-review) and submit.
8. [Publish the privacy policy paragraph](#9-privacy-policy) before submitting.

[CI](#10-ci) and the [checklist for each release](#11-each-release) follow.

## 1. Apple Developer Program

https://developer.apple.com/programs/enroll/ — 99 USD a year (or the local price). Enrol with
the Apple Account you will keep for the app; it needs two-factor authentication. Use the Apple
Developer app on the iPhone or the website.

**Individual or organization?** The choice decides the seller name shown under the app on the
App Store, and it is hard to change later.

| | Individual | Organization ("Metavirtuoso") |
|---|---|---|
| Seller name on the App Store | your legal name | the organization's legal name |
| Needs | your legal name and address | a legal entity (LLC, company, etc.; a trade name or DBA does not count), a D-U-N-S Number for it, a website on the organization's own domain (ideally an email address on it too), and the legal authority to bind it |
| Time | usually within a day or two | the D-U-N-S Number (free through Apple's lookup) can take several business days, then Apple verifies the entity, sometimes by phone |
| Other people | App Store Connect users (testers, marketing) can be invited; the developer account itself is yours alone | team members with roles in both the developer account and App Store Connect |

The Google Play account is a personal account (see `sundial-android-native/play/TESTING.md`), and
"Metavirtuoso" is the developer name, not necessarily a registered company. So:

- If Metavirtuoso **is** a registered legal entity (or you intend to register one before
  launch), enrol as an **organization** so the App Store shows "Metavirtuoso". Get the D-U-N-S
  Number first (https://developer.apple.com/enroll/duns-lookup/).
- Otherwise enrol as an **individual**; the App Store shows your own name. Apple Developer
  Support can convert an individual membership to an organization one later, and App Store Connect
  can transfer an app to another account, each with conditions, so this is not a trap, but it is
  work: prefer to start with the account you mean to keep.

**EU trader status.** App Store Connect asks every developer who distributes in the European
Union to declare whether they are a trader under the Digital Services Act (Business → your
account). A trader's address, phone number and email are shown on the EU product page; for an
individual that is personal contact information. Declare it before submitting, or limit
availability to non-EU storefronts until you do.

**Agreements.** The Program License Agreement covers free apps; Sundial is free and has no
in-app purchases, so the Paid Apps Agreement, tax and banking forms are not needed.

## 2. Certificates, Identifiers & Profiles

https://developer.apple.com/account/resources/identifiers/list

Xcode's automatic signing can register all of this on the first device build, but registering
it by hand once makes the capabilities explicit and avoids surprises on a new Mac or in CI.

**App Group.** Identifiers → + → App Groups → Description `Sundial`, Identifier
`group.com.metavirtuoso.sundial`. The app, its widgets, the watch app and its complications all
read and write their settings there (`UserDefaults(suiteName:)`): the app and its widgets in the
iPhone's or iPad's container, the watch app and its complications in the watch's own (the two are
not synced).

**App IDs.** Identifiers → + → App IDs → App, one explicit bundle id each:

| Description | Bundle ID (explicit) | Target |
|---|---|---|
| Sundial | `com.metavirtuoso.sundial` | iOS app |
| Sundial Widgets | `com.metavirtuoso.sundial.widgets` | iOS widgets |
| Sundial Watch | `com.metavirtuoso.sundial.watchkitapp` | watch app |
| Sundial Watch Widgets | `com.metavirtuoso.sundial.watchkitapp.widgets` | complications |

The ids are permanent once a build is uploaded; the extensions' ids must start with their
container's id, as these do.

**Capabilities.** Tick **App Groups** on each of the four and, under Configure, select
`group.com.metavirtuoso.sundial`. Nothing else: calendar access (EventKit) and Apple's Foundation
Models need no capability, WidgetKit needs none, and the report form is an ordinary HTTPS request.
There is no iCloud, push notification, HealthKit or Sign in with Apple.

**Certificates and profiles.** With automatic signing Xcode creates the Apple Development
certificate for each Mac and uses a cloud-managed Apple Distribution certificate when uploading;
provisioning profiles are managed too. Nothing to create by hand. (With manual signing you would
need a distribution certificate and four App Store profiles, one per bundle id.)

**Devices.** For development builds, devices are registered when you run on them from Xcode.
TestFlight and App Store builds need no device registration.

## 3. Signing in the project

`Apps/project.yml` uses automatic signing (`CODE_SIGN_STYLE: Automatic`) with an empty
`DEVELOPMENT_TEAM`. Fill in the ten-character Team ID (developer.apple.com → Account →
Membership details) under `settings.base`, then regenerate:

```bash
xcodegen generate --spec Apps/project.yml
```

The Team ID is not secret (it is in every signed app), so it can be committed with the
regenerated project.

## 4. The App Store Connect record

https://appstoreconnect.apple.com → Apps → + → **New App**:

| Field | Value |
|---|---|
| Platforms | iOS (the Apple Watch app ships inside the iOS app) |
| Name | `Sundial: Celestial Clock` (`AppStore/metadata/en-US/name.txt`; 30 characters at most, unique on the App Store) |
| Primary Language | English (U.S.) |
| Bundle ID | `com.metavirtuoso.sundial` (registered in step 2) |
| SKU | `SUNDIAL-IOS` (any unique string; only you see it and it cannot be changed) |
| User Access | Full Access |

Then, in the app's pages:

- **App Information:** subtitle (`subtitle.txt`), category **Lifestyle** (as on Google Play;
  secondary optional, e.g. Utilities), content rights (below), age rating (the questionnaire,
  answered as in `AppStore/APP-PRIVACY.md`).
- **Content rights:** the app bundles `sundial_condensed.ttf` and `earth_texture.png`. The font
  is Sundial Condensed, the Android app's face: a static instance (width 76, weight 500) of
  [Archivo](https://github.com/Omnibus-Type/Archivo), Copyright 2020 The Archivo Project
  Authors, under the SIL Open Font License 1.1, which allows embedding it in an app. Its licence
  ships beside it in every bundle (`sundial-condensed-OFL.txt`, from the Android repository's
  `licenses/`). Earth-image provenance, source URL, credits and bundled hash are verified in
  `AppStore/NASA-BLUE-MARBLE.md`; include its credit in review notes and do not imply NASA endorsement.
- **Pricing and Availability:** Free; all countries (see EU trader status above). Under
  "iPhone and iPad Apps on Apple Silicon Macs" and "Apple Vision Pro", untick availability unless
  you have tried the app there: widgets and calendar access behave differently on those
  platforms.
- **App Privacy:** the privacy policy URL (`https://primitive.io/legal/sundial-privacy/`) and the
  data-collection answers in `AppStore/APP-PRIVACY.md` (one type, Other User Content, optional,
  not linked, not tracking). They match the privacy manifests in `Apps/Resources/<Target>/`.
- **Version 3.1.0** (the iOS version page): description, keywords, promotional text, support
  and marketing URLs from `AppStore/metadata/en-US/`; copyright (e.g. `2026 Metavirtuoso`);
  screenshots (step 7); the build (step 5); App Review Information (step 8); version release
  (manual or automatic after approval).

**Export compliance** is answered in the build itself: every target's Info.plist has
`ITSAppUsesNonExemptEncryption = NO` (only HTTPS through the system), so App Store Connect does
not ask on each upload.

## 5. Archive and upload

Versions: `MARKETING_VERSION` (3.1.0) and `CURRENT_PROJECT_VERSION` (the build number) are set
once, project-wide, in `Apps/project.yml`, so the app and its three extensions always agree, as
the App Store requires. Every upload needs a build number higher than the last one for that
version.

In Xcode:

1. Scheme **Sundial**, destination **Any iOS Device (arm64)**.
2. Product → **Archive** (Release). The archive contains the iOS app, its widgets, and the watch
   app with its complications.
3. Organizer → Distribute App → **TestFlight & App Store** (or **TestFlight Internal Only** for a
   build that should never go to review) → Distribute.

Processing takes a few minutes to an hour; App Store Connect emails when the build is ready.
Apple also emails if the upload has a problem (a missing icon size, a privacy-manifest or
Info.plist error, an invalid entitlement).

Without a Mac, the `TestFlight` workflow does the same on GitHub's macOS runners (see [CI](#10-ci)).

## 6. TestFlight

App Store Connect → the app → **TestFlight**. Builds expire after 90 days.

**Internal testing** (up to 100 people who are users of your App Store Connect team, with any
role): no review. Create an internal group, add the testers, and turn on automatic distribution
so each new build reaches them as soon as it is processed. As an individual developer, you are
the one internal tester unless you add users under Users and Access.

**External testing** (up to 10,000 people, by email invitation or a public link): the first
build of each version goes through Beta App Review (usually within a day); later builds of the
same version usually do not need a full review. Fill in the Test Information first:

- What to Test, and a beta app description (from the listing text);
- feedback email: themetavirtuoso@gmail.com;
- marketing and privacy policy URLs;
- Beta App Review information: contact details, "no sign-in required", and the review notes
  from `AppStore/APP-PRIVACY.md`.

Testers install the TestFlight app on their iPhone or iPad and accept the invitation (or open
the public link). The Apple Watch app installs on the paired watch with the iPhone app, when
automatic app install is on in the Watch app; otherwise from the Watch app → Available Apps.

Unlike Google Play for new personal accounts, the App Store requires no closed test of a minimum
size or length; TestFlight is for finding problems. Try at least:

- an iPhone on **iOS 17** (the oldest supported release: the app must launch without Foundation
  Models), and one on iOS 26 or later with Apple Intelligence on (horoscopes are written);
- an iPad in portrait and landscape, and in Split View or Stage Manager;
- an Apple Watch on watchOS 10 or later: the app, always-on, and the complications;
- the Home Screen widgets, Sundial and Sundial Earth View, at every size on a 3× iPhone (a blank
  or placeholder widget means the extension ran out of its ~30 MB; measure it with Instruments'
  Allocations and VM Tracker, no debugger attached, at the large size with Brass Watch), and
  that tapping Sundial Earth View flies the app to the Earth view; and the Lock Screen widgets;
- calendar access: allow, deny, and change it later in Settings;
- astrology mode, and reporting a reading (check the report arrives in the Google Form).

An invitation, adapted from the Android one (`sundial-android-native/play/TESTING.md`):

> Subject: Help test Sundial on iPhone and Apple Watch
>
> Sundial is a clock that shows the Sun, Earth, Moon and planets as one dial, with a fly-in Earth
> view, your calendar on the dials, widgets, an Apple Watch app and an optional astrology mode.
> Would you try it before it launches?
>
> 1. On your iPhone, install TestFlight from the App Store.
> 2. Open this link on the iPhone and install Sundial: PUBLIC_LINK
> 3. Tap the Sun, try the corner menus, add a widget, and if you have an Apple Watch, open Sundial
>    there and add a complication.
>
> Send feedback from TestFlight (take a screenshot, then Share Beta Feedback) or by email to
> themetavirtuoso@gmail.com. Thank you!

## 7. Screenshots

App Store Connect → the version page → Previews and Screenshots. One to ten screenshots per
device size, PNG or JPEG without transparency, all of one size within a set. They follow the
Android storyboard (`sundial-android-native/play/graphics/`): Solar view, Earth view, Brass
Watch with astrology, Brass Earth view, Galactic view, settings, astrology menu, calendars; and
the Wear OS set for the watch.

| Set | Required | Size (portrait) | Captured on |
|---|---|---|---|
| iPhone 6.9" | yes | 1320 × 2868 (also accepted: 1290 × 2796) | iPhone 17 Pro Max simulator |
| iPad 13" | yes, the app runs on iPad | 2064 × 2752 (also accepted: 2048 × 2732; landscape too) | iPad Pro 13-inch simulator |
| Apple Watch | yes, the app includes a watch app | one size for the whole set: 422 × 514 (Ultra 3), or e.g. 416 × 496 (Series 10/11, 46 mm) | Apple Watch Ultra 3 (49 mm) simulator |

App Store Connect scales them down for smaller devices. Check the current list in App Store
Connect Help → Screenshot specifications, as Apple adds sizes with new devices.

**They are made by CI.** The `Apple` workflow (`.github/workflows/apple.yml`) runs
`SundialUITests/ScreenshotTests` (the `Sundial` scheme's test action) on the iPhone and iPad
simulators and launches the watch app on a watch simulator, all in the apps' screenshot mode:
launch arguments (`-screenshotScene`, `-screenshotMenu`, `-screenshotInstant`,
`-screenshotZone`) freeze the instrument at one moment with the sample calendars, birth date and
reading of Android's `StoreAssetsCapture`, and touch nothing on the device (no permission
prompts, EventKit, Foundation Models or network). The workflow run's `app-store-screenshots`
artifact holds the files, named for their set (`iPhone-6.9-…`, `iPad-13-…`, `Watch-Ultra-…`);
they replace the drafts in `AppStore/screenshots-draft/`. Upload them in order.

By hand, the same scenes come from a simulator: run the app with those launch arguments (Edit
Scheme → Run → Arguments) and take File → Save Screen, or
`xcrun simctl io booted screenshot 1-solar-view.png`. Use sample data only, never your own
calendars or birth details.

## 8. App Review

On the version page, App Review Information:

- Sign-in required: **No**.
- Contact: your name, phone and email (themetavirtuoso@gmail.com).
- Notes: paste "Notes for App Review" from `AppStore/APP-PRIVACY.md` (the Sun/Earth taps, the
  corner menus, calendar access only on request, astrology off by default with on-device
  Apple Intelligence and the explanation where it is unavailable, reporting a reading, the
  widgets and the watch app with complications).

Then Add for Review → Submit. Review usually takes a day or two. If it is rejected, answer in
App Review's message in App Store Connect, fix, upload a new build (a higher build number) and
resubmit.

## 9. Privacy policy

The published policy (https://primitive.io/legal/sundial-privacy/, source
`PRIMITIVE/landing/src/legal/sundial-privacy.md`, kept in step with
`sundial-android-native/play/privacy-policy.md`) must cover the Apple apps before the app is
submitted. Add this section after "The Sundial watch face" (from
`AppStore/privacy-policy-apple.md`, which remains the source):

```html
<h2>Sundial for iPhone, iPad and Apple Watch</h2>

<p>Sundial for Apple devices (bundle identifier <code>com.metavirtuoso.sundial</code>, with its widgets and Apple Watch app) works as described above, with these differences. Calendar events are read through Apple&rsquo;s EventKit, only after you allow calendar access, and never leave your device. Daily horoscopes are written on your device by Apple&rsquo;s Foundation Models (Apple Intelligence), where available; your birth details and the reading are processed on the device and are not sent to us or to Apple by Sundial. The Apple apps contain no Google ML Kit and no other third-party code that collects data. Settings are shared between the iPhone or iPad app and its widgets, and separately between the Apple Watch app and its complications; they are not synced between your iPhone and your Apple Watch, and may be included in your iCloud or device backups. The only information that leaves your device is a reading you choose to report, as described above.</p>
```

Also change the introduction's "Android package <code>com.metavirtuoso.sundial</code>" to cover
both platforms (for example "on Android and on Apple devices"), and update the effective date.
The App Privacy answers in App Store Connect and the privacy manifests must stay in step with
the policy.

## 10. CI

**Checks and screenshots: `.github/workflows/apple.yml`** (the `Apple` workflow, on every push
and pull request, on a macOS runner with Xcode 27; nothing is signed). It runs `swift test` for
SundialKit, builds the `Sundial` scheme (the iOS app, its widgets and the embedded watch app) for
the iOS Simulator and the `SundialWatch` scheme for the watchOS Simulator, then captures the App
Store screenshots (step 7) and uploads them as the `app-store-screenshots` artifact. See the
workflow's header for the details.

The workflow builds the **committed** `Apps/Sundial.xcodeproj`; it does not run XcodeGen. So
after every change to `Apps/project.yml`, and after adding, removing or renaming a file, run
`xcodegen generate --spec Apps/project.yml` and commit the project together with the generated
`Apps/Resources/*/Info.plist` and `*.entitlements`. The `Sundial` scheme's test action must keep
`SundialUITests`, which the screenshot step runs.

**Uploading to TestFlight: `.github/workflows/testflight.yml`** (the `TestFlight` workflow). It
archives the `Sundial` scheme on a GitHub macOS runner, signs it for the App Store and uploads it
to App Store Connect, on an annotated `v*` tag
(`git tag -a v3.1.0 -m "Sundial Apple 3.1.0" && git push origin v3.1.0`) or by hand
(Actions → TestFlight → Run workflow). No Mac is involved: signing is automatic ("cloud
signing"), so Xcode creates the distribution certificate and profiles through the API key and
nothing is stored in the repository. The build number is the workflow's run number, so every
upload is higher than the last; the version is `MARKETING_VERSION` from `Apps/project.yml`.

It needs four repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | the key's Key ID |
| `ASC_ISSUER_ID` | the Issuer ID shown above the keys list |
| `ASC_KEY_P8` | the whole contents of the downloaded `AuthKey_<KEY_ID>.p8` (downloadable once) |
| `APPLE_TEAM_ID` | the ten-character Team ID (not secret; a repository variable works too) |

Create the key in App Store Connect → Users and Access → Integrations → App Store Connect API →
**Team Keys**, with the **Admin** role (or App Manager with access to Certificates, Identifiers &
Profiles): cloud signing needs to create certificates and profiles. Only you should create the
key and paste it into GitHub; it never belongs in the repository or in a chat.

The workflow does not create the App Store Connect record: the record (step 4), and the bundle
ids and App Group (step 2), must exist before the first upload. After processing, the build
appears in TestFlight (step 6).

**Xcode Cloud** is the alternative (included with the membership, 25 compute hours a month): in
Xcode, Integrate → Create Workflow for the `Sundial` scheme, with an **Archive – iOS** action,
deployment preparation "TestFlight and App Store", and a post-action that sends the build to the
internal TestFlight group. It needs a Mac once, to create the workflow.

## 11. Each release

1. Raise `MARKETING_VERSION` (a new version) or `CURRENT_PROJECT_VERSION` (a new build of the
   same version) in `Apps/project.yml`, in step with the Android `versionName`; regenerate and
   commit the project (CI builds the committed one).
2. `swift test` at the repository root; build both schemes (`Apps/README.md`).
3. Commit the release, create an annotated `vX.Y.Z` tag matching `MARKETING_VERSION`, and push
   the commit and tag. Never move a published release tag. The tag starts the TestFlight workflow.
4. Archive and upload (step 5, or CI); try it through internal TestFlight on an iOS 17 device, an
   Apple Intelligence device, an iPad and a watch.
5. If anything the app collects or accesses changed, update the privacy manifests
   (`Apps/Resources/<Target>/PrivacyInfo.xcprivacy`), `AppStore/APP-PRIVACY.md`, the App Privacy
   answers and the privacy policy together.
6. Create the new version in App Store Connect ("What's New" from the Android release notes),
   refresh screenshots if the look changed, select the build and submit.
