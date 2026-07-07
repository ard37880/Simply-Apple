import Foundation
import UIKit

// MARK: - Risk database loading

enum RiskDatabase {

    static func load(_ resource: String) -> [AdditiveEntry] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([AdditiveEntry].self, from: data)
        else { return [] }
        return entries
    }
}

/// E-number lookup for food and pet food (additives.json).
final class AdditiveRepository {
    static let shared = AdditiveRepository()

    private let byId: [String: Additive]

    private init() {
        var map: [String: Additive] = [:]
        for entry in RiskDatabase.load("additives") {
            map[entry.id] = Additive(entry: entry)
        }
        byId = map
    }

    /// Resolve OFF tags like "en:e150d" / "en:e322i" (variants fall back
    /// to their base code).
    func resolve(_ tags: [String]) -> (rated: [Additive], unrated: [UnratedAdditive]) {
        var rated: [String: Additive] = [:]
        var order: [String] = []
        var unrated: [UnratedAdditive] = []
        for tag in tags {
            let code = tag.split(separator: ":").last.map(String.init)?.lowercased() ?? tag
            let base = code.range(of: "^e\\d+[a-d]?", options: .regularExpression)
                .map { String(code[$0]) }
            if let hit = byId[code] ?? base.flatMap({ byId[$0] }) {
                if rated[hit.id] == nil { order.append(hit.id) }
                rated[hit.id] = hit
            } else {
                unrated.append(UnratedAdditive(eNumber: code.uppercased()))
            }
        }
        return (order.compactMap { rated[$0] }, unrated)
    }
}

/// Text-based ingredient matcher for cosmetics and household products.
final class IngredientRiskRepository {
    static let cosmetics = IngredientRiskRepository(
        resource: "cosmetic_ingredients",
        defaultEvidence: ["SCCS (EU)", "EU CosIng database"],
        bannedWording: "Not permitted in cosmetics (Annex II)"
    )
    static let household = IngredientRiskRepository(
        resource: "household_ingredients",
        defaultEvidence: ["EU CLP/REACH (ECHA)", "EU Detergent Regulation"],
        bannedWording: "Not permitted in EU consumer products"
    )

    private let catalog: [String: Additive]
    private let exact: [String: String]  // normalized name/synonym -> id

    private init(resource: String, defaultEvidence: [String], bannedWording: String) {
        var cat: [String: Additive] = [:]
        var ex: [String: String] = [:]
        for entry in RiskDatabase.load(resource) {
            var additive = Additive(entry: entry)
            if additive.explicitEvidenceSources.isEmpty ||
                additive.explicitRegionStatus.isEmpty {
                additive = Self.enrich(additive,
                                       evidence: defaultEvidence,
                                       bannedWording: bannedWording,
                                       entry: entry)
            }
            cat[entry.id] = additive
            ex[Self.normalize(entry.name)] = entry.id
            for s in entry.synonyms ?? [] { ex[Self.normalize(s)] = entry.id }
        }
        catalog = cat
        exact = ex
    }

    private static func enrich(
        _ a: Additive, evidence: [String], bannedWording: String, entry: AdditiveEntry
    ) -> Additive {
        var patched = entry
        if (entry.evidenceSources ?? []).isEmpty { patched.evidenceSources = evidence }
        if (entry.regionStatus ?? [:]).isEmpty {
            var regions: [String: String] = [:]
            switch a.euStatus {
            case .banned: regions["EU"] = bannedWording
            case .restricted: regions["EU"] = "Restricted — concentration/use limits apply"
            case .approved: regions["EU"] = "Permitted"
            }
            for region in a.notPermittedIn { regions[region] = "Not permitted" }
            patched.regionStatus = regions
        }
        return Additive(entry: patched)
    }

