import Foundation
import XCTest
@testable import SundialCore

/// Compares SundialCore with the Android app, value for value, over the inputs recorded in
/// Resources/android-reference.json (see Resources/README.md for every key and field).
///
/// Integers, strings, booleans and enums must match exactly. Doubles must agree to 1e-9 relative
/// (1e-9 absolute near zero), and more tightly where the README expects bit-level agreement.
/// Two tolerances are wider for platform reasons, each explained where it is used: Kotlin Float
/// fields (the Swift port computes geometry in Double, PORTING.md) and instants (a Date holds about
/// 0.1 µs where java.time keeps exact nanoseconds).
final class AndroidReferenceTests: XCTestCase {
    // MARK: Astronomy

    func testAstronomyConstants() {
        let values = [
            "julianDateUnixEpoch": Astronomy.julianDateUnixEpoch,
            "julianDateJ2000": Astronomy.julianDateJ2000,
            "synodicMonthDays": Astronomy.synodicMonthDays,
        ]
        verify("Astronomy.constants") { r, m in
            m.equal(r["type"].string, "Double", r["name"].string)
            m.equal(values[r["swiftName"].string], r["value"].double, r["name"].string)
        }
    }

    func testAstronomyBody() {
        verify("Astronomy.Body") { r, m in
            let body = Astronomy.Body.allCases[r["ordinal"].int]
            m.equal(kotlinName(body), r["name"].string, "Body \(r["ordinal"].int)")
            m.equal(body.ordinal, r["ordinal"].int, "ordinal")
        }
        XCTAssertEqual(Astronomy.Body.allCases.count, records("Astronomy.Body").count)
    }

    func testJulianDate() {
        verify("Astronomy.julianDate") { r, m in
            // A day is 4.7e-10 of a Julian date near J2000: this allows about two ulps.
            m.close(Astronomy.julianDate(parseInstant(r["instant"])), r["output"].double, absolute: 1e-9, "\(r["instant"].int64)")
        }
    }

    func testHeliocentricPosition() {
        verify("Astronomy.heliocentricPosition") { r, m in
            let v = Astronomy.heliocentricPosition(parseBody(r["body"]), parseInstant(r["instant"]))
            let o = r["output"]
            let what = "\(r["body"].string) \(r["instant"].int64)"
            m.close(v.x, o["x"].double, "\(what) x")
            m.close(v.y, o["y"].double, "\(what) y")
            m.close(v.z, o["z"].double, "\(what) z")
            m.close(v.radius, o["radius"].double, "\(what) radius")
            m.circular(v.longitudeDegrees, o["longitudeDegrees"].double, period: 360, "\(what) longitude")
        }
    }

    func testSiderealAndLunarAngles() {
        let functions: [(String, (Date) -> Double)] = [
            ("Astronomy.greenwichMeanSiderealDegrees", Astronomy.greenwichMeanSiderealDegrees),
            ("Astronomy.moonLongitudeDegrees", Astronomy.moonLongitudeDegrees),
            ("Astronomy.moonPhaseDegrees", Astronomy.moonPhaseDegrees),
            ("Astronomy.sunLongitudeOfDate", Astronomy.sunLongitudeOfDate),
            ("Zodiac.sunLongitude", Zodiac.sunLongitude),
        ]
        for (key, function) in functions {
            verify(key) { r, m in
                m.circular(function(parseInstant(r["instant"])), r["output"].double, period: 360, "\(r["instant"].int64)")
            }
        }
    }

    func testPrecessionDegrees() {
        verify("Astronomy.precessionDegrees") { r, m in
            m.close(Astronomy.precessionDegrees(parseInstant(r["instant"])), r["output"].double, "\(r["instant"].int64)")
        }
    }

    func testDaysInYear() {
        verify("Astronomy.daysInYear") { r, m in
            m.equal(Astronomy.daysInYear(r["year"].int), r["output"].int, "\(r["year"].int)")
        }
    }

    func testCivilYearFraction() {
        verify("Astronomy.civilYearFraction") { r, m in
            let dateTime = ZonedDateTime(parseInstant(r["instant"]), parseZone(r["zone"]))
            let what = "\(r["zone"].string) \(r["local"].string)"
            // The input itself: the zone's offset and local time at the instant (time-zone data).
            m.equal(dateTime.offsetSeconds, r["offsetSeconds"].int, "\(what) offset")
            m.equal(localText(dateTime), r["local"].string, "\(what) local")
            // Kotlin counts exact nanoseconds; a Date resolves about 0.1 µs, 3e-15 of a year.
            m.close(Astronomy.civilYearFraction(dateTime), r["output"].double, absolute: 1e-12, what)
        }
    }

    func testInstantAtYearFraction() {
        verify("Astronomy.instantAtYearFraction") { r, m in
            let output = Astronomy.instantAtYearFraction(r["year"].int, r["fraction"].double, parseZone(r["zone"]))
            m.instant(output, r["output"], "\(r["year"].int) \(r["fraction"].double) \(r["zone"].string)")
        }
    }

    func testNormalizeDegrees() {
        // Only % and +: bit-identical.
        verify("Astronomy.normalizeDegrees") { r, m in
            m.equal(Astronomy.normalizeDegrees(r["input"].double), r["output"].double, "\(r["input"].double)")
        }
        verify("Astronomy.normalizeSignedDegrees") { r, m in
            m.equal(Astronomy.normalizeSignedDegrees(r["input"].double), r["output"].double, "\(r["input"].double)")
        }
    }

    // MARK: Zodiac

