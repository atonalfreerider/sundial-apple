import Foundation

/// Compact symbols keep US holiday calendars legible on the annual ring.
public enum HolidayIcons {
    public static let fallback = "★"

    public static func isHolidayCalendar(_ displayName: String, _ ownerAccount: String? = nil) -> Bool {
        displayName.localizedCaseInsensitiveContains("holiday") ||
            (ownerAccount?.localizedCaseInsensitiveContains("#holiday@") ?? false)
    }

    public static func icon(for title: String) -> String {
        let name = title.lowercased()
        return rules.first { rule in rule.0.contains { name.contains($0) } }?.1 ?? fallback
    }

    private static let rules: [([String], String)] = [
        (["lunar new year", "chinese new year"], "🏮"), (["new year's eve", "new years eve"], "🥂"),
        (["new year"], "🎉"), (["martin luther king", "mlk"], "✊"), (["groundhog"], "🦫"),
        (["lincoln", "president", "washington's birthday"], "🎩"), (["valentine"], "❤️"),
        (["daylight saving"], "⏰"), (["patrick"], "☘️"), (["tax day"], "🧾"),
        (["good friday"], "✝️"), (["easter"], "🐣"), (["earth day"], "🌍"),
        (["cinco de mayo"], "🌮"), (["mother"], "💐"),
        (["armed forces", "memorial", "veteran"], "🎖️"), (["flag day"], "🇺🇸"),
        (["juneteenth"], "🕊️"), (["father"], "👔"), (["independence"], "🎆"),
        (["labor day", "labour day"], "🛠️"), (["indigenous"], "🪶"), (["columbus"], "🧭"),
        (["halloween"], "🎃"), (["election"], "🗳️"),
        (["black friday", "day after thanksgiving", "cyber monday"], "🛍️"),
        (["thanksgiving"], "🦃"), (["rosh hashanah"], "🍎"), (["yom kippur"], "🕯️"),
        (["hanukkah", "chanukah"], "🕎"), (["diwali"], "🪔"), (["ramadan", "eid"], "🌙"),
        (["christmas eve"], "🌟"), (["christmas"], "🎄"), (["kwanzaa"], "🕯️"),
        (["first day of", "solstice", "equinox"], "☀️"),
    ]
}
