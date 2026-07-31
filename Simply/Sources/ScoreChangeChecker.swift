import Foundation
import UserNotifications

/// Watches previously scanned products for score changes: a regulatory-rules
/// update or a product-data correction can move a score after the fact, and
/// someone who scanned that product deserves to hear about it.
///
/// Runs at most once per `period` unless the applied rules version changed
/// since the last run. Compares STANDARD scores (never personalized) against
/// its own baseline, so editing diet preferences never fires alerts. The
/// baseline seeds silently on first run. Shares the recall-alerts opt-in,
/// same as Android.
enum ScoreChangeChecker {

    private static let maxCheck = 25
    private static let period: TimeInterval = 72 * 60 * 60 // 3 days
    private static let lastRunKey = "watchlist.lastRun"
    private static let rulesVersionKey = "watchlist.rulesVersion"
    private static let scoresKey = "watchlist.scores"
    private static let pendingKey = "watchlist.pending"

    struct Change {
        let name: String
        let from: Int
        let to: Int
    }

    static func checkAndNotify() async {
        guard ProfileStore.shared.recallAlerts else { return }
        let defaults = UserDefaults.standard

        // "rules.version" is the version RulesUpdater last applied.
        let rulesVersion = defaults.string(forKey: "rules.version")
        let rulesChanged = rulesVersion != defaults.string(forKey: rulesVersionKey)
        let due = Date().timeIntervalSince1970 - defaults.double(forKey: lastRunKey) > period
        guard rulesChanged || due else { return }

        let history = await MainActor.run {
            Array(HistoryStore.shared.records.prefix(maxCheck))
        }
        guard !history.isEmpty else { return }

        var baseline = (defaults.dictionary(forKey: scoresKey) as? [String: Int]) ?? [:]
        var pending = (defaults.dictionary(forKey: pendingKey) as? [String: Int]) ?? [:]
        var changes: [Change] = []
        for record in history {
            // peek() never writes the scan-history record, so background
            // re-scoring can't reorder recents or refresh scan timestamps.
            // A partial fetch (an upstream outage dropped the nutrition or
            // additive data) is skipped entirely: comparing against it fires
            // false alarms and writing it poisons the baseline.
            guard case .found(let product, let score) =
                    await ProductRepository.shared.peek(barcode: record.barcode),
                  let standard = score.total,
                  !score.isPartial
            else { continue }
            guard let known = baseline[record.barcode] else {
                baseline[record.barcode] = standard // seed silently
                continue
            }
            if standard == known {
                pending.removeValue(forKey: record.barcode)
            } else if pending[record.barcode] == standard {
                // The new score held across two runs: a real change, not a
                // one-off data flap. Notify and move the baseline.
                changes.append(Change(name: product.name, from: known, to: standard))
                baseline[record.barcode] = standard
                pending.removeValue(forKey: record.barcode)
            } else {
                pending[record.barcode] = standard
            }
        }
        defaults.set(baseline, forKey: scoresKey)
        defaults.set(pending, forKey: pendingKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastRunKey)
        defaults.set(rulesVersion, forKey: rulesVersionKey)
        if !changes.isEmpty { await notify(changes) }
    }

    private static func notify(_ changes: [Change]) async {
        let center = UNUserNotificationCenter.current()
        for change in changes.prefix(3) {
            let direction = change.to < change.from ? "down" : "up"
            let content = UNMutableNotificationContent()
            content.title = "Score changed: \(change.name)"
            content.subtitle = "Standard score now \(change.to), was \(change.from)"
            content.body = "The standard score for \(change.name) moved \(direction) "
                + "from \(change.from) to \(change.to) after updated product data or "
                + "safety rules. Your personalized score can differ."
            content.sound = .default
            try? await center.add(UNNotificationRequest(
                identifier: "score-change-\(change.name)-\(change.from)-\(change.to)",
                content: content, trigger: nil))
        }
        if changes.count > 3 {
            let content = UNMutableNotificationContent()
            content.title = "Scores changed"
            content.body = "\(changes.count) products you scanned have new scores"
            content.sound = .default
            try? await center.add(UNNotificationRequest(
                identifier: "score-change-summary", content: content, trigger: nil))
        }
    }
}