    func testZodiacTables() {
        verify("Zodiac.Sign") { r, m in
            let sign = Zodiac.Sign.allCases[r["ordinal"].int]
            let what = r["name"].string
            m.equal(sign.name, r["name"].string, what)
            m.equal(sign.ordinal, r["ordinal"].int, what)
            m.equal(sign.displayName, r["displayName"].string, what)
            m.equal(sign.symbol, r["symbol"].string, what)
            m.equal(kotlinName(sign.element), r["element"].string, what)
            m.equal(sign.startMonth, r["startMonth"].int, what)
            m.equal(sign.startDay, r["startDay"].int, what)
        }
        verify("Zodiac.Element") { r, m in
            m.equal(kotlinName(Zodiac.Element.allCases[r["ordinal"].int]), r["name"].string, "element")
        }
        verify("Zodiac.Season") { r, m in
            m.equal(kotlinName(Zodiac.Season.allCases[r["ordinal"].int]), r["name"].string, "season")
        }
        XCTAssertEqual(Zodiac.Sign.allCases.count, records("Zodiac.Sign").count)
        XCTAssertEqual(Zodiac.Element.allCases.count, records("Zodiac.Element").count)
        XCTAssertEqual(Zodiac.Season.allCases.count, records("Zodiac.Season").count)
    }

    func testSignFor() {
        verify("Zodiac.signFor") { r, m in
            m.equal(Zodiac.signFor(parseDate(r["date"])).name, r["output"].string, r["date"].string)
        }
    }

    func testSignForLongitude() {
        verify("Zodiac.signForLongitude") { r, m in
            m.equal(Zodiac.signForLongitude(r["longitude"].double).name, r["output"].string, "\(r["longitude"].double)")
        }
    }

    func testSeasonFor() {
        verify("Zodiac.seasonFor") { r, m in
            let season = Zodiac.seasonFor(parseDate(r["date"]), r["northernHemisphere"].bool)
            m.equal(kotlinName(season), r["output"].string, "\(r["date"].string) \(r["northernHemisphere"].bool)")
        }
    }

    func testGeocentricLongitude() {
        verify("Zodiac.geocentricLongitude") { r, m in
            let output = Zodiac.geocentricLongitude(parseBody(r["body"]), parseInstant(r["instant"]))
            m.circular(output, r["output"].double, period: 360, "\(r["body"].string) \(r["instant"].int64)")
        }
    }

    func testPlacements() {
        verify("Zodiac.placements") { r, m in
            let placements = Zodiac.placements(parseInstant(r["instant"]))
            let expected = r["output"].array
            m.equal(placements.count, expected.count, "count")
            for (actual, e) in zip(placements, expected) {
                let what = "\(r["instant"].int64) \(e["label"].string)"
                m.equal(actual.label, e["label"].string, what)
                m.equal(actual.symbol, e["symbol"].string, what)
                m.circular(actual.longitudeDegrees, e["longitudeDegrees"].double, period: 360, what)
                m.equal(actual.sign.name, e["sign"].string, what)
            }
        }
    }

    // MARK: DialGeometry

    func testDialGeometryConstants() {
        let values: [String: Double] = [
            "mercuryOrbit": DialGeometry.mercuryOrbit,
            "venusOrbit": DialGeometry.venusOrbit,
            "earthOrbit": DialGeometry.earthOrbit,
            "marsOrbit": DialGeometry.marsOrbit,
            "zodiacOuter": DialGeometry.zodiacOuter,
            "zodiacInner": DialGeometry.zodiacInner,
            "zodiacHandEnd": DialGeometry.zodiacHandEnd,
            "moonDial": DialGeometry.moonDial,
            "earthUnit": DialGeometry.moonDial / 67.5, // private, recomputed as the generator does
            "hourDial": DialGeometry.hourDial,
            "earthRadius": DialGeometry.earthRadius,
            "localWheel": DialGeometry.localWheel,
            "localWheelSmallTooth": DialGeometry.localWheelSmallTooth,
            "localWheelBigTooth": DialGeometry.localWheelBigTooth,
            "localWheelRedTooth": DialGeometry.localWheelRedTooth,
            "localWheelRedHalfBase": DialGeometry.localWheelRedHalfBase,
            "localWheelToothHalfAngle": DialGeometry.localWheelToothHalfAngle,
            "dateStripOuter": DialGeometry.dateStripOuter,
            "dateStripInner": DialGeometry.dateStripInner,
            "earthCameraZoom": DialGeometry.earthCameraZoom,
            "earthSubdialScale": DialGeometry.earthSubdialScale,
            "heliocentricEarthRadius": DialGeometry.heliocentricEarthRadius,
            "subdialGear": DialGeometry.subdialGear,
            "subdialMoonTrack": DialGeometry.subdialMoonTrack,
            "unityYearDays": DialGeometry.unityYearDays,
            "januaryFirstAngle": DialGeometry.januaryFirstAngle,
            "geocentricSunDistance": DialGeometry.geocentricSunDistance,
            "skyParallax": DialGeometry.skyParallax,
        ]
        verify("DialGeometry.constants") { r, m in
            guard let value = values[r["swiftName"].string] else {
                return m.check(false, "no Swift constant \(r["swiftName"].string)")
            }
            m.value(value, r, r["name"].string)
        }
        XCTAssertEqual(values.count, records("DialGeometry.constants").count)
    }

