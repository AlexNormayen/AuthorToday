import Foundation
import Combine

/// Soft Pro nudge after several active reading days (not on first launch).
@MainActor
final class ProNudgeStore: ObservableObject {
    static let shared = ProNudgeStore()

    private let defaults = UserDefaults.standard
    private let firstSeenKey = "pro.nudge.firstSeenAt"
    private let activeDaysKey = "pro.nudge.activeDayKeys"
    private let lastShownKey = "pro.nudge.lastShownAt"

    /// Active calendar days of reading before a nudge is eligible.
    private let minActiveDays = 3
    /// Minimum days between soft nudges.
    private let cooldownDays: TimeInterval = 14 * 24 * 60 * 60
    /// Don't nudge on the calendar day of first install/open.
    private let minInstallAge: TimeInterval = 24 * 60 * 60

    @Published var showPaywall = false

    private init() {
        if defaults.object(forKey: firstSeenKey) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: firstSeenKey)
        }
    }

    func recordActiveReadingDay() {
        var days = Set(defaults.stringArray(forKey: activeDaysKey) ?? [])
        days.insert(Self.dayKey(Date()))
        defaults.set(Array(days), forKey: activeDaysKey)
    }

    /// Call from main UI when appropriate; returns whether a sheet should open.
    func considerPresenting(isProUnlocked: Bool) -> Bool {
        guard !isProUnlocked else { return false }
        let first = Date(timeIntervalSince1970: defaults.double(forKey: firstSeenKey))
        guard Date().timeIntervalSince(first) >= minInstallAge else { return false }

        let days = defaults.stringArray(forKey: activeDaysKey) ?? []
        guard days.count >= minActiveDays else { return false }

        let last = defaults.double(forKey: lastShownKey)
        if last > 0, Date().timeIntervalSince1970 - last < cooldownDays {
            return false
        }

        defaults.set(Date().timeIntervalSince1970, forKey: lastShownKey)
        showPaywall = true
        return true
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
