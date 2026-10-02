# App Store Connect: App Privacy, age rating and review

Answers for the iOS app (with its widgets and Apple Watch app). They follow what the code does;
check them against the shipped build before submitting.

## App Privacy ("nutrition label")

**Do you or your third-party partners collect data from this app?** Yes — one type, only when
the person chooses to report an AI-written reading.

| Data type | Collected | Linked to the user | Used for tracking | Purpose |
|---|---|---|---|---|
| User Content → Other User Content (the text of a reported reading, the reason chosen, the date and the app version) | Yes, optional | No | No | App Functionality (reviewing reported AI content) |

Not collected: calendar events (read on the device only), birth date and time, horoscope text
(unless reported), location, contacts, identifiers, usage data, diagnostics. Horoscopes are
written by Apple's on-device Foundation Models, which send nothing to us.

Reports go to a Google Form over HTTPS; there are no third-party SDKs in the app.

**Privacy policy URL:** https://primitive.io/legal/sundial-privacy/ (add a paragraph for the
Apple apps before submitting; see `docs/RELEASE.md`).

## Privacy manifest

Each target ships `PrivacyInfo.xcprivacy`: no tracking, no tracking domains, the collected data
type above (not linked, not tracking, App Functionality), and the required-reason APIs:
`NSPrivacyAccessedAPICategoryUserDefaults` (CA92.1; 1C8F.1 for the App Group: on the iPhone or
iPad it is shared by the app and its widgets, and separately, on the watch, by the watch app and
its complications) and `NSPrivacyAccessedAPICategorySystemBootTime` (35F9.1: the
instrument's animation clock uses `ProcessInfo.systemUptime`).

## Age rating

No violence, sexual content, profanity, drugs, gambling, horror or mature themes; no
unrestricted web access; no user-generated content shared with others; no messaging. The optional
astrology mode shows short AI-written horoscopes for entertainment: answer the questionnaire's
AI / generated-content questions accordingly. Expected rating: 4+ (or 9+ if the generated-content
answer raises it).

## Export compliance

`ITSAppUsesNonExemptEncryption` is `NO`: the app uses only HTTPS through the system.

## Notes for App Review

- No account or sign-in; every feature is available immediately.
- The Earth texture is a color-adjusted derivative of NASA Visible Earth's 2002 Blue Marble
  "Land Surface, Ocean Color and Sea Ice" map. Source, credit, bundled-file hash and NASA media
  guidance are recorded in `AppStore/NASA-BLUE-MARBLE.md`; the app does not imply NASA endorsement.
- Tap the Sun to fly to the Earth view; tap the Earth to return. Drag the Earth (Sun view) or
  the Moon (Earth view) to move through time; "Return to now" is in the settings menu (top left).
- Calendars (bottom-left menu) ask for calendar access only when the reviewer chooses to show
  calendars; events are read-only and never leave the device.
- Astrology (bottom-right menu) is off by default. With a birth date and time entered, a
  horoscope is written on the device by Apple Intelligence where available (otherwise the app
  explains why it is unavailable). Tap a reading to report it.
- Widgets: add "Sundial" (the solar view) or "Sundial Earth View" from the Home Screen widget
  gallery, and "Sundial" from the Lock Screen widget gallery.
- Apple Watch: an interactive orrery, not a watch face. Turn the Digital Crown to move through
  time; tap the Sun / Earth as on iPhone. Touch and hold the dial to open settings (Clock,
  Astrology, Southern hemisphere, Galactic view, Return to now, and the aesthetic); with
  VoiceOver, use the "Settings" action. The time readout is optional (the Clock switch in
  settings). Because Apple Watch has no custom faces, Sundial comes to the user's own watch face
  as complications (Year Dial, Moon and Season, Instrument, Season and Moon): touch and hold a
  watch face → Edit → Complications → choose a slot → Sundial.