    func testDialAngles() {
        let functions: [(String, String, (Double, Bool) -> Double, Double?)] = [
            ("DialGeometry.annualAngle", "fraction", DialGeometry.annualAngle, nil),
            ("DialGeometry.yearFractionFromAngle", "angle", DialGeometry.yearFractionFromAngle, 1),
            ("DialGeometry.eclipticAngle", "longitude", DialGeometry.eclipticAngle, nil),
            ("DialGeometry.hourAngle", "hours", DialGeometry.hourAngle, nil),
            ("DialGeometry.minuteFromHourAngle", "angle", DialGeometry.minuteFromHourAngle, 1_440),
            ("DialGeometry.moonAngle", "phase", DialGeometry.moonAngle, nil),
            ("DialGeometry.phaseFromMoonAngle", "angle", DialGeometry.phaseFromMoonAngle, 360),
        ]
        for (key, input, function, period) in functions {
            // Only + − × ÷ % and floor, in Kotlin's order: expected to agree to 1e-12.
            verify(key) { r, m in
                let output = function(r[input].double, r["north"].bool)
                let what = "\(r[input].double) north=\(r["north"].bool)"
                if let period {
                    m.circular(output, r["output"].double, period: period, relative: 1e-12, what)
                } else {
                    m.close(output, r["output"].double, relative: 1e-12, what)
                }
            }
        }
    }

    func testEventBands() {
        let functions: [(String, String, (Double, Int, Double) -> DialGeometry.EventBand)] = [
            ("DialGeometry.yearEventBand", "annualRadius", { DialGeometry.yearEventBand($0, $1, minThickness: $2) }),
            ("DialGeometry.dayEventBand", "hourRadius", { DialGeometry.dayEventBand($0, $1, minThickness: $2) }),
        ]
        for (key, radius, function) in functions {
            verify(key) { r, m in
                let band = function(r[radius].double, r["calendarIndex"].int, r["minThickness"].double)
                let what = "\(r[radius].double) \(r["calendarIndex"].int) \(r["minThickness"].double)"
                // The operands: the radius, less up to calendarIndex + 1 band thicknesses.
                let scale = r[radius].double + r["minThickness"].double * Double(max(r["calendarIndex"].int, 0) + 1)
                m.float(band.centerRadius, r["output"]["centerRadius"].double, scale: scale, "\(what) centerRadius")
                m.float(band.thickness, r["output"]["thickness"].double, scale: scale, "\(what) thickness")
            }
        }
    }

    func testEarthFlightFrame() {
        verify("DialGeometry.earthFlightFrame") { r, m in
            let frame = DialGeometry.earthFlightFrame(r["progress"].double)
            let what = "\(r["progress"].double)"
            m.float(frame.cameraScale, r["output"]["cameraScale"].double, "\(what) cameraScale")
            m.float(frame.earthSystemScale, r["output"]["earthSystemScale"].double, "\(what) earthSystemScale")
            m.float(frame.skyScale, r["output"]["skyScale"].double, "\(what) skyScale")
        }
    }

    // MARK: SeasonBands

    func testSeasonBands() {
        verify("SeasonBands.constants") { r, m in
            m.equal(r["swiftName"].string, "blendDays", "name")
            m.equal(SeasonBands.blendDays, r["value"].double, "BLEND_DAYS")
        }
        verify("SeasonBands.starts") { r, m in
            let starts = SeasonBands.starts(r["year"].int)
            let expected = r["output"].array
            m.equal(starts.count, expected.count, "count")
            for (actual, e) in zip(starts, expected) {
                m.equal(actual.0, e["fraction"].double, "\(r["year"].int) \(e["season"].string)")
                m.equal(kotlinName(actual.1), e["season"].string, "\(r["year"].int)")
            }
        }
        var startsByYear: [Int: [(Double, Zodiac.Season)]] = [:]
        verify("SeasonBands.mixAt") { r, m in
            let year = r["year"].int
            if startsByYear[year] == nil { startsByYear[year] = SeasonBands.starts(year) }
            let mix = SeasonBands.mixAt(r["fraction"].double, startsByYear[year]!, r["daysInYear"].int)
            let what = "\(year) \(r["fraction"].double)"
            m.equal(kotlinName(mix.from), r["output"]["from"].string, "\(what) from")
            m.equal(kotlinName(mix.to), r["output"]["to"].string, "\(what) to")
            m.close(mix.amount, r["output"]["amount"].double, relative: 1e-12, "\(what) amount")
        }
    }

    // MARK: TimeZoneDial

    func testSpokes() {
        verify("TimeZoneDial.spokes") { r, m in
            let spokes = TimeZoneDial.spokes(parseInstant(r["instant"]), north: r["north"].bool)
            let expected = r["output"].array
            m.equal(spokes.count, expected.count, "count")
            for (actual, e) in zip(spokes, expected) {
                let what = "\(r["instant"].int64) north=\(r["north"].bool) \(e["offsetHours"].int)"
                m.equal(actual.offsetHours, e["offsetHours"].int, what)
                m.close(actual.angleDegrees, e["angleDegrees"].double, relative: 1e-12, what)
                m.equal(actual.localDate.description, e["localDate"].string, what)
                m.equal(actual.label, e["label"].string, what)
            }
        }
    }

    func testDatelineHours() {
        verify("TimeZoneDial.datelineHours") { r, m in
            m.close(TimeZoneDial.datelineHours(parseInstant(r["instant"])), r["output"].double, relative: 1e-12, "\(r["instant"].int64)")
        }
    }

    func testLocalOffsetMinutes() {
        verify("TimeZoneDial.localOffsetMinutes") { r, m in
            let output = TimeZoneDial.localOffsetMinutes(parseInstant(r["instant"]), parseZone(r["zone"]))
            m.equal(output, r["output"].int, "\(r["zone"].string) \(r["instant"].int64)")
        }
    }

