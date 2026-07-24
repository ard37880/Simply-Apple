import Foundation

/// Remembers which barcodes the user already answered the bioengineered
/// label question for, so the product page never re-asks. The answer
/// itself travels through the facts-submission pipeline and goes live
/// after review; this store only silences the question on this device.
enum BioAnswers {
    private static let answeredKey = "bioengineered.answered"

    static func answered(_ barcode: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: answeredKey) ?? [])
            .contains(barcode)
    }

    static func markAnswered(_ barcode: String) {
        var done = UserDefaults.standard.stringArray(forKey: answeredKey) ?? []
        guard !done.contains(barcode) else { return }
        done.append(barcode)
        UserDefaults.standard.set(done, forKey: answeredKey)
    }
}

/// The opt-in "did you buy this?" crowdsourcing loop. Answers are anonymous
/// yes/no counts sent to the Simply Pure server; when the user also has
/// location tagging on, a "yes" carries a coarse "City, ST" so availability
/// can be understood by region. Nothing identifies the user, and each
/// product is only ever asked about once (answered barcodes are remembered
/// on the device).
final class CrowdRepository {
    static let shared = CrowdRepository()

    private static let answeredKey = "crowd.answered"

    private static func answerKey(_ barcode: String) -> String { "crowd.answer:\(barcode)" }
    private static func regionKey(_ barcode: String) -> String { "crowd.region:\(barcode)" }

    var enabled: Bool { ProfileStore.shared.crowdsourcing }

    func answered(_ barcode: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: Self.answeredKey) ?? [])
            .contains(barcode)
    }

    /// The answer this device gave, when known. Answers from before the
    /// change-your-mind feature stored only the asked flag, so they return
    /// nil and cannot be changed (retracting an unknown answer would skew
    /// the anonymous counts).
    func answerOf(_ barcode: String) -> Bool? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.answerKey(barcode)) != nil else { return nil }
        return defaults.bool(forKey: Self.answerKey(barcode))
    }

    func answer(_ barcode: String, bought: Bool) async {
        // Remember locally first: even if the post fails, never re-ask.
        var done = UserDefaults.standard.stringArray(forKey: Self.answeredKey) ?? []
        if !done.contains(barcode) { done.append(barcode) }
        UserDefaults.standard.set(done, forKey: Self.answeredKey)

        var region: String?
        if bought, ProfileStore.shared.locationTagging {
            region = await LocationTagger.shared.cityState()
        }
        remember(barcode, bought: bought, region: region)
        await post(barcode, bought: bought, region: region,
                   previous: nil, previousRegion: nil)
    }

    /// A changed mind: retracts the stored answer on the server (counts
    /// stay anonymous, so the client reports what it is retracting) and
    /// records the new one.
    func changeAnswer(_ barcode: String, bought: Bool) async {
        guard let previous = answerOf(barcode), previous != bought else { return }
        let previousRegion = UserDefaults.standard.string(forKey: Self.regionKey(barcode))
        var region: String?
        if bought, ProfileStore.shared.locationTagging {
            region = await LocationTagger.shared.cityState()
        }
        remember(barcode, bought: bought, region: region)
        await post(barcode, bought: bought, region: region,
                   previous: previous, previousRegion: previousRegion)
    }

    private func remember(_ barcode: String, bought: Bool, region: String?) {
        let defaults = UserDefaults.standard
        defaults.set(bought, forKey: Self.answerKey(barcode))
        if let region {
            defaults.set(region, forKey: Self.regionKey(barcode))
        } else {
            defaults.removeObject(forKey: Self.regionKey(barcode))
        }
    }

    private func post(
        _ barcode: String, bought: Bool, region: String?,
        previous: Bool?, previousRegion: String?
    ) async {
        var payload: [String: Any] = ["bought": bought]
        if let region { payload["region"] = region }
        // The retraction keys only travel when set, matching the Android
        // client (kotlinx omits nulls).
        if let previous { payload["previous"] = previous }
        if let previousRegion { payload["previousRegion"] = previousRegion }
        var request = URLRequest(
            url: ProductRepository.serverBase.appendingPathComponent("api/v2/crowd/\(barcode)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Nil when opted out, below the server's threshold, or unreachable.
    /// Wording is decided here so it matches Android exactly.
    func signal(_ barcode: String) async -> String? {
        guard enabled else { return nil }
        let request = URLRequest(
            url: ProductRepository.serverBase.appendingPathComponent("api/v2/crowd/\(barcode)"))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(CrowdResponse.self, from: data)
        else { return nil }
        switch decoded.signal {
        case "most": return "Most scanners bought this"
        case "mixed": return "Some scanners buy this, some pass"
        case "few": return "Most scanners passed on this"
        default: return nil
        }
    }

    private struct CrowdResponse: Decodable {
        let total: Int?
        let signal: String?
    }
}

/// Features that move behind the premium subscription at production.
enum PremiumFeature { case search, personalization, preferenceAlerts, recallAlerts, customThemes }

/// Premium gating, dormant during the beta. Whether gates are enforced at
/// all comes from the server (/api/v2/config), fetched once per launch and
/// remembered across launches, so flipping premium on at production is a
/// server change rather than an app release. Everything fails open: no
/// server answer means nothing is locked, and beta builds see no change
/// because the flag is off.
///
/// The subscription itself (StoreKit) is not wired yet; until it is,
/// `premium` only reads a local flag so the whole path can be exercised.
final class Entitlements {
    static let shared = Entitlements()

    private static let gatesKey = "entitlements.gatesEnabled"
    private static let premiumKey = "entitlements.premium"

    func locked(_ feature: PremiumFeature) -> Bool {
        UserDefaults.standard.bool(forKey: Self.gatesKey)
            && !UserDefaults.standard.bool(forKey: Self.premiumKey)
    }

    /// Scoring uses the profile's diets unless personalization is locked.
    var activeDiets: Set<String> {
        locked(.personalization) ? [] : ProfileStore.shared.diets
    }

    /// Refreshes the server flag; quietly keeps the last value on failure.
    func refresh() async {
        let request = URLRequest(
            url: ProductRepository.serverBase.appendingPathComponent("api/v2/config"))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ConfigResponse.self, from: data)
        else { return }
        UserDefaults.standard.set(decoded.premiumGatesEnabled ?? false, forKey: Self.gatesKey)
    }

    private struct ConfigResponse: Decodable {
        let premiumGatesEnabled: Bool?
    }
}
