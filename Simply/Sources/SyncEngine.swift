import CryptoKit
import Foundation

// MARK: - Wire format (field names match the Android app exactly)

private struct SyncBundle: Codable {
    var v: Int = 1
    let ts: Int64
    var name: String = ""
    var prefsEditedAt: Int64 = 0
    var diets: [String] = []
    var allergens: [String] = []
    var history: [SyncScan] = []
}

private struct SyncScan: Codable {
    let barcode: String
    let name: String
    var brand: String?
    var imageUrl: String?
    let score: Int
    let band: String
    var hasEuBanned: Bool = false
    let scannedAt: Int64
}

// Android's kotlinx encoder omits fields that still hold their default
// (v, name, empty lists, hasEuBanned), so decoding must tolerate absence.
extension SyncBundle {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        ts = try c.decode(Int64.self, forKey: .ts)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        prefsEditedAt = try c.decodeIfPresent(Int64.self, forKey: .prefsEditedAt) ?? 0
        diets = try c.decodeIfPresent([String].self, forKey: .diets) ?? []
        allergens = try c.decodeIfPresent([String].self, forKey: .allergens) ?? []
        history = try c.decodeIfPresent([SyncScan].self, forKey: .history) ?? []
    }
}

extension SyncScan {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        barcode = try c.decode(String.self, forKey: .barcode)
        name = try c.decode(String.self, forKey: .name)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        score = try c.decode(Int.self, forKey: .score)
        band = try c.decode(String.self, forKey: .band)
        hasEuBanned = try c.decodeIfPresent(Bool.self, forKey: .hasEuBanned) ?? false
        scannedAt = try c.decode(Int64.self, forKey: .scannedAt)
    }
}

private struct SyncUpload: Codable {
    let blob: String
    let ts: Int64
}

private struct SyncPeer: Codable {
    let device: String
    let blob: String
    let ts: Int64
}

private struct SyncPeers: Codable {
    var peers: [SyncPeer] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        peers = try c.decodeIfPresent([SyncPeer].self, forKey: .peers) ?? []
    }
}

/// Paired-device sync with no accounts, wire-compatible with the Android
/// app. The pair code never leaves the two devices: the relay channel id
/// and the AES key are both derived from it, so the server only ever
/// stores ciphertext it cannot read. Each sync pushes this device's full
/// bundle (history + preferences) and merges whatever the paired device
/// last pushed: history keeps the newer scan per barcode, diets and
/// allergens combine, and a blank name fills in.
final class SyncEngine {
    static let shared = SyncEngine()
    private init() {}

    private let defaults = UserDefaults.standard

    var paired: Bool { currentCode != nil }

    /// The active pair code, shown so more devices can join later.
    var currentCode: String? { defaults.string(forKey: "sync.code") }

    private var deviceId: String {
        if let id = defaults.string(forKey: "sync.device") { return id }
        let bytes = (0..<8).map { _ in UInt8.random(in: .min ... .max) }
        let id = bytes.map { String(format: "%02x", $0) }.joined()
        defaults.set(id, forKey: "sync.device")
        return id
    }

    // Friendly fruit prefix + 4 random chars, e.g. MANGO-7K2P. The
    // unambiguous alphabet drops 0/O/1/I; guessing is impractical
    // because every attempt costs a rate-limited server roundtrip.
    // KEEP IN SYNC with SyncEngine.kt: validation depends on it.
    private static let fruits = [
        "MANGO", "PEACH", "APPLE", "LEMON", "BERRY", "MELON", "GRAPE",
        "KIWI", "PLUM", "PEAR", "CHERRY", "PAPAYA", "GUAVA", "OLIVE",
        "FIG", "DATE", "LYCHEE", "BANANA", "ORANGE", "COCONUT",
        "APRICOT", "CURRANT", "QUINCE", "POMELO",
    ]
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// Generates a fresh pair code and turns sync on for this device.
    @discardableResult
    func createCode() -> String {
        let fruit = Self.fruits.randomElement()!
        let tail = String((0..<4).map { _ in Self.alphabet.randomElement()! })
        let code = "\(fruit)-\(tail)"
        defaults.set(code, forKey: "sync.code")
        return code
    }

    /// Joins a code created on another device. Normalizes dashes/case.
    func join(_ entered: String) -> Bool {
        let cleaned = entered.uppercased().filter { $0.isLetter || $0.isNumber }
        guard let fruit = Self.fruits.first(where: { cleaned.hasPrefix($0) })
        else { return false }
        let tail = String(cleaned.dropFirst(fruit.count))
        guard tail.count == 4, tail.allSatisfy({ Self.alphabet.contains($0) })
        else { return false }
        defaults.set("\(fruit)-\(tail)", forKey: "sync.code")
        return true
    }