    func match(_ ingredientsText: String?) -> [Additive] {
        guard let text = ingredientsText, !text.isEmpty else { return [] }
        let tokens = text
            .split(whereSeparator: { ",;·•".contains($0) })
            .map { Self.normalize(String($0)) }
            .filter { !$0.isEmpty }

        var matched: [String: Additive] = [:]
        var order: [String] = []
        for token in tokens {
            var hit = exact[token].flatMap { catalog[$0] }
            if hit == nil {
                hit = exact.first { key, _ in
                    key.count >= 5 && token.hasPrefix(key + " ")
                }.flatMap { catalog[$0.value] }
            }
            if hit == nil { hit = familyMatch(token) }
            if let hit, matched[hit.id] == nil {
                matched[hit.id] = hit
                order.append(hit.id)
            }
        }
        return order.compactMap { matched[$0] }
    }

    private func familyMatch(_ token: String) -> Additive? {
        if token.hasSuffix("paraben") { return catalog["paraben-generic"] }
        if token.contains("phthalate") { return catalog["phthalate-generic"] }
        if token.hasPrefix("peg-") || token.contains(" peg-") { return catalog["peg-generic"] }
        if token.hasPrefix("ppg-") { return catalog["ppg-generic"] }
        if token.hasPrefix("polyquaternium") { return catalog["polyquaternium-generic"] }
        if token.contains("siloxane") { return catalog["siloxane-generic"] }
        if token.hasPrefix("benzophenone") { return catalog["benzophenone"] }
        if token.contains("acrylate") { return catalog["acrylates-generic"] }
        if token.contains("ethoxylate") { return catalog["ethoxylate-generic"] }
        return nil
    }

