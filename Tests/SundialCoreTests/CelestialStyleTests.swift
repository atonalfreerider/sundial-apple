import XCTest
@testable import SundialCore

final class CelestialStyleTests: XCTestCase {
    func testElementPalettesAreHiddenAndSelectedByAstrology() {
        XCTAssertFalse(CelestialStyle.fire.pickable)
        XCTAssertFalse(CelestialStyle.pickableCases.contains(.fire))
        XCTAssertEqual(CelestialStyle.effective(.voidBlack,
            ZodiacProfile(enabled: true, birthDate: LocalDate(1990, 4, 18))), .fire)
        XCTAssertEqual(CelestialStyle.effective(.crimsonNebula,
            ZodiacProfile(enabled: true, birthDate: LocalDate(1990, 5, 5))), .earth)
    }

    func testBrassOverridesAstrologyElement() {
        XCTAssertEqual(CelestialStyle.effective(.brassWatch,
            ZodiacProfile(enabled: true, birthDate: LocalDate(1990, 7, 5))), .brassWatch)
    }
}
