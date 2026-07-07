import Foundation

enum ScoreBand: String {
    case excellent = "No concerns", good = "Low concern", poor = "Moderate concern", bad = "High concern"

    static func forScore(_ score: Int) -> ScoreBand {
        switch score {
        case 75...: return .excellent
        case 50...: return .good
        case 25...: return .poor
        default: return .bad
        }
    }
}

struct ScoreResult {
    let total: Int?                // nil = not enough data
    let band: ScoreBand?
    let nutritionKnown: Bool
    let nutritionPoints: Int       // 0..60
    let nutriScoreGrade: Character?
    let nutritionEstimated: Bool
    let additivesKnown: Bool
    let additivePoints: Int        // 0..30
    let worstRisk: AdditiveRisk?
    let organicPoints: Int         // 0 or 10
    let euBanned: [Additive]
    let euRestricted: [Additive]
    let cappedByBanned: Bool
    let kind: ProductKind

    var ingredientBased: Bool { kind != .food }
    var displayLabel: String {
        guard total != nil, let band else { return "No data" }
        return (euBanned.count + euRestricted.count) >= 2
            ? "Multiple concerns flagged" : band.rawValue
    }
    var isPartial: Bool {
        total != nil && !ingredientBased && (!nutritionKnown || !additivesKnown)
    }
}

/// Nutri-Score (2017 algorithm) fallback when the database has no grade.
enum NutriScore {

    /// The Simply nutrition model (0..60): nutrient thresholds plus
    /// ultra-processing (NOVA) and artificial-sweetener penalties.
    static func simplyPoints(_ n: Nutriments, novaGroup: Int?, sweetener: Bool) -> Int? {
        guard let sugars = n.sugars, let satFat = n.saturatedFat,
              let sodiumMg = (n.sodium ?? n.salt.map { $0 / 2.5 }).map({ $0 * 1000 })
        else { return nil }
        var pts = 60
        pts -= sugars <= 5 ? 0 : sugars <= 13.5 ? 6 : sugars <= 22.5 ? 12 : 18
        pts -= satFat <= 1.5 ? 0 : satFat <= 3.25 ? 5 : satFat <= 5 ? 10 : 15
        pts -= sodiumMg <= 120 ? 0 : sodiumMg <= 360 ? 5 : sodiumMg <= 600 ? 10 : 15
        if let kcal = n.energyKcal { pts -= kcal <= 160 ? 0 : kcal <= 330 ? 3 : kcal <= 500 ? 6 : 9 }
        if let fiber = n.fiber { pts += fiber >= 3.5 ? 4 : fiber >= 1.5 ? 2 : 0 }
        if let protein = n.proteins { pts += protein >= 8 ? 4 : protein >= 4 ? 2 : 0 }
        if novaGroup == 4 { pts -= 8 } else if novaGroup == 3 { pts -= 3 }
        if sweetener { pts -= 6 }
        return min(max(pts, 0), 60)
    }

    static func computeGrade(_ n: Nutriments, isBeverage: Bool) -> Character? {
        guard let energyKj = n.energyKj ?? n.energyKcal.map({ $0 * 4.184 }),
              let sugars = n.sugars,
              let satFat = n.saturatedFat,
              let sodiumMg = (n.sodium ?? n.salt.map { $0 / 2.5 }).map({ $0 * 1000 })
        else { return nil }

        let fruitPct = n.fruitsVegNuts ?? 0
        let fruitPoints = fruitPct > 80 ? 5 : fruitPct > 60 ? 2 : fruitPct > 40 ? 1 : 0

        let negative =
            points(energyKj, step: 335, count: 10) +
            points(sugars, step: 4.5, count: 10) +
            points(satFat, step: 1.0, count: 10) +
            points(sodiumMg, step: 90, count: 10)

        let fiberPoints = points(n.fiber ?? 0, cutoffs: [0.9, 1.9, 2.8, 3.7, 4.7])
        let proteinPoints = points(n.proteins ?? 0, cutoffs: [1.6, 3.2, 4.8, 6.4, 8.0])

        let positive = (negative >= 11 && fruitPoints < 5)
            ? fruitPoints + fiberPoints
            : fruitPoints + fiberPoints + proteinPoints

        return grade(negative - positive, isBeverage: isBeverage)
    }

    static func nutritionPoints(for grade: Character) -> Int {
        switch String(grade).lowercased() {
        case "a": return 60
        case "b": return 45
        case "c": return 30
        case "d": return 15
        default: return 0
        }
    }

    private static func grade(_ score: Int, isBeverage: Bool) -> Character {
        if isBeverage {
            switch score {
            case ...1: return "b"
            case ...5: return "c"
            case ...9: return "d"
            default: return "e"
            }
        }
        switch score {
        case ...(-1): return "a"
        case ...2: return "b"
        case ...10: return "c"
        case ...18: return "d"
        default: return "e"
        }
    }

