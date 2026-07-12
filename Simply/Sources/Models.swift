import Foundation

// MARK: - Risk model (mirrors the Android app)

enum AdditiveRisk: Int, Comparable {
    case none = 0, limited, moderate, high

    static func < (lhs: AdditiveRisk, rhs: AdditiveRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .none: return "No known risk"
        case .limited: return "Limited risk"
        case .moderate: return "Moderate risk"
        case .high: return "High risk"
        }
    }
}

enum EuStatus { case approved, restricted, banned }

enum ProductKind { case food, cosmetic, petFood, household }

/// One entry from the risk databases (additives.json, cosmetic_ingredients.json,
/// household_ingredients.json) — the same files the Android app ships.
struct AdditiveEntry: Decodable {
    let id: String
    let eNumber: String
    let name: String
    var usName: String?
    let risk: String
    let euStatus: String
    let note: String
    var notPermittedIn: [String]?
    var maxPermittedLevel: String?
    var warningCategory: String?
    var evidenceSources: [String]?
    var regionStatus: [String: String]?
    var synonyms: [String]?
    /// Acceptable daily intake (EFSA/JECFA), mg per kg body weight per day.
    /// Absent when no ADI is established or when the ADI was withdrawn.
    var adiMgPerKg: Double?
    /// Documented environmental harm (EU CLP aquatic toxicity, poor
    /// biodegradability, eutrophication); flags the household Environment card.
    var envNote: String?
}

struct Additive: Identifiable {
    let id: String
    let eNumber: String
    let name: String
    let usName: String?
    let risk: AdditiveRisk
    let euStatus: EuStatus
    let note: String
    let notPermittedIn: [String]
    let maxPermittedLevel: String?
    let explicitWarningCategory: String?
    let explicitEvidenceSources: [String]
    let explicitRegionStatus: [String: String]
    /// Acceptable daily intake, mg per kg body weight per day, when established.
    let adiMgPerKg: Double?
    /// Documented environmental harm; shown on the household Environment card.
    let envNote: String?

    var displayName: String {
        usName.map { "\(name) (\($0))" } ?? name
    }

    /// EU-approved but prohibited by a strict positive-list jurisdiction
    /// is treated as at least moderate risk (same rule as Android).
    var effectiveRisk: AdditiveRisk {
        if euStatus == .approved && !notPermittedIn.isEmpty {
            return max(risk, .moderate)
        }
        return risk
    }

    var warningCategory: String {
        if let explicit = explicitWarningCategory { return explicit }
        switch euStatus {
        case .banned: return "banned"
        case .restricted: return "restricted"
        case .approved: return "permitted"
        }
    }

    /// Japan/Canada verdicts come from the database's per-entry
    /// regionStatus (researched against Japan's positive lists and Health
    /// Canada's permitted lists); the EU line stays derived from euStatus
    /// so the two can never disagree. The "not verified" fallback only
    /// fires for an entry the database hasn't covered yet.
    var regionStatus: [(String, String)] {
        var rows: [(String, String)] = []
        switch euStatus {
        case .banned: rows.append(("EU", "Not permitted in food"))
        case .restricted: rows.append(("EU", "Restricted (permitted only for specific uses)"))
        case .approved: rows.append(("EU", "Permitted"))
        }
        rows.append(("Japan", explicitRegionStatus["Japan"]
            ?? (notPermittedIn.contains("Japan")
                ? "Not permitted (not on the positive list)"
                : "Not yet individually verified")))
        rows.append(("Canada", explicitRegionStatus["Canada"]
            ?? (notPermittedIn.contains("Canada")
                ? "Not permitted (not on Health Canada's lists)"
                : "Not yet individually verified")))
        for (region, status) in explicitRegionStatus.sorted(by: { $0.key < $1.key })
        where !rows.contains(where: { $0.0 == region }) {
            rows.append((region, status))
        }
        for region in notPermittedIn
        where !rows.contains(where: { $0.0 == region }) {
            rows.append((region, "Not permitted in food"))
        }
        return rows
    }

    var maxLevelDisplay: String {
        if let level = maxPermittedLevel { return level }
        return euStatus == .banned
            ? "None (not permitted in the EU)"
            : "Varies by food category (EU Annex II); often quantum satis"
    }