    func unpair() {
        defaults.removeObject(forKey: "sync.code")
    }

    var lastSync: Int64 {
        Int64(defaults.double(forKey: "sync.lastSync"))
    }

    /// Pushes this device's bundle and merges the paired device's.
    @discardableResult
    @MainActor
    func syncNow(force: Bool = false) async -> Bool {
        guard let code = currentCode else { return false }
        // Home is visited constantly; one sync a minute is plenty.
        if !force && Self.nowMs() - lastSync < 60_000 { return true }
        // Both derivations hash the DASHED form, exactly as stored.
        let key = SymmetricKey(data: Self.sha256("simply-sync-key:\(code)"))
        let channel = Self.hex(Self.sha256("simply-sync-channel:\(code)")).prefix(32)
        do {
            try await push(channel: String(channel), key: key)
            try await pull(channel: String(channel), key: key)
        } catch {
            return false
        }
        defaults.set(Double(Self.nowMs()), forKey: "sync.lastSync")
        return true
    }

    @MainActor
    private func push(channel: String, key: SymmetricKey) async throws {
        let profile = ProfileStore.shared
        let bundle = SyncBundle(
            ts: Self.nowMs(),
            name: profile.name,
            prefsEditedAt: profile.prefsEditedAt,
            diets: Array(profile.diets),
            allergens: Array(profile.allergens),
            history: HistoryStore.shared.records.map {
                SyncScan(
                    barcode: $0.barcode, name: $0.name,
                    brand: $0.brand, imageUrl: $0.imageUrl,
                    score: $0.score, band: $0.band,
                    hasEuBanned: $0.hasEuBanned,
                    scannedAt: Self.ms($0.scannedAt))
            })
        let blob = try encrypt(JSONEncoder().encode(bundle), key: key)
        var request = URLRequest(
            url: ProductRepository.serverBase
                .appendingPathComponent("api/v2/sync/\(channel)/\(deviceId)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SyncUpload(blob: blob, ts: bundle.ts))
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    @MainActor
    private func pull(channel: String, key: SymmetricKey) async throws {
        let url = URL(
            string: "api/v2/sync/\(channel)?exclude=\(deviceId)",
            relativeTo: ProductRepository.serverBase)!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        for peer in try JSONDecoder().decode(SyncPeers.self, from: data).peers {
            guard let plain = try? decrypt(peer.blob, key: key),
                  let bundle = try? JSONDecoder().decode(SyncBundle.self, from: plain)
            else { continue }
            merge(bundle)
        }
    }

    @MainActor
    private func merge(_ remote: SyncBundle) {
        let history = HistoryStore.shared
        let local = Dictionary(
            history.records.map { ($0.barcode, Self.ms($0.scannedAt)) },
            uniquingKeysWith: max)
        for scan in remote.history {
            if let existing = local[scan.barcode], scan.scannedAt <= existing { continue }
            history.upsert(ScanRecord(
                barcode: scan.barcode, name: scan.name,
                brand: scan.brand, imageUrl: scan.imageUrl,
                score: scan.score, band: scan.band,
                hasEuBanned: scan.hasEuBanned,
                scannedAt: Date(timeIntervalSince1970: Double(scan.scannedAt) / 1000)))
        }
        // Preferences follow the device where they were last EDITED, not
        // the device that synced last. The old additive union resurrected
        // removed diets and let a frequently syncing device clobber a
        // fresh edit made on its partner.
        let profile = ProfileStore.shared
        if remote.prefsEditedAt > profile.prefsEditedAt {
            profile.applySyncedPrefs(
                name: remote.name.isEmpty ? profile.name : remote.name,
                diets: Set(remote.diets),
                allergens: Set(remote.allergens),
                editedAt: remote.prefsEditedAt)
        }
    }

    // AES-256-GCM, key = SHA-256 of the salted code; blob layout is
    // iv(12) || ciphertext || tag(16), base64 — CryptoKit's "combined"
    // format, byte-identical to the Android blob.
    private func encrypt(_ plain: Data, key: SymmetricKey) throws -> String {
        try AES.GCM.seal(plain, using: key).combined!.base64EncodedString()
    }

    private func decrypt(_ blob: String, key: SymmetricKey) throws -> Data {
        guard let raw = Data(base64Encoded: blob), raw.count > 28 else {
            throw URLError(.cannotDecodeContentData)
        }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: raw), using: key)
    }

    private static func sha256(_ text: String) -> Data {
        Data(SHA256.hash(data: Data(text.utf8)))
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func ms(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }
}
