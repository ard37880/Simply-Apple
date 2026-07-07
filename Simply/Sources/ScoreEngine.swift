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
    let euBanned: [Additive]
    let euRestricted: [Additive]
    let cappedByBanned: Bool
    let kind: ProductKind
    /// Diet-reweighted total; nil when the profile has no reweighting diets.
    var personalized: Int? = nil
    /// Ultra-processing axis (NOVA); excluded when the group is unknown.
    var processingKnown: Bool = false
    var processingPoints: Int = 0    // 0..10, meaningful only when known

    var ingredientBased: Bool { kind != .food }

    /// The score to show: personalized when the profile calls for it.
    var displayTotal: Int? { personalized ?? total }
    var displayBand: ScoreBand? { displayTotal.map(ScoreBand.forScore) }

    var displayLabel: String {
        guard displayTotal != nil, let shownBand = displayBand else { return "No data" }
        return (euBanned.count + euRestricted.count) >= 2
            ? "Multiple concerns flagged" : shownBand.rawValue
    }
    var isPartial: Bool {
        total != nil && !ingredientBased && (!nutritionKnown || !additivesKnown)
    }
}

/// Per-component multipliers for the Simply Pure nutrition model, driven by the
/// user's diet preferences. 1.0 everywhere = the standard score. Weights
/// scale deductions and bonuses alike: a 2.0 sugar weight doubles the
/// sugar deduction; a 1.5 protein weight raises the protein bonus.
struct NutritionWeights: Equatable {
    var sugar = 1.0
    var satFat = 1.0
    var sodium = 1.0
    var calories = 1.0
    var fiber = 1.0
    var protein = 1.0
    var sweetener = 1.0

    static let neutral = NutritionWeights()
    var isNeutral: Bool { self == .neutral }

    // Diet-pattern reweighting only — there is deliberately no
    // calorie-minimization or weight-loss preference.
    private static let dietWeights: [String: NutritionWeights] = [
        "keto": NutritionWeights(sugar: 2.0, satFat: 0.5, calories: 0.5),
        "carnivore": NutritionWeights(satFat: 0.5, protein: 1.5),
        "paleo": NutritionWeights(sugar: 1.5, sweetener: 1.5),
        "low_sodium": NutritionWeights(sodium: 2.0),
        "anti_inflammatory": NutritionWeights(sugar: 1.5, sweetener: 1.5),
        "no_artificial_sweeteners": NutritionWeights(sweetener: 2.0),
    ]

    /// Active diets multiply per component, clamped to [0.5, 2.0].
    static func forDiets(_ diets: Set<String>) -> NutritionWeights {
        var w = NutritionWeights.neutral
        for key in diets {
            guard let m = dietWeights[key] else { continue }
            w.sugar *= m.sugar
            w.satFat *= m.satFat
            w.sodium *= m.sodium
            w.calories *= m.calories
            w.fiber *= m.fiber
            w.protein *= m.protein
            w.sweetener *= m.sweetener
        }
        func clamp(_ v: Double) -> Double { min(max(v, 0.5), 2.0) }
        return NutritionWeights(
            sugar: clamp(w.sugar),
            satFat: clamp(w.satFat),
            sodium: clamp(w.sodium),
            calories: clamp(w.calories),
            fiber: clamp(w.fiber),
            protein: clamp(w.protein),
            sweetener: clamp(w.sweetener)
        )
    }
}

/// Nutri-Score (2017 algorithm) fallback when the database has no grade.
enum NutriScore {