    private static func points(_ value: Double, step: Double, count: Int) -> Int {
        (1...count).filter { value > Double($0) * step }.count
    }

    private static func points(_ value: Double, cutoffs: [Double]) -> Int {
        cutoffs.filter { value > $0 }.count
    }
}

/// Composite score — identical rules to the Android app:
/// food = 60 nutrition + 30 additives + 10 organic, renormalized over
/// known axes; other verticals score purely on ingredient safety.
/// High-risk caps at 49; anything EU-banned caps at 24.
enum ScoreEngine {

    static let bannedCap = 24
    static let highRiskCap = 49

    static func score(_ product: Product) -> ScoreResult {
        if product.kind != .food { return scoreByIngredients(product) }

        let sweetenerEs: Set<String> = ["E950","E951","E952","E954","E955","E961","E962","E969"]
        let sweetener = product.additives.contains { sweetenerEs.contains($0.eNumber.uppercased()) }
        let nutritionPts = product.nutriments.flatMap {
            NutriScore.simplyPoints($0, novaGroup: product.novaGroup, sweetener: sweetener)
        }
        let nutritionKnown = nutritionPts != nil
        let nutritionPoints = nutritionPts ?? 0
        let estimated = false
        let grade: Character? = nil

        let additivesKnown = product.hasAdditiveData
        let worstRisk = product.additives.map(\.effectiveRisk).max()
        var additivePoints: Int
        switch worstRisk {
        case nil, .some(.none): additivePoints = 30
        case .some(.limited): additivePoints = 22
        case .some(.moderate): additivePoints = 10
        case .some(.high): additivePoints = 0
        }
        // Positive-list principle: unidentified additives get no benefit of doubt
        if !product.unratedAdditives.isEmpty {
            additivePoints = min(additivePoints, 22)
        }

        let organicPoints = product.isOrganic ? 10 : 0
        let banned = product.additives.filter { $0.euStatus == .banned }
        let restricted = product.additives.filter { $0.euStatus == .restricted }

        var earned = organicPoints
        var availableMax = 10
        if nutritionKnown { earned += nutritionPoints; availableMax += 60 }
        if additivesKnown { earned += additivePoints; availableMax += 30 }

        var total: Int? = (!nutritionKnown && !additivesKnown)
            ? nil
            : Int((Double(earned) * 100.0 / Double(availableMax)).rounded())

        var cappedByBanned = false
        if var t = total {
            if worstRisk == .high { t = min(t, highRiskCap) }
            if !banned.isEmpty {
                cappedByBanned = t > bannedCap
                t = min(t, bannedCap)
            }
            total = min(max(t, 0), 100)
        }

        return ScoreResult(
            total: total,
            band: total.map(ScoreBand.forScore),
            nutritionKnown: nutritionKnown,
            nutritionPoints: nutritionPoints,
            nutriScoreGrade: grade,
            nutritionEstimated: estimated,
            additivesKnown: additivesKnown,
            additivePoints: additivePoints,
            worstRisk: worstRisk,
            organicPoints: organicPoints,
            euBanned: banned,
            euRestricted: restricted,
            cappedByBanned: cappedByBanned,
            kind: .food
        )
    }

    private static func scoreByIngredients(_ product: Product) -> ScoreResult {
        let known = !(product.ingredientsText ?? "").isEmpty
        let allRisks = product.additives.map(\.effectiveRisk) +
            product.flaggedIngredients.map(\.risk)
        let worstRisk = allRisks.max()
        let banned = product.additives.filter { $0.euStatus == .banned }
        let restricted = product.additives.filter { $0.euStatus == .restricted }

        var total: Int?
        if known {
            switch worstRisk {
            case nil, .some(.none): total = 92
            case .some(.limited): total = 72
            case .some(.moderate): total = 42
            case .some(.high): total = 15
            }
        }
        var cappedByBanned = false
        if var t = total {
            let riskyCount = allRisks.filter { $0 >= .moderate }.count
            if riskyCount > 1 { t -= 4 * (riskyCount - 1) }
            if !banned.isEmpty {
                cappedByBanned = t > bannedCap
                t = min(t, bannedCap)
            }
            total = min(max(t, 0), 100)
        }

        return ScoreResult(
            total: total,
            band: total.map(ScoreBand.forScore),
            nutritionKnown: false,
            nutritionPoints: 0,
            nutriScoreGrade: nil,
            nutritionEstimated: false,
            additivesKnown: known,
            additivePoints: 0,
            worstRisk: worstRisk,
            organicPoints: 0,
            euBanned: banned,
            euRestricted: restricted,
            cappedByBanned: cappedByBanned,
            kind: product.kind
        )
    }
}
