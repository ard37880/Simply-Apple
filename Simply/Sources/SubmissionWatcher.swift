import Foundation
import UserNotifications

/// Remembers what this device submitted for review and, on later launches,
/// asks the server what happened. An approved submission becomes a local
/// notification inviting the user back to see the product's new rating.
/// Rejected and stale entries are dropped quietly (nobody wants a scolding
/// notification), pending ones keep waiting. Only barcodes this device
/// already submitted are sent. Mirrors Android's SubmissionWatcher.
enum SubmissionWatcher {

    private struct Watched: Codable {
        var barcode: String
        var name: String
        var at: Double // ms since epoch, matching the server's timestamps
    }

    private struct StatusResponse: Codable {
        var ok: Bool?
        var results: [String: String]?
    }

    private static let key = "submissions.watched"
    private static let journalKey = "submissions.journal"
    private static let seededKey = "submissions.journalSeeded"
    private static let countKey = "submissions.approvedCount"
    private static let maxWatched = 25
    private static let maxJournal = 200
    private static let maxAgeMs: Double = 30 * 24 * 3600 * 1000

    /// How many products this device helped fix: journaled submissions the
    /// server reports approved. Recomputed on every check from the permanent
    /// journal below, so it never depends on notification permission and
    /// self-corrects if a submission is later rejected.
    static var approvedCount: Int {
        UserDefaults.standard.integer(forKey: countKey)
    }

    /// Karma: how many times the community has scanned this device's
    /// approved contributions since each went live. Computed by the server
    /// from anonymous per-barcode tallies; attribution never leaves this
    /// device (the journal is the only record of who submitted what).
    private static let impactKey = "submissions.impactPoints"
    static var impactPoints: Int {
        UserDefaults.standard.integer(forKey: impactKey)
    }

    /// Permanent journal of every barcode this device ever submitted, with
    /// the first submission time. The watch list drops entries once they
    /// resolve (nobody should be re-notified), but the profile's helped
    /// counter needs the full record: approved archives live forever on the
    /// server, so a journaled barcode can be counted years later. Deduped
    /// by barcode; the earliest timestamp maximizes archive matches.
    private static func journalAdd(_ barcode: String) {
        var journal = loadJournal()
        guard !journal.contains(where: { $0.barcode == barcode }) else { return }
        journal.append(Watched(
            barcode: barcode, name: "",
            at: Date().timeIntervalSince1970 * 1000))
        saveJournal(Array(journal.suffix(maxJournal)))
    }

    /// Journal snapshot for device sync: barcode to first-submitted ms.
    static func journalEntries() -> [(barcode: String, at: Int64)] {
        loadJournal().map { ($0.barcode, Int64($0.at)) }
    }

    /// Adopts journal entries synced from a paired device, so the helped
    /// counters survive a phone upgrade or wipe. Union by barcode keeping
    /// the earliest time (archives match best from the first submission).
    /// Returns true when anything changed so the caller can recount.
    static func mergeJournalEntries(_ entries: [(barcode: String, at: Int64)]) -> Bool {
        guard !entries.isEmpty else { return false }
        var journal = loadJournal()
        var changed = false
        for entry in entries {
            let at = Double(entry.at)
            if let index = journal.firstIndex(where: { $0.barcode == entry.barcode }) {
                if at < journal[index].at {
                    journal[index].at = at
                    changed = true
                }
            } else {
                journal.append(Watched(barcode: entry.barcode, name: "", at: at))
                changed = true
            }
        }
        if changed { saveJournal(Array(journal.suffix(maxJournal))) }
        return changed
    }

    /// Called after a successful save in the submit flow.
    static func watch(barcode: String, name: String) {
        var list = load().filter { $0.barcode != barcode }
        list.append(Watched(
            barcode: barcode, name: name,
            at: Date().timeIntervalSince1970 * 1000))
        save(Array(list.suffix(maxWatched)))
        journalAdd(barcode)
    }

    static func checkAndNotify() async {
        // Existing installs have submissions in flight that predate the
        // journal; adopt them once so their approvals count too.
        let watched = load()
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: seededKey) {
            var journal = loadJournal()
            let known = Set(journal.map(\.barcode))
            for entry in watched where !known.contains(entry.barcode) {
                journal.append(Watched(barcode: entry.barcode, name: "", at: entry.at))
            }
            saveJournal(Array(journal.suffix(maxJournal)))
            defaults.set(true, forKey: seededKey)
        }

        if !watched.isEmpty, let results = await fetchStatuses(watched) {
            var keep: [Watched] = []
            let center = UNUserNotificationCenter.current()
            for entry in watched {
                switch results[entry.barcode] {
                case "approved":
                    let label = entry.name.isEmpty ? "the product" : entry.name
                    let content = UNMutableNotificationContent()
                    content.title = "Your submission was approved!"
                    content.body = "Your correction is now live for every Simply Pure "
                        + "user. Open \(label) in Simply Pure to see its updated rating."
                    content.sound = .default
                    try? await center.add(UNNotificationRequest(
                        identifier: "submission-\(entry.barcode)",
                        content: content, trigger: nil))
                case "rejected":
                    break
                default:
                    if Date().timeIntervalSince1970 * 1000 - entry.at < maxAgeMs {
                        keep.append(entry)
                    }
                }
            }
            save(keep)
        }

        // The helped counter asks separately: journal timestamps are the
        // FIRST submission per barcode (a watched resubmission would report
        // a stale approval as this one's), and the server answers at most
        // 50 barcodes per request.
        let journal = loadJournal()
        guard !journal.isEmpty else { return }
        var approved = 0
        var impact = 0
        var index = 0
        while index < journal.count {
            let chunk = Array(journal[index ..< min(index + 50, journal.count)])
            guard let results = await fetchStatuses(chunk) else { return }
            approved += chunk.filter { results[$0.barcode] == "approved" }.count
            guard let impacts = await fetchImpact(chunk) else { return }
            impact += impacts.values.reduce(0, +)
            index += 50
        }
        defaults.set(approved, forKey: countKey)
        defaults.set(impact, forKey: impactKey)
    }

    private struct ImpactResponse: Codable {
        var ok: Bool?
        var results: [String: Int]?
    }

    private static func fetchImpact(_ items: [Watched]) async -> [String: Int]? {
        let payload = items.map {
            ["barcode": $0.barcode, "submittedAt": $0.at] as [String: Any]
        }
        var request = URLRequest(
            url: ProductRepository.serverBase.appendingPathComponent("api/v2/submissions/impact"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["items": payload])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ImpactResponse.self, from: data)
        else { return nil }
        return decoded.results ?? [:]
    }

    private static func fetchStatuses(_ items: [Watched]) async -> [String: String]? {
        let payload = items.map {
            ["barcode": $0.barcode, "submittedAt": $0.at] as [String: Any]
        }
        var request = URLRequest(
            url: ProductRepository.serverBase.appendingPathComponent("api/v2/submissions/status"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["items": payload])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(StatusResponse.self, from: data)
        else { return nil }
        return decoded.results
    }

    private static func load() -> [Watched] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Watched].self, from: data)
        else { return [] }
        return list
    }

    private static func save(_ list: [Watched]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
    }

    private static func loadJournal() -> [Watched] {
        guard let data = UserDefaults.standard.data(forKey: journalKey),
              let list = try? JSONDecoder().decode([Watched].self, from: data)
        else { return [] }
        return list
    }

    private static func saveJournal(_ list: [Watched]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: journalKey)
    }
}