    var evidenceSources: [String] {
        if !explicitEvidenceSources.isEmpty { return explicitEvidenceSources }
        var sources = ["EFSA", "EU Food Additives Database"]
        if notPermittedIn.contains("Canada") { sources.append("Health Canada") }
        if notPermittedIn.contains("Japan") { sources.append("Japan MHLW/CAA") }
        if notPermittedIn.contains("Singapore") { sources.append("Singapore SFA") }
        if notPermittedIn.contains("United States") { sources.append("US FDA") }
        return sources
    }

    init(entry: AdditiveEntry) {
        id = entry.id
        eNumber = entry.eNumber
        name = entry.name
        usName = entry.usName
        switch entry.risk.lowercased() {
        case "high": risk = .high
        case "moderate": risk = .moderate
        case "limited": risk = .limited
        default: risk = .none
        }
        switch entry.euStatus.lowercased() {
        case "banned": euStatus = .banned
        case "restricted": euStatus = .restricted
        default: euStatus = .approved
        }
        note = entry.note
        notPermittedIn = entry.notPermittedIn ?? []
        maxPermittedLevel = entry.maxPermittedLevel
        explicitWarningCategory = entry.warningCategory
        explicitEvidenceSources = entry.evidenceSources ?? []
        explicitRegionStatus = entry.regionStatus ?? [:]
        adiMgPerKg = entry.adiMgPerKg
        envNote = entry.envNote
    }
}

struct FlaggedIngredient: Identifiable {
    var id: String { name }
    let name: String
    let risk: AdditiveRisk
    let note: String
}

struct UnratedAdditive: Identifiable {
    var id: String { eNumber }
    let eNumber: String
}

// MARK: - Product

struct Nutriments {
    var energyKj, energyKcal, fat, saturatedFat, sugars,
        salt, sodium, fiber, proteins, fruitsVegNuts: Double?
    /// Every per-100g nutriment the record carries, by OFF key.
    var all: [String: Double] = [:]
}

struct Product {
    let barcode: String
    let name: String
    let brand: String?
    let quantity: String?
    let imageUrl: URL?
    let nutriScoreGrade: Character?
    let novaGroup: Int?
    let additives: [Additive]
    let unratedAdditives: [UnratedAdditive]
    let flaggedIngredients: [FlaggedIngredient]
    let isOrganic: Bool
    let isBeverage: Bool
    let categoryTag: String?
    let allergensTags: [String]
    let tracesTags: [String]
    let ingredientsAnalysisTags: [String]
    let ingredientsText: String?
    let servingSize: String?
    let servingQuantity: Double?
    let stores: [String]           // chains carrying this product
    let nutriments: Nutriments?
    let sourceDb: String?
    /// Free-text label nutrients with no OFF key, from our overrides.
    var nutritionOther: String? = nil

    var kind: ProductKind {
        switch sourceDb {
        case "openbeautyfacts": return .cosmetic
        case "openpetfoodfacts": return .petFood
        case "openproductsfacts": return .household
        default: return .food
        }
    }

    var hasAdditiveData: Bool {
        !additives.isEmpty || !unratedAdditives.isEmpty ||
            !(ingredientsText ?? "").isEmpty
    }
}

// MARK: - API DTOs (Open Food Facts shape, served by the Simply Pure server)

struct ProductResponse: Decodable {
    var status: Int?
    var product: ProductDTO?
    var simply_source: String?
}

struct ProductDTO: Decodable {
    var code: String?
    var product_name: String?
    var brands: String?
    var quantity: String?
    var image_front_url: String?
    var nutriscore_grade: String?
    var nova_group: Int?
    var additives_tags: [String]?
    var labels_tags: [String]?
    var categories_tags: [String]?
    var allergens_tags: [String]?
    var traces_tags: [String]?
    var ingredients_analysis_tags: [String]?
    var ingredients_text: String?
    var serving_size: String?
    var serving_quantity: Double?
    var stores: String?
    var stores_tags: [String]?
    var nutriments: NutrimentsDTO?
    // Admin-approved free-text nutrients with no OFF key — served from
    // our overrides only.
    var nutrition_other: String?
}

/// Normalizes the free-text Open Food Facts "stores" field (comma-separated
/// chain names, typed by the community) into clean display names: trimmed,
/// known chains in their canonical casing, duplicates removed. Falls back
/// to "stores_tags" slugs when the free-text field is empty.
enum StoreNames {