    func testAngleForOffsetMinutes() {
        verify("TimeZoneDial.angleForOffsetMinutes") { r, m in
            let output = TimeZoneDial.angleForOffsetMinutes(parseInstant(r["instant"]), r["offsetMinutes"].int, north: r["north"].bool)
            // Kotlin reads the local time's exact nanoseconds; here they come from a Date, which holds
            // an instant in 1950 to about 0.1 µs, 5e-10 of a degree on this dial. 1e-9 relative is 0.24 µs.
            m.close(output, r["output"].double,
                    "\(r["instant"].int64) \(r["offsetMinutes"].int) north=\(r["north"].bool)")
        }
    }

    func testLocalName() {
        verify("TimeZoneDial.localName") { r, m in
            let zone = parseZone(r["zone"])
            let instant = parseInstant(r["instant"])
            let what = "\(r["zone"].string) \(r["instant"].int64)"
            m.equal(TimeZoneDial.localOffsetMinutes(instant, zone), r["offsetMinutes"].int, "\(what) offset")
            m.equal(TimeZoneDial.localName(zone, instant), r["output"].string, what)
        }
    }

    func testCommonName() {
        verify("TimeZoneDial.commonName") { r, m in
            m.equal(TimeZoneDial.commonName(r["offsetHours"].int), r["output"].string, "\(r["offsetHours"].int)")
        }
    }

    func testNearestSpoke() {
        var spokesByCase: [String: [TimeZoneDial.Spoke]] = [:]
        verify("TimeZoneDial.nearestSpoke") { r, m in
            let key = "\(r["instant"].int64) \(r["north"].bool)"
            if spokesByCase[key] == nil { spokesByCase[key] = TimeZoneDial.spokes(parseInstant(r["instant"]), north: r["north"].bool) }
            let spoke = TimeZoneDial.nearestSpoke(spokesByCase[key]!, r["angle"].double)
            m.equal(spoke.offsetHours, r["output"].int, "\(key) \(r["angle"].double)")
        }
    }

    // MARK: GalacticGeometry

    func testGalacticConstants() {
        let values: [String: Double] = [
            "travelX": GalacticGeometry.travelX,
            "travelY": GalacticGeometry.travelY,
            "sideX": GalacticGeometry.sideX,
            "sideY": GalacticGeometry.sideY,
            "yearPitch": GalacticGeometry.yearPitch,
            "orbitDepth": GalacticGeometry.orbitDepth,
            "minYear": Double(GalacticGeometry.minYear),
            "maxYear": Double(GalacticGeometry.maxYear),
        ]
        verify("GalacticGeometry.constants") { r, m in
            guard let value = values[r["swiftName"].string] else {
                return m.check(false, "no Swift constant \(r["swiftName"].string)")
            }
            m.value(value, r, r["name"].string)
        }
    }

    func testContinuousYear() {
        verify("GalacticGeometry.continuousYear") { r, m in
            let output = GalacticGeometry.continuousYear(parseInstant(r["instant"]), parseZone(r["zone"]))
            // As civilYearFraction; 1e-12 of a year is about two ulps of a year number.
            m.close(output, r["output"].double, absolute: 1e-12, "\(r["zone"].string) \(r["instant"].int64)")
        }
    }

    func testInstantAt() {
        verify("GalacticGeometry.instantAt") { r, m in
            let zone = parseZone(r["zone"])
            let what = "\(r["continuousYear"].double) \(r["zone"].string)"
            let output = GalacticGeometry.instantAt(r["continuousYear"].double, zone)
            m.instant(output, r["output"], what)
            m.close(GalacticGeometry.continuousYear(output, zone), r["roundTrip"].double, absolute: 1e-11, "\(what) round trip")
        }
    }

    func testMonthStart() {
        verify("GalacticGeometry.monthStart") { r, m in
            m.equal(GalacticGeometry.monthStart(r["year"].int, r["month"].int), r["output"].double,
                    "\(r["year"].int)-\(r["month"].int)")
        }
    }

    func testOrbitOffset() {
        verify("GalacticGeometry.orbitOffset") { r, m in
            let (along, side) = GalacticGeometry.orbitOffset(r["longitude"].double, r["orbitRadius"].double)
            let what = "\(r["longitude"].double) \(r["orbitRadius"].double)"
            m.float(along, r["output"]["along"].double, "\(what) along")
            m.float(side, r["output"]["side"].double, "\(what) side")
        }
    }

    // MARK: EarthOrientation

    func testEarthOrientation() {
        verify("EarthOrientation.constants") { r, m in
            m.equal(r["swiftName"].string, "obliquityDegrees", "name")
            m.equal(EarthOrientation.obliquityDegrees, r["value"].double, "OBLIQUITY_DEGREES")
        }
        verify("EarthOrientation.projectedGeographicPole") { r, m in
            let (x, y) = EarthOrientation.projectedGeographicPole(r["north"].bool, r["sunLongitude"].double)
            let what = "north=\(r["north"].bool) \(r["sunLongitude"].double)"
            m.close(x, r["output"]["x"].double, "\(what) x")
            m.close(y, r["output"]["y"].double, "\(what) y")
        }
        verify("EarthOrientation.screenToEquatorial") { r, m in
            let v = EarthOrientation.screenToEquatorial(r["sx"].double, r["sy"].double, r["sz"].double,
                                                        r["sunLongitude"].double, r["north"].bool)
            let what = "(\(r["sx"].double), \(r["sy"].double), \(r["sz"].double)) \(r["sunLongitude"].double) north=\(r["north"].bool)"
            m.close(v.x, r["output"]["x"].double, "\(what) x")
            m.close(v.y, r["output"]["y"].double, "\(what) y")
            m.close(v.z, r["output"]["z"].double, "\(what) z")
        }
    }

