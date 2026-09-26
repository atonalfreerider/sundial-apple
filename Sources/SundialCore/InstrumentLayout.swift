import Foundation

/// The screen the instrument is fitted to. Watches get their own geometry, labels and chrome.
public enum InstrumentLayout: Sendable {
    case phone
    case watchRound
    case watchRect

    public var isWatch: Bool { self != .phone }
}
