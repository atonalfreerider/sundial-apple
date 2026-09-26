import Foundation
import XCTest
@testable import SundialRender

/// KotlinRandom against kotlin.random.Random: the sequences and the two star fields recorded from
/// the Android code in SundialCoreTests/Resources/android-reference.json (see its README).
final class KotlinRandomTests: XCTestCase {
    func testNextIntMatchesKotlin() throws {
        let reference = try Self.reference()
        XCTAssertFalse(reference.nextInt.isEmpty)
        for record in reference.nextInt {
            var random = KotlinRandom(seed: record.seed)
            let output = (0..<record.output.count).map { _ in random.nextInt() }
            XCTAssertEqual(output, record.output, "seed \(record.seed)")
        }
    }

    func testNextFloatMatchesKotlin() throws {
        let reference = try Self.reference()
        XCTAssertFalse(reference.nextFloat.isEmpty)
        for record in reference.nextFloat {
            var random = KotlinRandom(seed: record.seed)
            let output = (0..<record.output.count).map { _ in Double(random.nextFloat()) }
            XCTAssertEqual(output, record.output, "seed \(record.seed)")
        }
    }

    func testNextIntUntilMatchesKotlin() throws {
        let reference = try Self.reference()
        XCTAssertFalse(reference.nextIntUntil.isEmpty)
        for record in reference.nextIntUntil {
            var random = KotlinRandom(seed: record.seed)
            let output = (0..<record.output.count).map { _ in random.nextInt(record.until) }
            XCTAssertEqual(output, record.output, "seed \(record.seed) until \(record.until)")
        }
    }

    /// SundialView.ambientStars, computed as Kotlin computes it: in Float, with kotlin.math's
    /// Float sqrt/cos/sin (Math.sqrt / cos / sin of the Double, rounded to Float) and PI.toFloat().
    func testAmbientStarsMatchKotlin() throws {
        let reference = try Self.reference()
        XCTAssertEqual(reference.ambientStars.count, 170)
        var random = KotlinRandom(seed: 0x51A7_D1A1)
        for (index, expected) in reference.ambientStars.enumerated() {
            let radius = Float(sqrt(Double(random.nextFloat())))
            let angle = random.nextFloat() * 2 * Float(Double.pi)
            let xFraction = radius * Float(cos(Double(angle)))
            let yFraction = radius * Float(sin(Double(angle)))
            let radiusDp: Float = 0.28 + random.nextFloat() * (index % 11 == 0 ? 1.12 : 0.63)
            let alpha = 30 + Int(random.nextInt(index % 11 == 0 ? 100 : 64))
            let flare = index % 17 == 0
            XCTAssertEqual(expected.index, index)
            XCTAssertEqual(expected.radius, Double(radius), "star \(index) radius")
            XCTAssertEqual(expected.angle, Double(angle), "star \(index) angle")
            XCTAssertEqual(expected.xFraction, Double(xFraction), "star \(index) xFraction")
            XCTAssertEqual(expected.yFraction, Double(yFraction), "star \(index) yFraction")
            XCTAssertEqual(expected.radiusDp, Double(radiusDp), "star \(index) radiusDp")
            XCTAssertEqual(expected.alpha, alpha, "star \(index) alpha")
            XCTAssertEqual(expected.flare, flare, "star \(index) flare")
        }
    }

    /// SundialView.dustLaneStars, likewise.
    func testDustLaneStarsMatchKotlin() throws {
        let reference = try Self.reference()
        XCTAssertEqual(reference.dustLaneStars.count, 64)
        var random = KotlinRandom(seed: 0x0B1_7A5E)
        for (index, expected) in reference.dustLaneStars.enumerated() {
            let x = random.nextFloat()
            let yFraction = min(max(0.10 + x * 0.78 + (random.nextFloat() - 0.5) * 0.13, 0.02), 0.98)
            let radiusDp = 0.20 + random.nextFloat() * 0.42
            let alpha = 12 + Int(random.nextInt(34))
            XCTAssertEqual(expected.index, index)
            XCTAssertNil(expected.radius)
            XCTAssertNil(expected.angle)
            XCTAssertEqual(expected.xFraction, Double(x), "dust \(index) xFraction")
            XCTAssertEqual(expected.yFraction, Double(yFraction), "dust \(index) yFraction")
            XCTAssertEqual(expected.radiusDp, Double(radiusDp), "dust \(index) radiusDp")
            XCTAssertEqual(expected.alpha, alpha, "dust \(index) alpha")
            XCTAssertFalse(expected.flare)
        }
    }

    /// The star fields the Instrument itself builds, bit for bit.
    func testInstrumentSkyMatchesKotlin() throws {
        let reference = try Self.reference()
        let instrument = Instrument(earthTexture: PixelImage(width: 2, height: 1))
        XCTAssertEqual(instrument.ambientStars.count, reference.ambientStars.count)
        for (index, (star, expected)) in zip(instrument.ambientStars, reference.ambientStars).enumerated() {
            XCTAssertEqual(star.xFraction, expected.xFraction, "star \(index) xFraction")
            XCTAssertEqual(star.yFraction, expected.yFraction, "star \(index) yFraction")
            XCTAssertEqual(star.radiusDp, expected.radiusDp, "star \(index) radiusDp")
            XCTAssertEqual(star.alpha, expected.alpha, "star \(index) alpha")
            XCTAssertEqual(star.flare, expected.flare, "star \(index) flare")
        }
        XCTAssertEqual(instrument.dustLaneStars.count, reference.dustLaneStars.count)
        for (index, (star, expected)) in zip(instrument.dustLaneStars, reference.dustLaneStars).enumerated() {
            XCTAssertEqual(star.xFraction, expected.xFraction, "dust \(index) xFraction")
            XCTAssertEqual(star.yFraction, expected.yFraction, "dust \(index) yFraction")
            XCTAssertEqual(star.radiusDp, expected.radiusDp, "dust \(index) radiusDp")
            XCTAssertEqual(star.alpha, expected.alpha, "dust \(index) alpha")
        }
    }

    // MARK: Reference data

    /// The keys of android-reference.json this suite reads. Floats are recorded widened to Double,
    /// so they are read as Doubles and compared exactly.
    struct Reference: Decodable {
        struct Sequence<Value: Decodable>: Decodable {
            let seed: Int32
            let output: [Value]
        }

        struct Until: Decodable {
            let seed: Int32
            let until: Int32
            let output: [Int32]
        }

        struct Star: Decodable {
            let index: Int
            let radius: Double?
            let angle: Double?
            let xFraction: Double
            let yFraction: Double
            let radiusDp: Double
            let alpha: Int
            let flare: Bool
        }

        let nextFloat: [Sequence<Double>]
        let nextInt: [Sequence<Int32>]
        let nextIntUntil: [Until]
        let ambientStars: [Star]
        let dustLaneStars: [Star]

        enum CodingKeys: String, CodingKey {
            case nextFloat = "Random.nextFloat"
            case nextInt = "Random.nextInt"
            case nextIntUntil = "Random.nextIntUntil"
            case ambientStars = "SundialView.ambientStars"
            case dustLaneStars = "SundialView.dustLaneStars"
        }
    }

    private static var cached: Reference?

    /// The file lives in SundialCoreTests' resources; it is found beside this source file, so the
    /// suite skips where the sources are not on disk (on a device).
    static func reference() throws -> Reference {
        if let cached { return cached }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SundialCoreTests/Resources/android-reference.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("android-reference.json not found at \(url.path)")
        }
        // JSONDecoder reads every double in the file bit-exactly; JSONSerialization on Linux does not.
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
        cached = reference
        return reference
    }
}
