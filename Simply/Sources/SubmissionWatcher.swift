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
    private static let maxWatched = 25
    private static let maxAgeMs: Double = 30 * 24 * 3600 * 1000

    /// Called after a successful save in the submit flow.
    static func watch(barcode: String, name: String) {
        var list = load().filter { $0.barcode != barcode }
        list.append(Watched(
            barcode: barcode, name: name,
            at: Date().timeIntervalSince1970 * 1000))
        save(Array(list.suffix(maxWatched)))
    }

    static func checkAndNotify() async {
        let watched = load()
        guard !watched.isEmpty else { return }
        let items = watched.map {
            ["barcode": $0.barcode, "submittedAt": $0.at] as [String: Any]
        }
        var request = URLRequest(
            url: ProductRepository.serverBase.appendingPathComponent("api/v2/submissions/status"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["items": items])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(StatusResponse.self, from: data),
              let results = decoded.results
        else { return }

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

    private static func load() -> [Watched] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Watched].self, from: data)
        else { return [] }
        return list
    }

    private static func save(_ list: [Watched]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
    }
}