    // MARK: CalendarHitTesting

    func testCalendarHitTesting() {
        verify("CalendarHitTesting.containsYearFraction") { r, m in
            let output = CalendarHitTesting.containsYearFraction(r["touch"].double, r["start"].double,
                                                                 r["sweep"].double, r["padding"].double)
            m.equal(output, r["output"].bool,
                    "touch \(r["touch"].double) start \(r["start"].double) sweep \(r["sweep"].double) padding \(r["padding"].double)")
        }
        verify("CalendarHitTesting.containsMinute") { r, m in
            let output = CalendarHitTesting.containsMinute(r["touch"].double, r["start"].double,
                                                           r["endExclusive"].double, r["padding"].double)
            m.equal(output, r["output"].bool,
                    "touch \(r["touch"].double) start \(r["start"].double) end \(r["endExclusive"].double) padding \(r["padding"].double)")
        }
    }

    // MARK: Calendar

    func testDeviceCalendarIsGoogle() {
        verify("DeviceCalendar.isGoogle") { r, m in
            let calendar = DeviceCalendar(1, "Name", "someone@example.com", r["accountType"].string, 0)
            m.equal(calendar.isGoogle, r["output"].bool, "'\(r["accountType"].string)'")
        }
    }

    func testCalendarNormalizer() {
        verify("CalendarNormalizer.normalize") { r, m in
            let event = AndroidReferenceTests.normalized(r)
            let o = r["output"]
            let what = "#\(r["index"].int) \(r["raw"]["title"].string) in \(r["displayZone"].string)"
            m.equal(event.eventId, o["eventId"].int64, "\(what) eventId")
            m.equal(event.calendarId, o["calendarId"].int64, "\(what) calendarId")
            m.equal(event.title, o["title"].string, "\(what) title")
            m.zoned(event.start, o["start"], "\(what) start")
            m.zoned(event.endExclusive, o["endExclusive"], "\(what) endExclusive")
            m.equal(event.allDayStart?.description, o["allDayStart"].optionalString, "\(what) allDayStart")
            m.equal(event.allDayEndExclusive?.description, o["allDayEndExclusive"].optionalString, "\(what) allDayEndExclusive")
            m.equal(event.color, argb(o["color"]), "\(what) color")
            m.equal(event.isAllDay, o["isAllDay"].bool, "\(what) isAllDay")
            m.equal(event.isYearRingEvent, o["isYearRingEvent"].bool, "\(what) isYearRingEvent")
        }
    }

    func testCalendarIntervalsInDay() {
        let events = AndroidReferenceTests.occurrences
        verify("CalendarIntervals.inDay") { r, m in
            let event = events[r["eventIndex"].int]
            let segment = CalendarIntervals.inDay(event, parseDate(r["day"]), parseZone(r["zone"]))
            let what = "#\(r["eventIndex"].int) \(event.title) \(r["day"].string) \(r["zone"].string)"
            let o = r["output"]
            m.equal(segment == nil, o.isNull, "\(what) present")
            if let segment, !o.isNull {
                // Whole milliseconds over 60 000, as Kotlin divides them: bit-identical.
                m.equal(segment.startMinute, o["startMinute"].double, "\(what) startMinute")
                m.equal(segment.endMinuteExclusive, o["endMinuteExclusive"].double, "\(what) endMinuteExclusive")
            }
        }
    }

    func testCalendarIntervalsInYear() {
        let events = AndroidReferenceTests.occurrences
        verify("CalendarIntervals.inYear") { r, m in
            let event = events[r["eventIndex"].int]
            let segment = CalendarIntervals.inYear(event, r["year"].int, parseZone(r["zone"]))
            let what = "#\(r["eventIndex"].int) \(event.title) \(r["year"].int) \(r["zone"].string)"
            let o = r["output"]
            m.equal(segment == nil, o.isNull, "\(what) present")
            if let segment, !o.isNull {
                m.equal(segment.startFraction, o["startFraction"].double, "\(what) startFraction")
                m.equal(segment.sweepFraction, o["sweepFraction"].double, "\(what) sweepFraction")
            }
        }
    }

    // MARK: ZodiacProfile

    func testZodiacProfile() {
        verify("ZodiacProfile") { r, m in
            let profile = parseProfile(r)
            let what = "\(r["enabled"].bool) \(r["birthDate"].optionalString ?? "-") \(r["selectedSign"].optionalString ?? "-") \(r["today"].string)"
            m.equal(profile.resolvedSign(today: parseDate(r["today"])).name, r["output"]["resolvedSign"].string, "\(what) resolvedSign")
            m.equal(profile.isComplete, r["output"]["isComplete"].bool, "\(what) isComplete")
            m.equal(profile.signature, r["output"]["signature"].string, "\(what) signature")
        }
    }

    func testPreserveNatalData() {
        verify("ZodiacPreferences.preserveNatalData") { r, m in
            let output = ZodiacPreferences.preserveNatalData(parseProfile(r["requested"]), parseProfile(r["stored"]))
            m.equal(output, parseProfile(r["output"]), "\(parseProfile(r["requested"])) over \(parseProfile(r["stored"]))")
        }
    }

    // MARK: Birth date and time entry