    private static let known: [String: String] = [
        "aldi": "Aldi",
        "albertsons": "Albertsons",
        "amazon": "Amazon",
        "costco": "Costco",
        "cvs": "CVS",
        "dollar general": "Dollar General",
        "dollar tree": "Dollar Tree",
        "food lion": "Food Lion",
        "fred meyer": "Fred Meyer",
        "giant": "Giant",
        "giant eagle": "Giant Eagle",
        "h e b": "H-E-B",
        "h-e-b": "H-E-B",
        "harris teeter": "Harris Teeter",
        "heb": "H-E-B",
        "hy vee": "Hy-Vee",
        "hy-vee": "Hy-Vee",
        "hyvee": "Hy-Vee",
        "jewel osco": "Jewel-Osco",
        "jewel-osco": "Jewel-Osco",
        "king soopers": "King Soopers",
        "kroger": "Kroger",
        "lidl": "Lidl",
        "meijer": "Meijer",
        "publix": "Publix",
        "ralphs": "Ralphs",
        "safeway": "Safeway",
        "sam s club": "Sam's Club",
        "sam's club": "Sam's Club",
        "sams club": "Sam's Club",
        "7 eleven": "7-Eleven",
        "7-eleven": "7-Eleven",
        "shop rite": "ShopRite",
        "shoprite": "ShopRite",
        "sprouts": "Sprouts",
        "sprouts farmers market": "Sprouts",
        "stater bros": "Stater Bros",
        "stater bros.": "Stater Bros",
        "stater brothers": "Stater Bros",
        "stop & shop": "Stop & Shop",
        "stop and shop": "Stop & Shop",
        "target": "Target",
        "trader joe s": "Trader Joe's",
        "trader joe's": "Trader Joe's",
        "trader joes": "Trader Joe's",
        "vons": "Vons",
        "wal-mart": "Walmart",
        "walgreens": "Walgreens",
        "walmart": "Walmart",
        "wegmans": "Wegmans",
        "whole foods": "Whole Foods",
        "whole foods market": "Whole Foods",
        "winco": "WinCo Foods",
        "winco foods": "WinCo Foods",
    ]

