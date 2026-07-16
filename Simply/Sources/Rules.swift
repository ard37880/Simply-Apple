import Foundation
import CryptoKit

/// Holds the server-downloaded copies of the risk databases. RiskDatabase
/// reads through `cachedData` (preferring the cache, falling back to the
/// bundled resource), so a server-pushed regulatory update applies without
/// an app release.
final class RulesStore {
    static let shared = RulesStore()

    private let dir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        dir = base.appendingPathComponent("rules", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func cacheURL(_ resource: String) -> URL {
        dir.appendingPathComponent("\(resource).json")
    }

    /// The cached copy's bytes, or nil when nothing has been downloaded.
    func cachedData(_ resource: String) -> Data? {
        try? Data(contentsOf: cacheURL(resource))
    }
}

/// Keeps the on-device risk databases current from the server. On launch it
/// fetches a tiny manifest; when the version differs from what's applied it
/// downloads only the files whose hash changed, verifies each download's
/// SHA-256 against the manifest AND that it still parses, then writes it
/// atomically into the rules cache. Downloaded rules take effect on the
/// next launch. Best-effort throughout: no network, a bad manifest, or a
/// hash mismatch leaves the bundled databases in place, and the applied
/// version only advances once every file verified.
enum RulesUpdater {
    private static let store = RulesStore.shared
    private static let versionKey = "rules.version"

    private struct Manifest: Decodable {
        let version: String
        let files: [RuleFile]
    }
    private struct RuleFile: Decodable {
        let name: String
        let sha256: String
    }

    static func refresh() async {
        guard let manifest = await fetchManifest() else { return }
        if manifest.version == UserDefaults.standard.string(forKey: versionKey) { return }
        var allOK = true
        for file in manifest.files {
            if currentSHA(file.name) == file.sha256 { continue }
            if !(await downloadAndVerify(file.name, expected: file.sha256)) { allOK = false }
        }
        if allOK {
            UserDefaults.standard.set(manifest.version, forKey: versionKey)
        }
    }

    private static func fetchManifest() async -> Manifest? {
        let url = ProductRepository.serverBase.appendingPathComponent("api/v2/rules/manifest")
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return nil }
        return manifest
    }

    /// SHA-256 of the currently effective file (cached copy or bundled).
    private static func currentSHA(_ resource: String) -> String? {
        let data = store.cachedData(resource)
            ?? Bundle.main.url(forResource: resource, withExtension: "json")
                .flatMap { try? Data(contentsOf: $0) }
        guard let data else { return nil }
        return hex(SHA256.hash(data: data))
    }

    private static func downloadAndVerify(_ resource: String, expected: String) async -> Bool {
        let url = ProductRepository.serverBase.appendingPathComponent("api/v2/rules/\(resource)")
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              hex(SHA256.hash(data: data)) == expected,
              (try? JSONSerialization.jsonObject(with: data)) != nil
        else { return false }
        // Atomic write: URL's atomic option writes to a temp file and renames.
        return (try? data.write(to: store.cacheURL(resource), options: .atomic)) != nil
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