    func testBirthDateInput() {
        verify("BirthDateInput.parse") { r, m in
            let what = "\(debug(r["month"].string)) \(debug(r["day"].string)) \(debug(r["year"].string)) today \(r["today"].string)"
            do {
                let date = try BirthDateInput.parse(r["month"].string, r["day"].string, r["year"].string, today: parseDate(r["today"]))
                m.check(!r["output"].isNull, "\(what): parsed \(date), expected error \(r["error"].optionalString ?? "")")
                if !r["output"].isNull {
                    m.equal([date.year, date.month, date.day],
                            [r["output"]["year"].int, r["output"]["month"].int, r["output"]["day"].int], what)
                }
            } catch let error as BirthInputError {
                m.equal(error.message, r["error"].optionalString, what)
            } catch {
                m.check(false, "\(what): unexpected \(error)")
            }
        }
    }

    func testBirthTimeInput() {
        verify("BirthTimeInput.parse") { r, m in
            let what = "\(debug(r["hour"].string)) \(debug(r["minute"].string)) pm=\(r["pm"].bool)"
            do {
                let time = try BirthTimeInput.parse(r["hour"].string, r["minute"].string, r["pm"].bool)
                m.check(!r["output"].isNull, "\(what): parsed \(time), expected error \(r["error"].optionalString ?? "")")
                if !r["output"].isNull {
                    m.equal([time.hour, time.minute], [r["output"]["hour"].int, r["output"]["minute"].int], what)
                }
            } catch let error as BirthInputError {
                m.equal(error.message, r["error"].optionalString, what)
            } catch {
                m.check(false, "\(what): unexpected \(error)")
            }
        }
    }

    // MARK: Horoscope and reporting

    func testHoroscopePrompt() {
        verify("HoroscopeGenerator.prompt") { r, m in
            let profile = parseProfile(r)
            let instant = parseInstant(r["instant"])
            let zone = parseZone(r["zone"])
            let what = "\(r["birthDate"].optionalString ?? "-") \(r["instant"].int64) \(r["zone"].string)"
            let date = LocalDate.of(instant, zone)
            m.equal(date.description, r["date"].string, "\(what) date")
            m.equal(profile.resolvedSign(today: date).name, r["sign"].string, "\(what) sign")
            m.equal(HoroscopeGenerator.prompt(profile, instant, zone), r["output"].string, what)
        }
    }

    func testHoroscopeCleanResponse() {
        verify("HoroscopeGenerator.cleanResponse") { r, m in
            let input = r["input"].optionalString
            m.equal(HoroscopeGenerator.cleanResponse(input), r["output"].optionalString, debug(input ?? "nil"))
        }
    }

    func testReadingReporter() {
        verify("ReadingReporter.Reason") { r, m in
            let reason = ReadingReporter.Reason.allCases[r["ordinal"].int]
            m.equal(kotlinName(reason), r["name"].string, "name")
            m.equal(reason.label, r["label"].string, r["name"].string)
        }
        XCTAssertEqual(ReadingReporter.Reason.allCases.count, records("ReadingReporter.Reason").count)
        verify("ReadingReporter.fieldNames") { r, m in
            var expected: [String: String] = [:]
            for (key, value) in r["output"].object { expected[key] = value.string }
            m.equal(ReadingReporter.fieldNames(spec: r["spec"].string), expected, debug(r["spec"].string))
        }
        verify("ReadingReporter.formBody") { r, m in
            let reason = ReadingReporter.Reason.allCases.first { kotlinName($0) == r["reason"].string }!
            let report = ReadingReporter.Report(reason, r["reading"].string, parseDate(r["date"]))
            let body = ReadingReporter.formBody(report, version: r["version"].string,
                                                fields: ReadingReporter.fieldNames(spec: r["spec"].string))
            m.equal(body, r["output"].string, debug(r["reading"].string))
        }
    }

    // MARK: Coverage

    /// Every key in the file is checked, here or in SundialRenderTests' KotlinRandomTests.
    func testEveryKeyIsCovered() {
        let elsewhere: Set = [
            "_meta", "Random.nextFloat", "Random.nextInt", "Random.nextIntUntil",
            "SundialView.ambientStars", "SundialView.dustLaneStars",
        ]
        let covered: Set = [
            "Astronomy.constants", "Astronomy.Body", "Astronomy.julianDate", "Astronomy.heliocentricPosition",
            "Astronomy.greenwichMeanSiderealDegrees", "Astronomy.moonLongitudeDegrees", "Astronomy.moonPhaseDegrees",
            "Astronomy.sunLongitudeOfDate", "Astronomy.precessionDegrees", "Astronomy.daysInYear",
            "Astronomy.civilYearFraction", "Astronomy.instantAtYearFraction", "Astronomy.normalizeDegrees",
            "Astronomy.normalizeSignedDegrees",
            "Zodiac.Sign", "Zodiac.Element", "Zodiac.Season", "Zodiac.signFor", "Zodiac.signForLongitude",
            "Zodiac.seasonFor", "Zodiac.geocentricLongitude", "Zodiac.sunLongitude", "Zodiac.placements",
            "DialGeometry.constants", "DialGeometry.annualAngle", "DialGeometry.yearFractionFromAngle",
            "DialGeometry.eclipticAngle", "DialGeometry.hourAngle", "DialGeometry.minuteFromHourAngle",
            "DialGeometry.moonAngle", "DialGeometry.phaseFromMoonAngle", "DialGeometry.yearEventBand",
            "DialGeometry.dayEventBand", "DialGeometry.earthFlightFrame",
            "SeasonBands.constants", "SeasonBands.starts", "SeasonBands.mixAt",
            "TimeZoneDial.spokes", "TimeZoneDial.datelineHours", "TimeZoneDial.localOffsetMinutes",
            "TimeZoneDial.angleForOffsetMinutes", "TimeZoneDial.localName", "TimeZoneDial.commonName",
            "TimeZoneDial.nearestSpoke",
            "GalacticGeometry.constants", "GalacticGeometry.continuousYear", "GalacticGeometry.instantAt",
            "GalacticGeometry.monthStart", "GalacticGeometry.orbitOffset",
            "EarthOrientation.constants", "EarthOrientation.projectedGeographicPole", "EarthOrientation.screenToEquatorial",
            "CalendarHitTesting.containsYearFraction", "CalendarHitTesting.containsMinute",
            "DeviceCalendar.isGoogle", "CalendarNormalizer.normalize", "CalendarIntervals.inDay", "CalendarIntervals.inYear",
            "ZodiacProfile", "ZodiacPreferences.preserveNatalData",
            "BirthDateInput.parse", "BirthTimeInput.parse",
            "HoroscopeGenerator.prompt", "HoroscopeGenerator.cleanResponse",
            "ReadingReporter.Reason", "ReadingReporter.fieldNames", "ReadingReporter.formBody",
        ]
        let keys = Set(AndroidReferenceTests.reference.keys)
        XCTAssertEqual(keys.subtracting(covered).subtracting(elsewhere), [], "keys nothing checks")
        XCTAssertEqual(covered.subtracting(keys), [], "checked keys missing from the file")
    }