    /// All 50 states plus DC — chains with a national footprint.
    private static let national: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA",
        "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY",
        "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX",
        "UT", "VT", "VA", "WA", "WV", "WI", "WY",
    ]

    /// Which US states each chain operates in, keyed by canonical display
    /// name. Chains absent from this map have unknown coverage and are
    /// never filtered out.
    private static let coverage: [String: Set<String>] = [
        "Walmart": national,
        "Target": national,
        "Costco": national,
        "Sam's Club": national,
        "Whole Foods": national,
        "Trader Joe's": national,
        "7-Eleven": national,
        "Aldi": [
            "AL", "AR", "AZ", "CA", "CO", "CT", "DE", "DC", "FL", "GA",
            "IA", "IL", "IN", "KS", "KY", "LA", "MA", "MD", "MI", "MN",
            "MO", "MS", "NC", "ND", "NE", "NH", "NJ", "NY", "OH", "OK",
            "PA", "RI", "SC", "SD", "TN", "TX", "VA", "VT", "WI", "WV",
        ],
        "Vons": ["CA", "NV"],
        "Ralphs": ["CA"],
        "Stater Bros": ["CA"],
        "H-E-B": ["TX"],
        "Publix": ["FL", "GA", "AL", "SC", "NC", "TN", "VA", "KY"],
        "Wegmans": ["NY", "PA", "NJ", "VA", "MD", "MA", "NC", "DE", "DC"],
        "Meijer": ["MI", "OH", "IN", "IL", "KY", "WI"],
        "Hy-Vee": ["IA", "IL", "KS", "MN", "MO", "NE", "SD", "WI"],
        "WinCo Foods": ["WA", "OR", "ID", "NV", "CA", "AZ", "UT", "TX", "OK", "MT"],
        "Safeway": [
            "AK", "AZ", "CA", "CO", "DC", "DE", "HI", "ID", "MD", "MT",
            "NE", "NM", "NV", "OR", "SD", "VA", "WA", "WY",
        ],
        "Albertsons": [
            "AZ", "CA", "CO", "ID", "LA", "MT", "ND", "NV", "NM", "OR",
            "TX", "UT", "WA", "WY",
        ],
        "Kroger": [
            "AK", "AL", "AR", "AZ", "CA", "CO", "DC", "GA", "ID", "IL",
            "IN", "KS", "KY", "LA", "MD", "MI", "MO", "MS", "MT", "NC",
            "NE", "NM", "NV", "OH", "OR", "SC", "TN", "TX", "UT", "VA",
            "WA", "WV", "WI", "WY",
        ],
        "Fred Meyer": ["WA", "OR", "ID", "AK"],
        "King Soopers": ["CO", "WY"],
        "ShopRite": ["NJ", "NY", "PA", "CT", "DE", "MD"],
        "Stop & Shop": ["MA", "CT", "RI", "NY", "NJ"],
        "Food Lion": ["DE", "GA", "KY", "MD", "NC", "PA", "SC", "TN", "VA", "WV"],
        "Harris Teeter": ["NC", "SC", "VA", "MD", "DE", "DC", "GA", "FL"],
        "Giant Eagle": ["PA", "OH", "WV", "IN", "MD"],
        "Sprouts": [
            "AL", "AZ", "CA", "CO", "DE", "FL", "GA", "KS", "LA", "MD",
            "MO", "NC", "NJ", "NM", "NV", "OK", "PA", "SC", "TN", "TX",
            "UT", "VA", "WA",
        ],
        "Jewel-Osco": ["IL", "IN", "IA"],
    ]

    /// Orders chains available in the user's state first and drops chains
    /// whose known footprint excludes that state; chains with unknown
    /// coverage are kept after the in-state ones. Returns the full list
    /// unchanged when no state is known or filtering would empty it.
    static func forState(_ stores: [String], _ stateCode: String?) -> [String] {
        guard let stateCode, !stores.isEmpty else { return stores }
        var inState: [String] = []
        var unknown: [String] = []
        for store in stores {
            guard let states = coverage[store] else {
                unknown.append(store)
                continue
            }
            if states.contains(stateCode) { inState.append(store) }
        }
        let filtered = inState + unknown
        return filtered.isEmpty ? stores : filtered
    }

    static func normalize(stores: String?, storesTags: [String] = []) -> [String] {
        let raw: [String]
        if let stores, !stores.trimmingCharacters(in: .whitespaces).isEmpty {
            raw = stores.split(separator: ",").map(String.init)
        } else {
            raw = storesTags.map { tag in
                (tag.split(separator: ":").last.map(String.init) ?? tag)
                    .replacingOccurrences(of: "-", with: " ")
            }
        }
        var seen = Set<String>()
        var result: [String] = []
        for name in raw {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let display = known[trimmed.lowercased()] ?? titleCaseIfLower(trimmed)
            if seen.insert(display.lowercased()).inserted {
                result.append(display)
            }
        }
        return result
    }

    /// Community data is often all-lowercase; leave mixed case as typed.
    private static func titleCaseIfLower(_ raw: String) -> String {
        guard raw == raw.lowercased() else { return raw }
        return raw.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

/// Decodes the whole nutriments map so every nutrient OFF knows about
/// survives (vitamins, minerals, trans fat, …), not just the scored
/// handful. OFF occasionally serves numbers as strings, so both parse.
struct NutrimentsDTO: Decodable {
    var energyKj100g, energyKcal100g, fat100g, saturatedFat100g,
        sugars100g, salt100g, sodium100g, fiber100g, proteins100g,
        fruitsVegNuts100g: Double?
    /// Every per-100g nutriment the record carries, by OFF key.
    var all: [String: Double] = [:]

    private struct AnyKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        var values: [String: Double] = [:]
        for key in container.allKeys where key.stringValue.hasSuffix("_100g") {
            if let num = try? container.decode(Double.self, forKey: key) {
                values[key.stringValue] = num
            } else if let str = try? container.decode(String.self, forKey: key),
                      let num = Double(str) {
                values[key.stringValue] = num
            }
        }
        all = values
        energyKj100g = values["energy-kj_100g"]
        energyKcal100g = values["energy-kcal_100g"]
        fat100g = values["fat_100g"]
        saturatedFat100g = values["saturated-fat_100g"]
        sugars100g = values["sugars_100g"]
        salt100g = values["salt_100g"]
        sodium100g = values["sodium_100g"]
        fiber100g = values["fiber_100g"]
        proteins100g = values["proteins_100g"]
        fruitsVegNuts100g = values["fruits-vegetables-nuts-estimate-from-ingredients_100g"]
    }
}

struct SearchResponse: Decodable {
    var products: [ProductDTO]?
}