    private static func normalize(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "\\(.*?\\)", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[*.%:]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Text flaggers (same rules as Android)

enum IngredientFlagger {
    static func detect(_ text: String?) -> [FlaggedIngredient] {
        guard let t = text?.lowercased() else { return [] }
        var flags: [FlaggedIngredient] = []
        if t.contains("partially hydrogenated") {
            flags.append(.init(
                name: "Partially hydrogenated oil", risk: .high,
                note: "Artificial trans fat. The EU caps industrial trans fats and the US FDA revoked approval of partially hydrogenated oils; trans fats are strongly linked to heart disease."))
        } else if t.contains("hydrogenated") {
            flags.append(.init(
                name: "Hydrogenated oil", risk: .moderate,
                note: "Industrially hardened fat. Fully hydrogenated oils are trans-fat free but are highly processed and typically raise saturated fat content."))
        }
        if t.contains("interesterified") {
            flags.append(.init(
                name: "Interesterified fat", risk: .moderate,
                note: "Fat restructured industrially to replace trans fats. Long-term health data on interesterified fats is still limited."))
        }
        return flags
    }
}

enum PetIngredientFlagger {
    private static let rules: [(String, FlaggedIngredient)] = [
        ("ethoxyquin", .init(name: "Ethoxyquin", risk: .high,
            note: "Synthetic preservative suspended in EU animal feed since 2017 over genotoxicity data gaps; still appears in US pet food, often via preserved fish meal.")),
        ("xylitol", .init(name: "Xylitol", risk: .high,
            note: "Sweetener that is severely toxic to dogs — even small amounts can cause hypoglycemia and liver failure.")),
        ("onion", .init(name: "Onion", risk: .high,
            note: "Onion in any form is toxic to dogs and cats (oxidative damage to red blood cells).")),
        ("garlic", .init(name: "Garlic", risk: .moderate,
            note: "Garlic is toxic to dogs and cats in larger amounts; small flavoring quantities are debated.")),
        ("propylene glycol", .init(name: "Propylene glycol", risk: .moderate,
            note: "Humectant the US FDA prohibits in cat food (causes feline blood-cell damage); still used in some soft dog foods and treats.")),
        ("menadione", .init(name: "Menadione (vitamin K3)", risk: .moderate,
            note: "Synthetic vitamin K linked to organ effects at high doses; European pet food typically avoids it.")),
        ("bha", .init(name: "BHA", risk: .moderate,
            note: "Synthetic fat preservative; possible carcinogen classification from animal studies.")),
        ("bht", .init(name: "BHT", risk: .moderate,
            note: "Synthetic fat preservative with mixed animal-study findings.")),
        ("corn syrup", .init(name: "Corn syrup", risk: .moderate,
            note: "Added sugar with no nutritional role in pet food; drives palatability and weight gain.")),
        ("animal by-product", .init(name: "Unnamed animal by-products", risk: .limited,
            note: "Catch-all term for unspecified animal parts; quality varies widely. Named sources are more transparent.")),
    ]

    static func detect(_ text: String?) -> [FlaggedIngredient] {
        guard let t = text?.lowercased() else { return [] }
        var seen = Set<String>()
        return rules.compactMap { needle, flag in
            guard t.contains(needle), !seen.contains(flag.name) else { return nil }
            seen.insert(flag.name)
            return flag
        }
    }
}

// MARK: - Offline product cache (raw response JSON, keyed by barcode)

/// On-device cache of successfully looked-up products, one JSON file per
/// barcode. Lets previously scanned products load with no connectivity
/// (e.g. airplane mode). Capped at `maxEntries`; oldest files (by last
/// write) are pruned first.
final class ProductCache {
    static let shared = ProductCache()

    private static let maxEntries = 500
    private let directory: URL

    private init() {
        directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProductCache", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    func store(_ data: Data, barcode: String) {
        guard let url = fileUrl(for: barcode) else { return }
        try? data.write(to: url, options: .atomic)
        prune()
    }

    func load(barcode: String) -> ProductResponse? {
        guard let url = fileUrl(for: barcode),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(ProductResponse.self, from: data)
    }

    /// Barcodes come from the scanner or manual entry; only cache safe names.
    private func fileUrl(for barcode: String) -> URL? {
        guard !barcode.isEmpty,
              barcode.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else { return nil }
        return directory.appendingPathComponent("\(barcode).json")
    }

    private func prune() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ), files.count > Self.maxEntries else { return }

        let dated = files.map { url -> (URL, Date) in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return (url, date)
        }
        for (url, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(files.count - Self.maxEntries) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - API client (Simply server first, Open Food Facts fallback)

final class ProductRepository {
    static let shared = ProductRepository()

    static let serverBase = URL(string: "https://simply.studio86.dev/")!
    static let offBase = URL(string: "https://world.openfoodfacts.org/")!

    enum Lookup {
        case found(Product, ScoreResult)
        case notFound
        case error(String)
    }

    func lookup(barcode: String) async -> Lookup {
        let path = "api/v2/product/\(barcode)"
        var networkUnreachable = false
        var serverError: String?
        for base in [Self.serverBase, Self.offBase] {
            var request = URLRequest(url: base.appendingPathComponent(path))
            request.setValue("Simply-iOS/1.0 (Studio86)", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status) {
                    guard let decoded = try? JSONDecoder().decode(ProductResponse.self, from: data)
                    else { continue }
                    // A decoded not-found (status != 1) is authoritative —
                    // never serve a stale cached copy in that case.
                    if decoded.status == 1, decoded.product != nil {
                        ProductCache.shared.store(data, barcode: barcode)
                    }
                    return found(decoded, barcode: barcode)
                }
                if status == 404, base == Self.offBase {
                    // OFF answers unknown barcodes with 404 — authoritative.
                    return .notFound
                }
                // Upstream trouble (e.g. a 502 error body from the Simply
                // server): try the next base rather than trusting it.
                serverError = "Server error (\(status))"
            } catch is URLError {
                networkUnreachable = true
            } catch {}
        }
        // No connectivity: fall back to the last good copy so previously
        // scanned products still work offline.
        if networkUnreachable, let cached = ProductCache.shared.load(barcode: barcode) {
            return found(cached, barcode: barcode)
        }
        return .error(serverError ?? "Network error")
    }

    private func found(_ response: ProductResponse, barcode: String) -> Lookup {
        guard response.status == 1, let dto = response.product else { return .notFound }

        let product = Self.toDomain(dto, barcode: barcode, sourceDb: response.simply_source)
        let score = ScoreEngine.score(product, diets: ProfileStore.shared.diets)
        // History keeps the standard score so past scans stay stable when
        // preferences change.
        HistoryStore.shared.record(product: product, score: score)
        return .found(product, score)
    }

    // MARK: Alternatives (better-scoring US products, same category)

    struct Alternative: Identifiable {
        var id: String { barcode }
        let barcode: String
        let name: String
        let brand: String?
        let imageUrl: URL?
        let score: Int
        let band: ScoreBand
    }

    func alternatives(for product: Product, currentScore: Int?) async -> [Alternative] {
        guard product.kind == .food, let category = product.categoryTag else { return [] }
        var components = URLComponents(
            url: Self.offBase.appendingPathComponent("api/v2/search"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "categories_tags", value: category),
            .init(name: "countries_tags", value: "en:united-states"),
            .init(name: "fields", value: "code,product_name,brands,quantity,image_front_url,nutriscore_grade,nova_group,additives_tags,labels_tags,categories_tags,ingredients_text,nutriments,serving_size,serving_quantity"),
            .init(name: "page_size", value: "24"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Simply-iOS/1.0 (Studio86)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data)
        else { return [] }

        let diets = ProfileStore.shared.diets
        let floor = max((currentScore ?? 0) + 15, 50)
        var seenNames = Set<String>()
        var results: [Alternative] = []
        for dto in response.products ?? [] {
            guard let code = dto.code, code != product.barcode else { continue }
            let candidate = Self.toDomain(dto, barcode: code, sourceDb: nil)
            let score = ScoreEngine.score(candidate, diets: diets)
            guard let total = score.displayTotal, total >= floor,
                  let band = score.displayBand,
                  seenNames.insert(candidate.name.lowercased()).inserted
            else { continue }
            results.append(Alternative(
                barcode: code, name: candidate.name, brand: candidate.brand,
                imageUrl: candidate.imageUrl, score: total, band: band))
        }
        return Array(results.sorted { $0.score > $1.score }.prefix(6))
    }

    // MARK: Submissions (photos + verified ingredient text)

    func submitPhoto(barcode: String, field: String, image: UIImage) async -> Bool {
        let resized = image.resized(maxDimension: 2048)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return false }

        let boundary = "SimplyBoundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"imagefield\"\r\n\r\n\(field)\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"\(field).jpg\"\r\nContent-Type: image/jpeg\r\n\r\n")
        body.append(jpeg)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(
            url: Self.serverBase.appendingPathComponent("api/v2/product/\(barcode)/photos"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }
        return (200..<300).contains(http.statusCode)
    }

    /// [nutriments] uses OFF per-100g keys ("energy-kcal_100g", …) with
    /// values already converted from per serving.
    func submitFacts(
        barcode: String, ingredientsText: String? = nil, stores: String? = nil,
        storesRegion: String? = nil, nutriments: [String: Double]? = nil,
        servingSize: String? = nil, servingQuantity: Double? = nil
    ) async -> Bool {
        var payload: [String: Any] = [:]
        if let ingredientsText { payload["ingredients_text"] = ingredientsText }
        if let stores { payload["stores"] = stores }
        if let storesRegion { payload["stores_region"] = storesRegion }
        if let nutriments, !nutriments.isEmpty { payload["nutriments"] = nutriments }
        if let servingSize { payload["serving_size"] = servingSize }
        if let servingQuantity { payload["serving_quantity"] = servingQuantity }
        var request = URLRequest(
            url: Self.serverBase.appendingPathComponent("api/v2/product/\(barcode)/facts"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }
        return (200..<300).contains(http.statusCode)
    }

    static func toDomain(_ dto: ProductDTO, barcode: String, sourceDb: String?) -> Product {
        let rated: [Additive]
        let unrated: [UnratedAdditive]
        switch sourceDb {
        case "openbeautyfacts":
            rated = IngredientRiskRepository.cosmetics.match(dto.ingredients_text)
            unrated = []
        case "openproductsfacts":
            rated = IngredientRiskRepository.household.match(dto.ingredients_text)
            unrated = []
        default:
            (rated, unrated) = AdditiveRepository.shared.resolve(dto.additives_tags ?? [])
        }
        let flagged: [FlaggedIngredient]
        switch sourceDb {
        case "openbeautyfacts", "openproductsfacts": flagged = []
        case "openpetfoodfacts": flagged = PetIngredientFlagger.detect(dto.ingredients_text)
        default: flagged = IngredientFlagger.detect(dto.ingredients_text)
        }

        let organicLabels: Set<String> = [
            "en:organic", "en:eu-organic", "en:usda-organic", "en:certified-organic",
        ]
        let grade = dto.nutriscore_grade?.lowercased().first
            .flatMap { ("a"..."e").contains(String($0)) ? $0 : nil }

        return Product(
            barcode: barcode,
            name: dto.product_name?.isEmpty == false ? dto.product_name! : "Unknown product",
            brand: dto.brands?.isEmpty == false ? dto.brands : nil,
            quantity: dto.quantity?.isEmpty == false ? dto.quantity : nil,
            imageUrl: dto.image_front_url.flatMap(URL.init(string:)),
            nutriScoreGrade: grade,
            novaGroup: dto.nova_group,
            additives: rated,
            unratedAdditives: unrated,
            flaggedIngredients: flagged,
            isOrganic: (dto.labels_tags ?? []).contains { organicLabels.contains($0) },
            isBeverage: (dto.categories_tags ?? []).contains("en:beverages"),
            categoryTag: dto.categories_tags?.last,
            allergensTags: dto.allergens_tags ?? [],
            tracesTags: dto.traces_tags ?? [],
            ingredientsAnalysisTags: dto.ingredients_analysis_tags ?? [],
            ingredientsText: dto.ingredients_text?.isEmpty == false ? dto.ingredients_text : nil,
            servingSize: dto.serving_size,
            servingQuantity: dto.serving_quantity.flatMap { $0 > 0 ? $0 : nil },
            stores: StoreNames.normalize(stores: dto.stores, storesTags: dto.stores_tags ?? []),
            nutriments: dto.nutriments.map {
                Nutriments(
                    energyKj: $0.energyKj100g, energyKcal: $0.energyKcal100g,
                    fat: $0.fat100g, saturatedFat: $0.saturatedFat100g,
                    sugars: $0.sugars100g, salt: $0.salt100g, sodium: $0.sodium100g,
                    fiber: $0.fiber100g, proteins: $0.proteins100g,
                    fruitsVegNuts: $0.fruitsVegNuts100g)
            },
            sourceDb: sourceDb
        )
    }
}

// MARK: - Scan history (local JSON file, mirrors Android's Room store)

struct ScanRecord: Codable, Identifiable {
    var id: String { barcode }
    let barcode: String
    let name: String
    let brand: String?
    let imageUrl: String?
    let score: Int          // -1 = not enough data
    let band: String
    let hasEuBanned: Bool
    let scannedAt: Date
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var records: [ScanRecord] = []

    private let fileUrl = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("history.json")

    private init() {
        if let data = try? Data(contentsOf: fileUrl),
           let saved = try? JSONDecoder().decode([ScanRecord].self, from: data) {
            records = saved
        }
    }

    func record(product: Product, score: ScoreResult) {
        DispatchQueue.main.async {
            self.records.removeAll { $0.barcode == product.barcode }
            self.records.insert(ScanRecord(
                barcode: product.barcode,
                name: product.name,
                brand: product.brand,
                imageUrl: product.imageUrl?.absoluteString,
                score: score.total ?? -1,
                band: score.band?.rawValue ?? "UNKNOWN",
                hasEuBanned: !score.euBanned.isEmpty,
                scannedAt: Date()
            ), at: 0)
            self.persist()
        }
    }

    func delete(barcode: String) {
        records.removeAll { $0.barcode == barcode }
        persist()
    }

    func clear() {
        records = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileUrl)
        }
    }
}