    // MARK: - Reference data

    static let reference: [String: JSON] = {
        guard let url = Bundle.module.url(forResource: "android-reference", withExtension: "json", subdirectory: "Resources") else {
            fatalError("Resources/android-reference.json is missing from the test bundle")
        }
        do {
            // JSONDecoder reads every double in the file bit-exactly; JSONSerialization on Linux does not.
            return try JSONDecoder().decode([String: JSON].self, from: Data(contentsOf: url))
        } catch {
            fatalError("android-reference.json: \(error)")
        }
    }()

    /// CalendarNormalizer.normalize of every recorded raw instance, by record index.
    static let occurrences: [CalendarOccurrence] = {
        guard case .array(let records)? = reference["CalendarNormalizer.normalize"] else { return [] }
        return records.map(normalized)
    }()

    static func normalized(_ r: JSON) -> CalendarOccurrence {
        let raw = r["raw"]
        return CalendarNormalizer.normalize(
            RawCalendarInstance(raw["eventId"].int64, raw["calendarId"].int64, raw["title"].string,
                                raw["beginMillis"].int64, raw["endMillis"].int64, raw["allDay"].bool,
                                raw["eventTimeZone"].optionalString, argb(raw["color"])),
            TimeZone(identifier: r["displayZone"].string)!
        )
    }

    func records(_ key: String) -> [JSON] {
        guard case .array(let records)? = AndroidReferenceTests.reference[key] else {
            XCTFail("android-reference.json has no \(key)")
            return []
        }
        return records
    }

    /// Runs [check] on every record of [key] and reports the mismatches together.
    func verify(_ key: String, file: StaticString = #filePath, line: UInt = #line, _ check: (JSON, Mismatches) -> Void) {
        let records = records(key)
        XCTAssertFalse(records.isEmpty, "\(key) has no records", file: file, line: line)
        let mismatches = Mismatches(key)
        for record in records { check(record, mismatches) }
        mismatches.report(file: file, line: line)
    }
}

// MARK: - Decoding helpers

private func parseInstant(_ json: JSON) -> Date { Date(epochMilli: json.int64) }
private func parseZone(_ json: JSON) -> TimeZone { TimeZone(identifier: json.string)! }
private func parseDate(_ json: JSON) -> LocalDate { LocalDate.parse(json.string)! }
private func parseBody(_ json: JSON) -> Astronomy.Body { Astronomy.Body.allCases.first { kotlinName($0) == json.string }! }
/// A Kotlin colour Int (signed) as ARGB.
private func argb(_ json: JSON) -> ARGB { ARGB(UInt32(bitPattern: Int32(json.int))) }

/// The Kotlin constant name of a single-word enum case: `.sagittarius` is "SAGITTARIUS".
private func kotlinName<T>(_ value: T) -> String { String(describing: value).uppercased() }

private func parseProfile(_ json: JSON) -> ZodiacProfile {
    let time = json["birthTime"]
    return ZodiacProfile(
        enabled: json["enabled"].bool,
        birthDate: json["birthDate"].isNull ? nil : parseDate(json["birthDate"]),
        birthTime: time.isNull ? nil : LocalTime(time["hour"].int, time["minute"].int, time["second"].int),
        selectedSign: json["selectedSign"].isNull ? nil : Zodiac.Sign.allCases.first { $0.name == json["selectedSign"].string }!
    )
}

/// java.time's "uuuu-MM-dd'T'HH:mm:ss.SSS" of a ZonedDateTime whose instant is a whole number of
/// milliseconds, as every recorded one is. The local time is rounded to the millisecond, which a
/// Date (about 0.1 µs) cannot always hold exactly: 16:00:00.001 may read back as 16:00:00.000999.
private func localText(_ dateTime: ZonedDateTime) -> String {
    let localMillis = Int64(((dateTime.instant.timeIntervalSince1970 + Double(dateTime.offsetSeconds)) * 1_000).rounded())
    let day = Int((Double(localMillis) / 86_400_000).rounded(.down))
    let millisOfDay = Int(localMillis - Int64(day) * 86_400_000)
    return "\(LocalDate(epochDay: day))T" + String(format: "%02d:%02d:%02d.%03d", millisOfDay / 3_600_000,
                                                   millisOfDay / 60_000 % 60, millisOfDay / 1_000 % 60, millisOfDay % 1_000)
}

