# Privacy policy: the Apple apps

To add to https://primitive.io/legal/sundial-privacy/ (source:
`PRIMITIVE/landing/src/legal/sundial-privacy.md`, and `sundial-android-native/play/privacy-policy.md`)
before the iOS app is submitted. The page's other sections already hold for the Apple apps —
calendar data stays on the device, birth details stay on the device, reports are optional — except
the Google ML Kit paragraph, which is Android only.

Proposed section, after "The Sundial watch face":

```html
<h2>Sundial for iPhone, iPad and Apple Watch</h2>

<p>Sundial for Apple devices (bundle identifier <code>com.metavirtuoso.sundial</code>, with its widgets and Apple Watch app) works as described above, with these differences. Calendar events are read through Apple&rsquo;s EventKit, only after you allow calendar access, and never leave your device. Daily horoscopes are written on your device by Apple&rsquo;s Foundation Models (Apple Intelligence), where available; your birth details and the reading are processed on the device and are not sent to us or to Apple by Sundial. The Apple apps contain no Google ML Kit and no other third-party code that collects data. Settings are shared between the iPhone or iPad app and its widgets, and separately between the Apple Watch app and its complications; they are not synced between your iPhone and your Apple Watch, and may be included in your iCloud or device backups. The only information that leaves your device is a reading you choose to report, as described above.</p>
```

Also change the introduction's "Android package <code>com.metavirtuoso.sundial</code>" to cover
both platforms (for example "on Android and on Apple devices").
