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

/// What entering a supporter code came back with.
enum RedeemResult { case unlocked, inactive, invalid, inUse, network }

/// Premium gating, dormant during the beta. Whether gates are enforced at
/// all comes from the server (/api/v2/config), fetched once per launch and
/// remembered across launches, so flipping premium on at production is a
/// server change rather than an app release. Everything fails open: no
/// server answer means nothing is locked, and beta builds see no change
/// because the flag is off.
///
/// Premium itself is a supporter code: after contributing on the website,
/// the thanks page shows a SIMPLY-XXXX-XXXX code the user types in once.
/// The server ties it to the Stripe subscription; we re-verify at most
/// once a day and keep the last known answer when the network is down,
/// so a paying supporter is never locked out by a hiccup.
final class Entitlements {
    static let shared = Entitlements()

    private static let gatesKey = "entitlements.gatesEnabled"
    private static let premiumKey = "entitlements.premium"
    private static let codeKey = "entitlements.supporterCode"
    private static let checkedKey = "entitlements.supporterChecked"
    private static let recheckSeconds: TimeInterval = 24 * 3600

    private static let grandfatheredKey = "entitlements.grandfathered"

    func locked(_ feature: PremiumFeature) -> Bool {
        UserDefaults.standard.bool(forKey: Self.gatesKey)
            && !UserDefaults.standard.bool(forKey: Self.premiumKey)
            && !UserDefaults.standard.bool(forKey: Self.grandfatheredKey)
    }

    /// Beta testers keep premium for free, forever: the first launch of a
    /// build that knows about grandfathering decides, exactly once, based
    /// on whether this install already existed (was onboarded) while the
    /// gates were still off. Fresh installs decide false and stay false.
    func grandfatherExistingInstall(alreadyOnboarded: Bool) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.grandfatheredKey) == nil else { return }
        let gatesOn = defaults.bool(forKey: Self.gatesKey)
        defaults.set(alreadyOnboarded && !gatesOn, forKey: Self.grandfatheredKey)
    }

    var isSupporter: Bool { UserDefaults.standard.bool(forKey: Self.premiumKey) }
    var supporterCode: String? { UserDefaults.standard.string(forKey: Self.codeKey) }
    var isCancelled: Bool { UserDefaults.standard.bool(forKey: Self.cancelledKey) }

    /// "July 26, 2027" style end date, empty when unknown.
    var premiumEndsText: String {
        let ends = UserDefaults.standard.double(forKey: Self.endsKey)
        guard ends > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: Date(timeIntervalSince1970: ends))
    }

    private static let cancelledKey = "entitlements.supporterCancelled"
    private static let endsKey = "entitlements.supporterEnds"

    /// Scoring uses the profile's diets unless personalization is locked.
    var activeDiets: Set<String> {
        locked(.personalization) ? [] : ProfileStore.shared.diets
    }

    /// Verifies and stores a typed supporter code.
    func redeem(_ entered: String) async -> RedeemResult {
        let result = await verifyWithServer(
            entered.trimmingCharacters(in: .whitespacesAndNewlines))
        if result == .unlocked || result == .inactive {
            // Even an inactive code is worth remembering: a lapsed
            // subscription that gets paid again re-unlocks on re-verify.
            UserDefaults.standard.set(
                Date().timeIntervalSince1970, forKey: Self.checkedKey)
        }
        return result
    }

    func removeSupporterCode() {
        UserDefaults.standard.removeObject(forKey: Self.codeKey)
        UserDefaults.standard.set(false, forKey: Self.premiumKey)
    }

    /// Refreshes the server gate flag, and re-verifies a stored supporter
    /// code at most once a day. Both quietly keep the last known state on
    /// any failure.
    func refresh() async {
        let request = URLRequest(
            url: ProductRepository.serverBase.appendingPathComponent("api/v2/config"))
        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let decoded = try? JSONDecoder().decode(ConfigResponse.self, from: data) {
            UserDefaults.standard.set(
                decoded.premiumGatesEnabled ?? false, forKey: Self.gatesKey)
        }
        guard let code = supporterCode else { return }
        let checked = UserDefaults.standard.double(forKey: Self.checkedKey)
        guard Date().timeIntervalSince1970 - checked >= Self.recheckSeconds else { return }
        let result = await verifyWithServer(code)
        if result != .network {
            UserDefaults.standard.set(
                Date().timeIntervalSince1970, forKey: Self.checkedKey)
        }
        if result == .invalid {
            // The server no longer knows this code; stop claiming premium.
            removeSupporterCode()
        }
        if result == .inUse {
            // Bound to a different device now; keep the code stored (the
            // user may pair with that device) but stop claiming premium.
            UserDefaults.standard.set(false, forKey: Self.premiumKey)
        }
    }

    /// Cancels the supporter subscription at Stripe (it finishes the paid
    /// period, then does not renew). Premium stays on until the daily
    /// re-verify sees the subscription actually end.
    func cancelSubscription() async -> Bool {
        guard let code = supporterCode else { return false }
        var request = URLRequest(
            url: ProductRepository.serverBase.appendingPathComponent("api/v2/supporter/cancel"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode,
              (200..<300).contains(status)
        else { return false }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.cancelledKey)
        if let parsed = try? JSONDecoder().decode(CancelResponse.self, from: data),
           let ends = parsed.endsAt {
            defaults.set(Double(ends), forKey: Self.endsKey)
        }
        return true
    }

    private struct CancelResponse: Decodable {
        let ok: Bool?
        let endsAt: Int64?
    }

    private func verifyWithServer(_ code: String) async -> RedeemResult {
        var request = URLRequest(
            url: ProductRepository.serverBase.appendingPathComponent("api/v2/supporter/verify"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = ["code": code, "device": SyncEngine.shared.deviceId]
        if let group = SyncEngine.shared.channelId { payload["group"] = group }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return .network }
        if status == 403 { return .inUse }
        if status == 404 || status == 400 { return .invalid }
        guard status == 200,
              let decoded = try? JSONDecoder().decode(VerifyResponse.self, from: data)
        else { return .network }
        guard decoded.ok == true else { return .invalid }
        let defaults = UserDefaults.standard
        defaults.set(decoded.code ?? code, forKey: Self.codeKey)
        defaults.set(decoded.active ?? false, forKey: Self.premiumKey)
        // Server truth for the cancel banner, so it self-corrects.
        defaults.set(decoded.cancelAtPeriodEnd ?? false, forKey: Self.cancelledKey)
        defaults.set(Double(decoded.endsAt ?? 0), forKey: Self.endsKey)
        return (decoded.active ?? false) ? .unlocked : .inactive
    }

    private struct ConfigResponse: Decodable {
        let premiumGatesEnabled: Bool?
    }

    private struct VerifyResponse: Decodable {
        let ok: Bool?
        let code: String?
        let active: Bool?
        let cancelAtPeriodEnd: Bool?
        let endsAt: Int64?
    }
}
