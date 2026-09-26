import Foundation

/// Seasons of the civil year (northern names) with soft edges: within [blendDays] of a solstice or
/// equinox the outgoing season fades into the incoming one instead of switching at a hard line.
public enum SeasonBands {
    public static let blendDays = 12.0

    public struct Mix: Hashable, Sendable {
        public let from: Zodiac.Season
        public let to: Zodiac.Season
        public let amount: Double

        public init(_ from: Zodiac.Season, _ to: Zodiac.Season, _ amount: Double) {
            self.from = from
            self.to = to
            self.amount = amount
        }
    }

    /// Year fractions at which spring, summer, fall and winter begin.
    public static func starts(_ year: Int) -> [(Double, Zodiac.Season)] {
        let days = Double(Astronomy.daysInYear(year))
        func fraction(_ month: Int, _ day: Int) -> Double { Double(LocalDate(year, month, day).dayOfYear - 1) / days }
        return [
            (fraction(3, 21), .spring),
            (fraction(6, 21), .summer),
            (fraction(9, 23), .fall),
            (fraction(12, 22), .winter),
        ]
    }

    public static func mixAt(_ fraction: Double, _ starts: [(Double, Zodiac.Season)], _ daysInYear: Int) -> Mix {
        let halfWidth = blendDays / Double(daysInYear)
        for (index, (start, season)) in starts.enumerated() {
            var offset = fraction - start
            offset -= floor(offset + 0.5)
            if abs(offset) < halfWidth {
                let previous = starts[(index + starts.count - 1) % starts.count].1
                let t = (offset + halfWidth) / (2 * halfWidth)
                return Mix(previous, season, t * t * (3 - 2 * t))
            }
        }
        let season = starts.last { fraction >= $0.0 }?.1 ?? starts.last!.1
        return Mix(season, season, 0.0)
    }
}
