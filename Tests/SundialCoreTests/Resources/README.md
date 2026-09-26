# android-reference.json

Outputs of the Android app's pure functions over many inputs, for SundialCore's tests to compare
against value for value. The file is generated, never edited by hand:

```bash
cd ../sundial-android-native
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 ./gradlew :app:testDebugUnitTest --tests '*SwiftReferenceTest*'
cp app/build/swift-reference.json ../sundial-apple/Tests/SundialCoreTests/Resources/android-reference.json
```

The generator is `sundial-android-native/app/src/test/java/com/metavirtuoso/sundial/SwiftReferenceTest.kt`.
It is a JVM unit test in the app module, so it calls `:core` and `:app` code directly;
`SeasonBands`, `GalacticGeometry`, `EarthOrientation` and `ZodiacPreferences.preserveNatalData`
are internal to `:core` and are called by reflection. Three things live inside functions that need a
model, the network or an Android View, so the generator copies them: the horoscope prompt and its
clean-up (`HoroscopeGenerator.generate`), the report form body (`ReadingReporter.send`) and the
star fields (`SundialView.ambientStars`, `dustLaneStars`). The test fails if those source lines
change without the copy being updated.

Generated with JDK 21.0.12.1, Kotlin 2.3.21, tzdb 2026b, app 3.0.0 (14). About 4.7 MB, 73 keys.

## File layout

One JSON object. `_meta` is an object; every other key is an array of records.

```json
{
"_meta": {...},
"Astronomy.julianDate": [
  {"instant": -631152000000, "output": 2433282.5},
  ...
],
...
}
```

Keys are `KotlinObject.function` (or `KotlinType` for enum tables and `….constants` for
constants). Each record holds its inputs, then `output`; a few carry extra fields, listed below.

## Encoding conventions

| What | How it is written |
|---|---|
| Instant input (`instant`) | integer epoch milliseconds. `Date(timeIntervalSince1970: Double(ms) / 1000)` |
| Instant output | `{"epochSecond": Int64, "nano": Int, "epochMillis": Int64}` (Java `Instant`: `nano` is 0..999 999 999 and always positive, so `epochMillis` is the floor) |
| ZonedDateTime output | `{"epochMillis": Int64, "offsetSeconds": Int, "local": "yyyy-MM-ddTHH:mm:ss.SSS", "zone": IANA id}` |
| Zone | IANA id string (`"UTC"`, `"America/Los_Angeles"`, …). `TimeZone(identifier:)` |
| LocalDate | `"yyyy-MM-dd"` string, except `BirthDateInput.parse` output: `{"year", "month", "day"}` |
| LocalTime | `{"hour", "minute", "second"}` (inputs); `BirthTimeInput.parse` output is `{"hour", "minute"}` |
| Enum value | Kotlin constant name: `"SAGITTARIUS"`, `"FALL"`, `"MERCURY"`, `"OFFENSIVE"`. The Swift case is the name lowercased (`.sagittarius`) — every one is a single word |
| Double | Java `Double.toString`, the shortest decimal that round-trips (`2451545.0`, `9.742726057858796E-17`, `-0.0`) |
| Float | a Kotlin `Float` widened to `Double` exactly, e.g. `0.1935f` is `0.19349999725818634`. Fields that are Float are marked **(F)** below |
| Boolean hemisphere | `north` / `northernHemisphere`: `true` is the northern view |
| Strings | non-ASCII and control characters are `\uXXXX` escapes (UTF-16, so emoji are surrogate pairs) |
| Absent | `null` |

No NaN or infinity appears anywhere.

**Decode with `JSONDecoder`, not `JSONSerialization`.** On Linux, swift-corelibs-foundation's
`JSONSerialization` misrounds some doubles by 1–2 ulp (e.g. a `julianDate` output). `JSONDecoder`
decoded all 164,379 numbers in this file bit-identically to a correctly rounded parser (checked with
Swift 6.4 on Linux). Integers fit in `Int64`, and every epoch-milliseconds value fits exactly in a `Double`.

### Tolerances

The values are what Android computes. Where they come from:

- **Exact**: integers, booleans, strings, enum names, `Random.*`, the star `alpha`/`flare`, every
  `CalendarHitTesting` result, `localOffsetMinutes`, `daysInYear`, the `SeasonBands.mixAt`
  from/to seasons, and `signFor`/`seasonFor`.
