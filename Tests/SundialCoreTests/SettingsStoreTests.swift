import Foundation
import XCTest
@testable import SundialCore

/// SettingsStore keeps the Android SharedPreferences' keys, defaults and behaviour.
final class SettingsStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = SettingsStore(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: CelestialStylePreferences

    func testStyleDefaultsToVoidBlackAndIsStoredByKotlinName() {
        XCTAssertEqual(store.celestialStyle.get(), .voidBlack)
        store.celestialStyle.set(.brassWatch)
        XCTAssertEqual(store.celestialStyle.get(), .brassWatch)
        XCTAssertEqual(defaults.string(forKey: "celestial_appearance.background_style"), "BRASS_WATCH")
        defaults.set("NOT_A_STYLE", forKey: "celestial_appearance.background_style")
        XCTAssertEqual(store.celestialStyle.get(), .voidBlack)
    }

    // MARK: ZodiacPreferences

    func testAstrologyIsOptInAndOldProfilesComeBackDisabled() {
        XCTAssertEqual(store.zodiac.get(), ZodiacProfile())
        XCTAssertEqual(defaults.object(forKey: "zodiac_profile.opt_in_version") as? Int, 1)

        // Saved enabled before the opt-in existed (version 0): disabled, and migrated.
        defaults.set(0, forKey: "zodiac_profile.opt_in_version")
        defaults.set(true, forKey: "zodiac_profile.enabled")
        XCTAssertFalse(store.zodiac.get().enabled)
        XCTAssertEqual(defaults.object(forKey: "zodiac_profile.opt_in_version") as? Int, 1)
        XCTAssertEqual(defaults.object(forKey: "zodiac_profile.enabled") as? Bool, false)

        store.zodiac.set(ZodiacProfile(enabled: true))
        XCTAssertTrue(store.zodiac.get().enabled)
    }

    func testProfileIsStoredAsAndroidStoresItAndNatalDataIsKept() {
        let profile = ZodiacProfile(enabled: true, birthDate: LocalDate(1976, 7, 4), birthTime: LocalTime(7, 5),
                                    selectedSign: .pisces, birthZoneId: "America/Chicago")
        XCTAssertEqual(store.zodiac.set(profile), profile)
        XCTAssertEqual(defaults.string(forKey: "zodiac_profile.birth_date"), "1976-07-04")
        XCTAssertEqual(defaults.string(forKey: "zodiac_profile.birth_time"), "07:05")
        XCTAssertEqual(defaults.string(forKey: "zodiac_profile.sign"), "PISCES")
        XCTAssertEqual(defaults.string(forKey: "zodiac_profile.birth_zone"), "America/Chicago")
        XCTAssertEqual(store.zodiac.get(), profile)

        // A mode-only update keeps the birthday and time; the sign follows the request.
        let saved = store.zodiac.set(ZodiacProfile(enabled: false))
        XCTAssertEqual(saved, ZodiacProfile(enabled: false, birthDate: LocalDate(1976, 7, 4),
                                            birthTime: LocalTime(7, 5), birthZoneId: "America/Chicago"))
        XCTAssertEqual(store.zodiac.get(), saved)
        XCTAssertNil(defaults.object(forKey: "zodiac_profile.sign"))
    }

    func testTodaysHoroscopeBelongsToOneProfileAndDate() {
        let profile = ZodiacProfile(enabled: true, birthDate: LocalDate(1990, 3, 20), birthTime: LocalTime(23, 59, 30))
        let today = LocalDate(2026, 9, 26)
        XCTAssertNil(store.zodiac.getCurrentHoroscope(profile, today))

        store.zodiac.setHoroscope(profile, today, "\u{00A0} The gears turn toward you.\n")
        XCTAssertEqual(store.zodiac.getCurrentHoroscope(profile, today), "The gears turn toward you.")
        XCTAssertEqual(defaults.string(forKey: "zodiac_profile.horoscope_signature"), "true|1990-03-20|23:59:30|null|null")
        XCTAssertEqual(defaults.string(forKey: "zodiac_profile.horoscope_date"), "2026-09-26")
        XCTAssertNil(store.zodiac.getCurrentHoroscope(profile, today.plusDays(1)))
        var other = profile
        other.selectedSign = .leo
        XCTAssertNil(store.zodiac.getCurrentHoroscope(other, today))

        store.zodiac.setHoroscope(profile, today, " \t ")
        XCTAssertNil(store.zodiac.getCurrentHoroscope(profile, today))
    }

    func testReportedReadingIsHiddenUntilTomorrow() {
        let profile = ZodiacProfile(enabled: true, birthDate: LocalDate(1990, 3, 20), birthTime: LocalTime(12, 0))
        let today = LocalDate(2026, 9, 26)
        store.zodiac.setHoroscope(profile, today, "A reading.")
        XCTAssertFalse(store.zodiac.wasReadingReported(today))
        store.zodiac.hideReportedHoroscope(today)
        XCTAssertNil(store.zodiac.getCurrentHoroscope(profile, today))
        XCTAssertTrue(store.zodiac.wasReadingReported(today))
        XCTAssertFalse(store.zodiac.wasReadingReported(today.plusDays(1)))
    }

    // MARK: WatchPreferences

    func testWatchSettingsDefaults() {
        XCTAssertTrue(store.watch.showClock())
        XCTAssertFalse(store.watch.southern())
        store.watch.setShowClock(false)
        store.watch.setSouthern(true)
        XCTAssertFalse(store.watch.showClock())
        XCTAssertTrue(store.watch.southern())
        XCTAssertEqual(defaults.object(forKey: "watch_settings.clock") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "watch_settings.southern_hemisphere") as? Bool, true)
    }

    func testRequestsAreConsumedOnce() {
        XCTAssertEqual(store.watch.consumeRequest(), WatchPreferences.Request.none)
        store.watch.request(.galactic)
        XCTAssertEqual(defaults.string(forKey: "watch_settings.request"), "GALACTIC")
        XCTAssertEqual(store.watch.consumeRequest(), .galactic)
        XCTAssertEqual(store.watch.consumeRequest(), WatchPreferences.Request.none)
        store.watch.request(.now)
        XCTAssertEqual(store.watch.consumeRequest(), .now)
        defaults.set("SOMETHING_ELSE", forKey: "watch_settings.request")
        XCTAssertEqual(store.watch.consumeRequest(), WatchPreferences.Request.none)
    }
}
