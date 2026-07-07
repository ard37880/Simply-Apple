import CoreLocation
import Foundation
import UserNotifications

// MARK: - FDA recall alerts

/// Matches the scan history against recent FDA food-enforcement records via
/// the Simply Pure server (which holds the openFDA key and the matching logic)
/// and raises one local notification per newly seen recall.
enum RecallChecker {

    struct Recall: Codable {
        var barcode = ""
        var recallNumber = ""
        var classification = ""
        var firm = ""
        var description = ""
        var reason = ""
        var date = ""
    }

    private struct CheckResponse: Codable {
        var recalls: [Recall] = []
    }

    static func checkAndNotify() async {
        guard ProfileStore.shared.recallAlerts else { return }
        let history = await MainActor.run { Array(HistoryStore.shared.records.prefix(100)) }
        guard !history.isEmpty else { return }

        let items = history.map {
            ["barcode": $0.barcode, "name": $0.name, "brand": $0.brand ?? ""]
        }
        var request = URLRequest(
            url: ProductRepository.serverBase.appendingPathComponent("api/v2/recalls/check"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["items": items])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(CheckResponse.self, from: data)
        else { return }

        let defaults = UserDefaults.standard
        var seen = Set(defaults.stringArray(forKey: "recalls.seen") ?? [])
        let names = Dictionary(uniqueKeysWithValues: history.map { ($0.barcode, $0.name) })
        let fresh = decoded.recalls.filter { !seen.contains("\($0.recallNumber):\($0.barcode)") }
        guard !fresh.isEmpty else { return }
        fresh.forEach { seen.insert("\($0.recallNumber):\($0.barcode)") }
        defaults.set(Array(seen), forKey: "recalls.seen")

        let center = UNUserNotificationCenter.current()
        for recall in fresh.prefix(3) {
            let content = UNMutableNotificationContent()
            let name = names[recall.barcode] ?? String(recall.description.prefix(60))
            content.title = "Recall: \(name)"
            content.body = recall.reason.isEmpty
                ? "Recalled by \(recall.firm)"
                : "\(recall.reason) — \(recall.firm) (FDA \(recall.recallNumber))"
            content.sound = .default
            try? await center.add(UNNotificationRequest(
                identifier: "recall-\(recall.recallNumber)-\(recall.barcode)",
                content: content, trigger: nil))
        }
    }
}

// MARK: - Coarse location for store submissions

/// Resolves the device position to a coarse "City, State" string for
/// tagging store submissions. Returns nil without permission, a fix, or a
/// geocoder result — never blocks on GPS.
final class LocationTagger: NSObject, CLLocationManagerDelegate {
    static let shared = LocationTagger()

    private let manager = CLLocationManager()

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func region() async -> String? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }
        manager.requestLocation()
        guard let location = manager.location else { return nil }
        guard let placemark = try? await CLGeocoder()
            .reverseGeocodeLocation(location).first else { return nil }
        let parts = [placemark.locality ?? placemark.subAdministrativeArea,
                     placemark.administrativeArea].compactMap { $0 }
        let region = parts.joined(separator: ", ")
        return region.isEmpty ? nil : region
    }

    /// Resolves the device position to a two-letter US state code and
    /// caches it; returns nil (leaving any cached value in place) without
    /// permission, a fix, or a geocoder result.
    func stateCode() async -> String? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }
        manager.requestLocation()
        guard let location = manager.location else { return nil }
        guard let placemark = try? await CLGeocoder()
            .reverseGeocodeLocation(location).first else { return nil }
        guard let code = Self.toStateCode(placemark.administrativeArea) else { return nil }
        UserDefaults.standard.set(code, forKey: Self.stateCodeKey)
        return code
    }

    /// The last state code resolved by `stateCode()`, so render paths
    /// never wait on location.
    var cachedStateCode: String? {
        UserDefaults.standard.string(forKey: Self.stateCodeKey)
    }

    private static let stateCodeKey = "location.stateCode"

    /// Geocoders return either a two-letter code or a full state name.
    private static func toStateCode(_ adminArea: String?) -> String? {
        guard let raw = adminArea?.trimmingCharacters(in: .whitespaces), !raw.isEmpty
        else { return nil }
        let upper = raw.uppercased()
        if upper.count == 2, stateCodes.values.contains(upper) { return upper }
        return stateCodes[raw.lowercased()]
    }

    private static let stateCodes: [String: String] = [
        "alabama": "AL", "alaska": "AK", "arizona": "AZ",
        "arkansas": "AR", "california": "CA", "colorado": "CO",
        "connecticut": "CT", "delaware": "DE",
        "district of columbia": "DC", "florida": "FL",
        "georgia": "GA", "hawaii": "HI", "idaho": "ID",
        "illinois": "IL", "indiana": "IN", "iowa": "IA",
        "kansas": "KS", "kentucky": "KY", "louisiana": "LA",
        "maine": "ME", "maryland": "MD", "massachusetts": "MA",
        "michigan": "MI", "minnesota": "MN", "mississippi": "MS",
        "missouri": "MO", "montana": "MT", "nebraska": "NE",
        "nevada": "NV", "new hampshire": "NH", "new jersey": "NJ",
        "new mexico": "NM", "new york": "NY", "north carolina": "NC",
        "north dakota": "ND", "ohio": "OH", "oklahoma": "OK",
        "oregon": "OR", "pennsylvania": "PA", "rhode island": "RI",
        "south carolina": "SC", "south dakota": "SD",
        "tennessee": "TN", "texas": "TX", "utah": "UT",
        "vermont": "VT", "virginia": "VA", "washington": "WA",
        "west virginia": "WV", "wisconsin": "WI", "wyoming": "WY",
    ]

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
