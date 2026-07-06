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

    var regionStatus: [(String, String)] {
        if !explicitRegionStatus.isEmpty {
            return explicitRegionStatus.sorted { $0.key < $1.key }
        }
        var rows: [(String, String)] = []
        switch euStatus {
        case .banned: rows.append(("EU", "Not permitted in food"))
        case .restricted: rows.append(("EU", "Restricted — check permitted use list"))
        case .approved: rows.append(("EU", "Permitted"))
        }
        rows.append(("Japan", notPermittedIn.contains("Japan")
            ? "Not on positive list" : "Check positive list (MHLW/CAA)"))
        rows.append(("Canada", notPermittedIn.contains("Canada")
            ? "Not on permitted list" : "Check permitted use lists (Health Canada)"))
        for region in notPermittedIn where region != "Japan" && region != "Canada" {
            rows.append((region, "Not permitted in food"))
        }
        return rows
    }

    var maxLevelDisplay: String {
        if let level = maxPermittedLevel { return level }
        return euStatus == .banned
            ? "None — not permitted in the EU"
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
    let nutriments: Nutriments?
    let sourceDb: String?

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

// MARK: - API DTOs (Open Food Facts shape, served by the Simply server)

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
    var nutriments: NutrimentsDTO?
}

struct NutrimentsDTO: Decodable {
    var energyKj100g, energyKcal100g, fat100g, saturatedFat100g,
        sugars100g, salt100g, sodium100g, fiber100g, proteins100g,
        fruitsVegNuts100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKj100g = "energy-kj_100g"
        case energyKcal100g = "energy-kcal_100g"
        case fat100g = "fat_100g"
        case saturatedFat100g = "saturated-fat_100g"
        case sugars100g = "sugars_100g"
        case salt100g = "salt_100g"
        case sodium100g = "sodium_100g"
        case fiber100g = "fiber_100g"
        case proteins100g = "proteins_100g"
        case fruitsVegNuts100g = "fruits-vegetables-nuts-estimate-from-ingredients_100g"
    }
}

struct SearchResponse: Decodable {
    var products: [ProductDTO]?
}