- **Doubles from `+ − × ÷ %` only** (the DialGeometry angle functions, `normalize*`, `SeasonBands`,
  `CalendarIntervals`, `monthStart`, `datelineHours`, `angleForOffsetMinutes`): usually bit-identical if
  the Swift code keeps Kotlin's order of operations; 1e-12 is safe. `civilYearFraction` and
  `continuousYear` are computed from nanoseconds in Kotlin and from a `Date` (a `Double` of seconds since
  2001, about 0.1 µs resolution) in Swift. Allow about 1e-12 of a year.
- **Doubles through sin/cos/atan2/pow** (Astronomy positions and angles, `geocentricLongitude`,
  `EarthOrientation`): the JVM's `Math.sin` etc. and Apple's or glibc's libm may differ in the last
  ulp, and Kepler's iteration or the lunar series can amplify that. Use 1e-9 (degrees or AU).
- **Instants** (`instantAtYearFraction`, `GalacticGeometry.instantAt`): `nano` is exact in Kotlin; a Swift
  `Date` holds about 0.1 µs, so compare to about 1 µs.
- **(F) Float fields**: Kotlin computes these in `Float`; the Swift port uses `Double` (PORTING.md). Use
  a relative tolerance of 1e-6. The star fields are the exception, because the Swift port draws from
  `KotlinRandom.nextFloat()`, which returns `Float`: computed in `Float` the way Kotlin does
  (`Float(cos(Double(angle)))`: Kotlin's `cos(Float)` is `Math.cos(x.toDouble()).toFloat()`, likewise
  `sin`, `sqrt` and `pow`), they should match exactly.
- Wrap-around outputs (angles near 0/360, fractions near 0/1, a sign on a 30° boundary) can land on the
  other side from a 1-ulp difference. Compare circular values modulo the period, and treat a boundary
  miss as an issue to look at, not a hard failure.

## Shared input sets

- **Common instants** (~207): 37 fixed instants (1950-01-01, 1969-12-31T23:59:59.999Z, the epoch,
  J2000 = 2000-01-01T12:00Z, the leap days 1952/2000/2024/2096, the ends of 1999/2023/2024/2100, the
  2024 equinoxes and solstices, US and UK DST changes, 2038-01-19T03:14:07Z, 2100-12-31T23:59:59.999Z …)
  plus 170 instants from 1950 to 2100, 322 days 7:13:17.123 apart.
- **Zones** (`_meta.zones`): UTC, America/Los_Angeles, Asia/Kolkata, Australia/Lord_Howe (30-minute
  DST), Pacific/Chatham (+12:45), America/St_Johns (−3:30), Europe/London, and America/Santiago
  (DST changes at local midnight, so some days start at 01:00).
- **Zone cases** (2,040 (zone, instant) pairs): for each zone, the common instants plus, for each offset
  transition in 2024 and 2025, the transition −1 h, −30 min, −1 ms, 0, +1 ms, +30 min, +59:59.999,
  +1 h, +2 h, the start of that local day and the last millisecond of it; plus local midnight of
  1 January 1950/2000/2024/2025/2026/2100, −1 ms, 0 and +1 ms. Instants in the hour after a fall-back
  transition are inside the repeated (overlap) hour.

## Keys and record fields

### `_meta`

`{"generator", "javaVersion", "kotlinVersion", "tzdbVersion", "appVersion", "zones": [IANA id]}`

### Astronomy (astronomy/Astronomy.kt)