/// Control and non-ASCII characters escaped, for readable failure messages.
private func debug(_ text: String) -> String {
    "\"" + text.unicodeScalars.map { $0.value < 0x20 || $0.value >= 0x7F ? String(format: "\\u%04X", $0.value) : String($0) }.joined() + "\""
}

/// Collects one key's mismatches, so a systematic error reports once with examples.
final class Mismatches {
    let key: String
    private(set) var checked = 0
    private(set) var failed = 0
    private var samples: [String] = []

    init(_ key: String) { self.key = key }

    func check(_ ok: Bool, _ message: @autoclosure () -> String) {
        checked += 1
        guard !ok else { return }
        failed += 1
        if samples.count < 12 { samples.append(message()) }
    }

    func equal<T: Equatable>(_ actual: T, _ expected: T, _ what: @autoclosure () -> String) {
        check(actual == expected, "\(what()): got \(actual), expected \(expected)")
    }

    /// Within [relative] of the expected value, or of 1 near zero; or within [absolute].
    func close(_ actual: Double, _ expected: Double, relative: Double = 1e-9, absolute: Double? = nil,
               _ what: @autoclosure () -> String) {
        let tolerance = absolute ?? relative * max(abs(expected), 1)
        check(actual == expected || abs(actual - expected) <= tolerance,
              "\(what()): got \(actual), expected \(expected) (off by \(actual - expected))")
    }

    /// As close, for a value on a circle of [period]: 359.9999999999 and 0 are neighbours.
    func circular(_ actual: Double, _ expected: Double, period: Double, relative: Double = 1e-9,
                  _ what: @autoclosure () -> String) {
        let difference = (actual - expected).remainder(dividingBy: period)
        check(actual == expected || abs(difference) <= relative * max(abs(expected), 1),
              "\(what()): got \(actual), expected \(expected) (off by \(difference))")
    }

    /// A Kotlin Float result, computed in Double here (PORTING.md): a Float carries 24 bits, so
    /// the two agree to a few parts in 10^7 of [scale], the size of the operands. When operands
    /// cancel (100 - 99.3...), Float's rounding error is relative to them, not to the small result.
    func float(_ actual: Double, _ expected: Double, scale: Double = 0, _ what: @autoclosure () -> String) {
        close(actual, expected, absolute: 1e-6 * max(abs(expected), abs(scale), 1), what())
    }

    /// A constant record {name, swiftName, type, value}: Doubles and Ints exactly, Floats as [float].
    func value(_ actual: Double, _ record: JSON, _ what: String) {
        switch record["type"].string {
        case "Float": float(actual, record["value"].double, what)
        default: equal(actual, record["value"].double, what)
        }
    }

    /// An Instant {epochSecond, nano}: a Date holds about 0.1 µs, so within a microsecond.
    func instant(_ actual: Date, _ expected: JSON, _ what: @autoclosure () -> String) {
        let seconds = actual.timeIntervalSince1970 - Double(expected["epochSecond"].int64)
        let offBy = seconds - Double(expected["nano"].int) / 1e9
        check(abs(offBy) <= 1e-6, "\(what()): got \(actual.timeIntervalSince1970), expected \(expected["epochSecond"].int64)"
              + " + \(expected["nano"].int) ns (off by \(offBy) s)")
    }

    /// A ZonedDateTime {epochMillis, offsetSeconds, local, zone}.
    func zoned(_ actual: ZonedDateTime, _ expected: JSON, _ what: @autoclosure () -> String) {
        equal(Int64((actual.instant.timeIntervalSince1970 * 1_000).rounded()), expected["epochMillis"].int64, "\(what()) epochMillis")
        equal(actual.offsetSeconds, expected["offsetSeconds"].int, "\(what()) offsetSeconds")
        equal(localText(actual), expected["local"].string, "\(what()) local")
        // Foundation names UTC "GMT"; compare the zones, not their names.
        equal(actual.zone, TimeZone(identifier: expected["zone"].string)!, "\(what()) zone")
    }

    func report(file: StaticString, line: UInt) {
        guard failed > 0 else { return }
        XCTFail("\(key): \(failed) of \(checked) checks failed, for example:\n  " + samples.joined(separator: "\n  "),
                file: file, line: line)
    }
}

// MARK: - JSON

/// A JSON value, decoded with JSONDecoder so every number arrives bit-exact.
enum JSON: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSON].self))
        }
    }

    subscript(key: String) -> JSON {
        guard case .object(let fields) = self else { fatalError("not an object: \(self)") }
        return fields[key] ?? .null
    }

    var isNull: Bool { if case .null = self { return true } else { return false } }

    var double: Double {
        guard case .number(let value) = self else { fatalError("not a number: \(self)") }
        return value
    }

    /// Every integer in the file fits a Double exactly (README).
    var int64: Int64 {
        let value = double
        guard let exact = Int64(exactly: value) else { fatalError("not an integer: \(value)") }
        return exact
    }

    var int: Int { Int(int64) }

    var bool: Bool {
        guard case .bool(let value) = self else { fatalError("not a boolean: \(self)") }
        return value
    }

    var string: String {
        guard case .string(let value) = self else { fatalError("not a string: \(self)") }
        return value
    }

    var optionalString: String? { isNull ? nil : string }

    var array: [JSON] {
        guard case .array(let value) = self else { fatalError("not an array: \(self)") }
        return value
    }

    var object: [String: JSON] {
        guard case .object(let value) = self else { fatalError("not an object: \(self)") }
        return value
    }
}