    /// The Simply Pure nutrition model (0..60): nutrient thresholds plus an
    /// artificial-sweetener penalty. Ultra-processing is scored separately
    /// as the NOVA axis in ScoreEngine.
    static func simplyPoints(
        _ n: Nutriments,
        sweetener: Bool,
        weights w: NutritionWeights = .neutral
    ) -> Int? {
        guard let sugars = n.sugars, let satFat = n.saturatedFat,
              let sodiumMg = (n.sodium ?? n.salt.map { $0 / 2.5 }).map({ $0 * 1000 })
        else { return nil }
        var pts = 60.0
        pts -= w.sugar * Double(sugars <= 5 ? 0 : sugars <= 13.5 ? 6 : sugars <= 22.5 ? 12 : 18)
        pts -= w.satFat * Double(satFat <= 1.5 ? 0 : satFat <= 3.25 ? 5 : satFat <= 5 ? 10 : 15)
        pts -= w.sodium * Double(sodiumMg <= 120 ? 0 : sodiumMg <= 360 ? 5 : sodiumMg <= 600 ? 10 : 15)
        if let kcal = n.energyKcal { pts -= w.calories * Double(kcal <= 160 ? 0 : kcal <= 330 ? 3 : kcal <= 500 ? 6 : 9) }
        if let fiber = n.fiber { pts += w.fiber * Double(fiber >= 3.5 ? 4 : fiber >= 1.5 ? 2 : 0) }
        if let protein = n.proteins { pts += w.protein * Double(protein >= 8 ? 4 : protein >= 4 ? 2 : 0) }
        if sweetener { pts -= w.sweetener * 6 }
        return min(max(Int(pts.rounded()), 0), 60)
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
/// food = 60 nutrition + 30 additives + 10 processing (NOVA),
/// renormalized over known axes; other verticals score purely on
/// ingredient safety. Organic certification is displayed but earns no
/// points. High-risk caps at 49; anything EU-banned caps at 24.
enum ScoreEngine {

    static let bannedCap = 24
    static let highRiskCap = 49

    // A personalized score may move at most this far from the standard
    // one, so reweighting can shift a band but never invent a verdict.
    static let personalizationSwing = 12

    static func score(_ product: Product, diets: Set<String> = []) -> ScoreResult {
        if product.kind != .food { return scoreByIngredients(product) }

        let sweetenerEs: Set<String> = ["E950","E951","E952","E954","E955","E961","E962","E969"]
        let sweetener = product.additives.contains { sweetenerEs.contains($0.eNumber.uppercased()) }
        let nutritionPts = product.nutriments.flatMap {
            NutriScore.simplyPoints($0, sweetener: sweetener)
        }
        let nutritionKnown = nutritionPts != nil
        let nutritionPoints = nutritionPts ?? 0
        let estimated = false
        let grade: Character? = nil

        // Processing: 0..10 from the product's NOVA group (1 = unprocessed
        // or minimally processed food, 4 = ultra-processed). Its own axis
        // so ultra-processing visibly costs points instead of hiding as a
        // small nutrition deduction; excluded and renormalized when the
        // database has no NOVA group.
        let processingKnown = (1...4).contains(product.novaGroup ?? 0)
        let processingPoints: Int
        switch product.novaGroup {
        case 1: processingPoints = 10
        case 2: processingPoints = 7
        case 3: processingPoints = 4
        default: processingPoints = 0
        }

        let additivesKnown = product.hasAdditiveData
        let worstRisk = (product.additives.map(\.effectiveRisk) +
            product.flaggedIngredients.map(\.risk)).max()
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

        let banned = product.additives.filter { $0.euStatus == .banned }
        let restricted = product.additives.filter { $0.euStatus == .restricted }

        var earned = 0
        var availableMax = 0
        if nutritionKnown { earned += nutritionPoints; availableMax += 60 }
        if additivesKnown { earned += additivePoints; availableMax += 30 }
        if processingKnown { earned += processingPoints; availableMax += 10 }

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

        // Personalization reweights only the nutrition axis, is bounded to
        // ±personalizationSwing of the standard score, and the absolute
        // additive caps still win afterwards.
        var personalized: Int? = nil
        let weights = NutritionWeights.forDiets(diets)
        if !weights.isNeutral, nutritionKnown, let standard = total,
           let pNutrition = product.nutriments.flatMap({
               NutriScore.simplyPoints($0, sweetener: sweetener, weights: weights)
           }) {
            var pEarned = pNutrition
            if additivesKnown { pEarned += additivePoints }
            if processingKnown { pEarned += processingPoints }
            var pTotal = Int((Double(pEarned) * 100.0 / Double(availableMax)).rounded())
            pTotal = min(max(pTotal, standard - personalizationSwing), standard + personalizationSwing)
            if worstRisk == .high { pTotal = min(pTotal, highRiskCap) }
            if !banned.isEmpty { pTotal = min(pTotal, bannedCap) }
            personalized = min(max(pTotal, 0), 100)
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
            euBanned: banned,
            euRestricted: restricted,
            cappedByBanned: cappedByBanned,
            kind: .food,
            personalized: personalized,
            processingKnown: processingKnown,
            processingPoints: processingPoints
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
            euBanned: banned,
            euRestricted: restricted,
            cappedByBanned: cappedByBanned,
            kind: product.kind
        )
    }
}