| Key | Record |
|---|---|
| `Astronomy.constants` | `{"name", "swiftName", "type": "Double", "value"}`: `JULIAN_DATE_UNIX_EPOCH`, `JULIAN_DATE_J2000`, `SYNODIC_MONTH_DAYS` |
| `Astronomy.Body` | `{"name", "ordinal"}` in declaration order |
| `Astronomy.julianDate` | `{"instant", "output": Double}` |
| `Astronomy.heliocentricPosition` | `{"body", "instant", "output": {"x", "y", "z", "radius", "longitudeDegrees"}}` for all four bodies (`radius` and `longitudeDegrees` are the `Vector3` properties) |
| `Astronomy.greenwichMeanSiderealDegrees` | `{"instant", "output"}` |
| `Astronomy.moonLongitudeDegrees` | `{"instant", "output"}` |
| `Astronomy.moonPhaseDegrees` | `{"instant", "output"}` |
| `Astronomy.sunLongitudeOfDate` | `{"instant", "output"}` |
| `Astronomy.precessionDegrees` | `{"instant", "output"}` |
| `Astronomy.daysInYear` | `{"year", "output": Int}` (years 1 … 9999, including 1900, 2000, 2023, 2024, 2100, 2400) |
| `Astronomy.civilYearFraction` | `{"instant", "zone", "offsetSeconds", "local", "output"}` for the zone cases. The input is `ZonedDateTime(instant, zone)`; `offsetSeconds` and `local` describe it, for debugging |
| `Astronomy.instantAtYearFraction` | `{"year", "fraction", "zone", "output": Instant}`. Years 1950, 1999, 2000, 2023–2026, 2099, 2100; fractions −0.5 … 1.5 (clamped by the function to [0, 0.999999999]); and, per zone, the fractions of its 2024/2025 transitions ±1e-7 |
| `Astronomy.normalizeDegrees` | `{"input", "output"}`: edges (±0, ±1e-300, ±1e-15, 360 ± 1 ulp, ±1e17, ±1e300 …) and grids |
| `Astronomy.normalizeSignedDegrees` | `{"input", "output"}`, the same inputs |

### Zodiac (astronomy/Zodiac.kt)

| Key | Record |
|---|---|
| `Zodiac.Sign` | `{"name", "ordinal", "displayName", "symbol", "element", "startMonth", "startDay"}` (symbols carry U+FE0E) |
| `Zodiac.Element` | `{"name", "ordinal"}` |
| `Zodiac.Season` | `{"name", "ordinal"}` |
| `Zodiac.signFor` | `{"date", "output": sign}` for every day of 2024 and 2025 |
| `Zodiac.signForLongitude` | `{"longitude", "output": sign}` for −720 … 1080 every 7.5°, plus edges |
| `Zodiac.seasonFor` | `{"date", "northernHemisphere", "output": season}` for every day of 2025, both hemispheres |
| `Zodiac.geocentricLongitude` | `{"body", "instant", "output"}` for MERCURY, VENUS, MARS at the common instants (EARTH is a precondition failure and is not recorded) |
| `Zodiac.sunLongitude` | `{"instant", "output"}` |
| `Zodiac.placements` | `{"instant", "output": [{"label", "symbol", "longitudeDegrees", "sign"}]}` (SUN, MOON, MERCURY, VENUS, MARS in order) at 7 instants |

### DialGeometry (ui/DialGeometry.kt)

| Key | Record |
|---|---|
| `DialGeometry.constants` | `{"name", "swiftName", "type": "Float" \| "Double", "value"}` for all 27 public constants plus `EARTH_UNIT`, which is private in Kotlin and recomputed as `MOON_DIAL / 67.5f`. Float constants were folded by the Kotlin compiler in Float arithmetic (so `HOUR_DIAL` is `60f * EARTH_UNIT` rounded to Float) |
| `DialGeometry.annualAngle` | `{"fraction", "north", "output"}`, fraction −0.25 … 1.25 every 1/64 plus a few |
| `DialGeometry.yearFractionFromAngle` | `{"angle", "north", "output"}`, angle −720 … 720 every 7.5 plus `JANUARY_FIRST_ANGLE` ± 360, ± 1e-9 and others |
| `DialGeometry.eclipticAngle` | `{"longitude", "north", "output"}` |
| `DialGeometry.hourAngle` | `{"hours", "north", "output"}`, hours −2 … 26 every 0.25 plus a few |
| `DialGeometry.minuteFromHourAngle` | `{"angle", "north", "output"}` (the same angles as `yearFractionFromAngle`) |
| `DialGeometry.moonAngle` | `{"phase", "north", "output"}` |
| `DialGeometry.phaseFromMoonAngle` | `{"angle", "north", "output"}` |
| `DialGeometry.yearEventBand` | `{"annualRadius" (F), "calendarIndex", "minThickness" (F), "output": {"centerRadius" (F), "thickness" (F)}}`. Radii 0, 1, 100, 250.5, 480, 512.75, 1234.567; indices −5, −1, 0, 1, 2, 3, 7, 12; minThickness 0, 4, 11.66, 24.5, 200. Call `yearEventBand(annualRadius, calendarIndex, minThickness: minThickness)` |
| `DialGeometry.dayEventBand` | `{"hourRadius" (F), "calendarIndex", "minThickness" (F), "output": {"centerRadius" (F), "thickness" (F)}}`, the same grid |
| `DialGeometry.earthFlightFrame` | `{"progress" (F), "output": {"cameraScale" (F), "earthSystemScale" (F), "skyScale" (F)}}`, progress −0.1 … 1.1 every 0.01, plus −1, 2, 0.5, 1e-6 |

### SeasonBands (ui/SeasonBands.kt)

| Key | Record |
|---|---|
| `SeasonBands.constants` | `{"name": "BLEND_DAYS", "swiftName", "type": "Double", "value": 12.0}` |
| `SeasonBands.starts` | `{"year", "output": [{"fraction", "season"}]}` (spring, summer, fall, winter) for 2023 … 2030 |
| `SeasonBands.mixAt` | `{"year", "fraction", "daysInYear", "output": {"from", "to", "amount"}}`. Call `mixAt(fraction, starts(year), daysInYear)`. For 2024 and 2025: every 4 hours of the year, each blend edge (start ± 12/days, ± 1e-12), and −0.02, −1e-9, 1, 1 + 1e-9, 1.02 |

### TimeZoneDial (ui/TimeZoneDial.kt)

| Key | Record |
|---|---|
| `TimeZoneDial.spokes` | `{"instant", "north", "output": [{"offsetHours", "angleDegrees", "localDate", "label"}]}`: 24 spokes, offsets −12 … 11 in order, at 29 instants (every tenth common instant plus exact hours, :07:30, 11:59:59.999, 12:30:30.5 …) |
| `TimeZoneDial.datelineHours` | `{"instant", "output"}` at the common and spoke instants |
| `TimeZoneDial.localOffsetMinutes` | `{"instant", "zone", "output": Int}` for the zone cases |
| `TimeZoneDial.angleForOffsetMinutes` | `{"instant", "offsetMinutes", "north", "output"}`: offsets −1080, −720, −660, −570, −480, −210, −150, 0, 330, 345, 525, 630, 765, 825, 840, 1080 at the spoke instants |
| `TimeZoneDial.localName` | `{"zone", "instant", "offsetMinutes", "output"}` for 52 zones (every named branch, and fallbacks with half-hour, 45-minute and ±14 h offsets) in January and July 2024. `offsetMinutes` is informational (the zone's offset then); the call is `localName(zone, instant)` |
| `TimeZoneDial.commonName` | `{"offsetHours", "output"}` for −14 … 16 |
| `TimeZoneDial.nearestSpoke` | `{"instant", "north", "angle", "output": offsetHours}`. The spokes are `spokes(instant, north: north)`; `output` is the `offsetHours` of the spoke returned. Angles −360 … 720 every 3.75 at 6 instants; exact-hour instants put spokes on multiples of 15°, so angles halfway between two spokes test the tie rule (Kotlin's `minBy` keeps the first, i.e. the lower offset) |

### GalacticGeometry (ui/GalacticGeometry.kt)

| Key | Record |
|---|---|
| `GalacticGeometry.constants` | `{"name", "swiftName", "type", "value"}`: `travelX`, `travelY`, `sideX`, `sideY`, `YEAR_PITCH`, `ORBIT_DEPTH` (Float), `MIN_YEAR`, `MAX_YEAR` (Int) |
| `GalacticGeometry.continuousYear` | `{"instant", "zone", "output"}` for the zone cases |
| `GalacticGeometry.instantAt` | `{"continuousYear", "zone", "output": Instant, "roundTrip"}`, where `roundTrip` is `continuousYear(output, zone)`. Inputs −5 … 12000 (clamped to [1, 9999.999999]) in every zone. Before the 1880s tzdb gives each zone its local mean time (Los Angeles −7:52:58), and java.time uses the proleptic Gregorian calendar |
| `GalacticGeometry.monthStart` | `{"year", "month", "output"}` for years 1, 1900, 1999, 2000, 2023, 2024, 2025, 2100, 9999 |
| `GalacticGeometry.orbitOffset` | `{"longitude", "orbitRadius" (F), "output": {"along" (F), "side" (F)}}`. `along` is the Kotlin pair's first (along travel), `side` its second |

### EarthOrientation (ui/EarthOrientation.kt)

| Key | Record |
|---|---|
| `EarthOrientation.constants` | `OBLIQUITY_DEGREES` (Double) |
| `EarthOrientation.projectedGeographicPole` | `{"north", "sunLongitude", "output": {"x", "y"}}`, longitude −360 … 720 every 5 plus a few |
| `EarthOrientation.screenToEquatorial` | `{"sx", "sy", "sz", "sunLongitude", "north", "output": {"x", "y", "z"}}` for 11 unit vectors and 21 longitudes |

### CalendarHitTesting (ui/CalendarHitTesting.kt)

| Key | Record |
|---|---|
| `CalendarHitTesting.containsYearFraction` | `{"touch", "start", "sweep", "padding", "output": Bool}`. A full grid over touches −0.5 … 1.5 every 1/16 plus a few, starts −0.125 … 1.25, sweeps 0 … 1.5, paddings −1/64 … 0.625. Mostly dyadic values, so boundaries are exact |
| `CalendarHitTesting.containsMinute` | `{"touch", "start", "endExclusive", "padding", "output": Bool}`, including ends before the start, full-day and longer spans, negative padding and wrap-around |

### Calendar (calendar/CalendarModels.kt, CalendarIntervals.kt)

| Key | Record |
|---|---|
| `DeviceCalendar.isGoogle` | `{"accountType", "output": Bool}` |
| `CalendarNormalizer.normalize` | `{"index", "raw": {"eventId", "calendarId", "title", "beginMillis", "endMillis", "allDay", "eventTimeZone", "color"}, "displayZone", "output": {"eventId", "calendarId", "title", "start": ZonedDateTime, "endExclusive": ZonedDateTime, "allDayStart": date \| null, "allDayEndExclusive": date \| null, "color", "isAllDay", "isYearRingEvent"}}`. 36 raw instances × the 8 zones: timed events across midnight, the DST gaps and overlaps of each zone, exactly 24 h and 1 ms under it, several days, zero-length and reversed (end coerced to begin + 1 ms), across a year end, a whole year, before 1970; all-day events on DST days, the Santiago day that starts at 01:00, a leap day, across a year end, a whole year, zero-length, and off-midnight all-day millis. `index` is the record's position in this array. `color` is a signed Int32 (ARGB `0xFF3366CC` is `-13408564`) |
| `CalendarIntervals.inDay` | `{"eventIndex", "day", "zone", "output": null \| {"startMinute", "endMinuteExclusive"}}`. The event is `CalendarNormalizer.normalize` record `eventIndex` (normalize its `raw` in its `displayZone`). Zones: the event's display zone and UTC. Days: from the day before the event to the day after it (the first and last four days when longer) |
| `CalendarIntervals.inYear` | `{"eventIndex", "year", "zone", "output": null \| {"startFraction", "sweepFraction"}}`, years from the one before the event to the one after |

### ZodiacProfile (ui/ZodiacPreferences.kt)

| Key | Record |
|---|---|
| `ZodiacProfile` | `{"enabled", "birthDate": date \| null, "birthTime": LocalTime \| null, "selectedSign": sign \| null, "today", "output": {"resolvedSign", "isComplete", "signature"}}`. `resolvedSign` is `resolvedSign(today)`. `signature` joins `enabled`, `birthDate`, `birthTime`, `selectedSign` with `|`, writing `null` for absent values, dates as `yyyy-MM-dd`, times as Java's `LocalTime.toString` (`"07:05"`, or `"23:59:30"` when seconds are non-zero) and signs by Kotlin name (`"PISCES"`) |
| `ZodiacPreferences.preserveNatalData` | `{"requested": profile, "stored": profile, "output": profile}`, where a profile is `{"enabled", "birthDate", "birthTime", "selectedSign"}` (all 49 pairs of 7 profiles) |

### Birth date and time entry (app ui/BirthDateInput.kt)

| Key | Record |
|---|---|
| `BirthDateInput.parse` | `{"month", "day", "year", "today", "output": null \| {"year", "month", "day"}, "error": null \| message}` |
| `BirthTimeInput.parse` | `{"hour", "minute", "pm", "output": null \| {"hour", "minute"}, "error": null \| message}` |

`error` is the `IllegalArgumentException` message. Kotlin behaviour these records pin down:

- `toIntOrNull` accepts a leading `+` or `-` and **any Unicode decimal digit** (fullwidth `１２`, Arabic-Indic
  `١٩٩٠`); Swift's `Int(_:)` accepts only ASCII digits. `"99999999999"` overflows to null.
- `trim()` strips Java whitespace **and** space separators: tab, newline, NBSP U+00A0, and U+001C–U+001F
  (so `"\u001f1976"` parses as 1976).
- The 4-character year check runs on the trimmed text before any other check, so `"+976"` is year 976 and
  `"-001"` is year −1. Years 0 and −1 are accepted.
- Error order: year length, month numeric, day numeric, year numeric, a valid date, not after `today`
  (equal to `today` is allowed). For times: hour numeric, minutes numeric, hour 1…12, minutes 0…59.

### Horoscope (app horoscope/HoroscopeGenerator.kt)

| Key | Record |
|---|---|
| `HoroscopeGenerator.prompt` | `{"enabled", "birthDate", "birthTime", "selectedSign", "instant", "zone", "date", "sign", "output": prompt}`. `date` is the local date of `instant` in `zone`; `sign` is `resolvedSign(date)`. The prompt is six lines joined by `\n` with no trailing newline; the placements come from `Zodiac.placements(instant)` |
| `HoroscopeGenerator.cleanResponse` | `{"input": String \| null, "output": String \| null}`: `trim`, remove one leading `"Horoscope:"` (case-sensitive), `trim`, null if blank. `null` output is the "returned no horoscope" error; a `null` input is a missing candidate. The trims use Java whitespace (em space U+2003 and U+001F are stripped; zero-width space U+200B is not) |

### ReadingReporter (app horoscope/ReadingReporter.kt)

| Key | Record |
|---|---|
| `ReadingReporter.Reason` | `{"name", "ordinal", "label"}` |
| `ReadingReporter.fieldNames` | `{"spec", "output": {key: value}}`: split on `,`, each piece split on the first `=`, both sides trimmed, empty keys and values dropped, a repeated key's last value wins |
| `ReadingReporter.formBody` | `{"reason": Reason name, "reading", "date", "version", "spec", "output": body}`. The body is `reason`, `reading`, `date`, `version` in that order, each `encode(fieldNames(spec)[key] ?? key) + "=" + encode(value)`, joined by `&`. `version` is `"\(versionName) (\(versionCode))"` on Android. `encode` is Java's `URLEncoder.encode(s, "UTF-8")`: `A–Z a–z 0–9 . - * _` stay, space becomes `+`, every other byte of the UTF-8 is `%XX` with upper-case hex (so `~` is `%7E`, `'` is `%27`) |

### kotlin.random.Random and the star fields

| Key | Record |
|---|---|
| `Random.nextFloat` | `{"seed", "output": [300 Float]}` from a fresh `Random(seed)`. Each value is k / 2^24, exact as a Swift `Float` |
| `Random.nextInt` | `{"seed", "output": [300 Int32]}` from a fresh `Random(seed)` |
| `Random.nextIntUntil` | `{"seed", "until", "output": [300 Int32]}` from a fresh `Random(seed)` for each `until` in 1, 2, 34, 64, 100, 1000, 2147483647 |
| `SundialView.ambientStars` | `{"index", "radius" (F), "angle" (F), "xFraction" (F), "yFraction" (F), "radiusDp" (F), "alpha", "flare"}`, 170 stars from `Random(0x51A7D1A1)`. `radius` and `angle` are the intermediate `sqrt(nextFloat())` and `nextFloat() * 2π` |
| `SundialView.dustLaneStars` | the same fields, 64 stars from `Random(0x0B17A5E)`; `radius` and `angle` are null and `flare` is false |

Seeds are 1369952673 (`0x51A7D1A1`), 185629278 (`0x0B17A5E`), 0, 1, −1, 42, −2147483648 and 2147483647,
passed as `KotlinRandom(seed: Int32(seed))`.

## Not covered

- Functions that need Android or I/O: `ZodiacPreferences.get/set/setHoroscope/…` (SharedPreferences),
  `HoroscopeGenerator.generate`'s model status and download messages, `ReadingReporter.send` and
  `isConfigured`.
- `CelestialStyle`, `InstrumentLayout` and the renderers (colours and drawing, not in the requested list).
- Preconditions and throws: `geocentricLongitude(EARTH)`, `nearestSpoke` on an empty list, NaN and
  infinite inputs (JSON has no representation for them).
