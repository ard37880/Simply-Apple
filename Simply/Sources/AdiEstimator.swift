import Foundation

/// Estimates how much of an additive one serving delivers, as a share of its
/// acceptable daily intake (ADI) for a 70 kg adult (the EFSA default).
///
/// Additive quantities are not printed on labels, so the concentration is
/// inferred from the ingredient list: US labels group minor ingredients behind
/// a "contains 2% or less of" marker (assume 0.1%, the upper end of typical
/// permitted additive use levels), otherwise the list position is used —
/// ingredients are ordered by weight, so the assumed share starts at 0.1% and
/// halves with each position. The result is an order-of-magnitude signal,
/// never a measurement, and it stays out of the score.
enum AdiEstimator {

    /// Copy shown when an additive is present but no dose could be estimated.
    static let notEstimated = "amount unknown, rated on its risk level alone"

    /// EFSA default adult body weight, kg.
    private static let bodyWeightKg = 70.0

    /// Portion used when the product declares no serving size, grams.
    private static let fallbackPortionG = 100.0

    /// Regulatory maxima for additives are typically 100–2000 mg/kg
    /// (0.01–0.2%); never assume more than 0.1%.
    private static let maxConcentration = 0.001

    /// Assumed share for ingredients behind a "2% or less" marker.
    private static let lowLevelConcentration = 0.001

    private static let lowLevelMarkers = [
        "contains 2% or less of",
        "contains 2 % or less of",
        "contains two percent or less of",
        "contains less than 2% of",
        "contains less than 2 % of",
        "less than 2% of",
        "less than 2 % of",
        "2% or less of",
        "2 % or less of",
    ]

    enum Basis { case serving, per100g }

    struct DoseEstimate {
        let percentOfDailyLimit: Double
        /// True when the label's "2% or less" marker bounded the amount —
        /// a stronger signal than the list-position heuristic.
        let fromLowLevelMarker: Bool
        let basis: Basis

        var displayText: String {
            let amount: String
            if percentOfDailyLimit < 1 {
                amount = "< 1%"
            } else if percentOfDailyLimit > 100 {
                amount = "> 100%"
            } else {
                amount = "≈ \(Int(percentOfDailyLimit.rounded()))%"
            }
            let per = basis == .serving ? "per serving" : "per 100 g"
            let confidence = fromLowLevelMarker ? "estimate" : "rough estimate"
            return "\(amount) of daily limit \(per) (\(confidence))"
        }
    }

    static func estimate(
        additive: Additive,
        ingredientsText: String?,
        servingQuantityG: Double?
    ) -> DoseEstimate? {
        guard let adi = additive.adiMgPerKg else { return nil }
        guard let text = ingredientsText?.lowercased(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        guard let index = matchIndex(in: text, additive: additive) else { return nil }
        let markerIndex = lowLevelMarkers
            .compactMap { text.range(of: $0)?.lowerBound }
            .min()
        let fromMarker = markerIndex.map { index > $0 } ?? false

        let concentration: Double
        if fromMarker {
            concentration = lowLevelConcentration
        } else {
            let rank = text[text.startIndex..<index]
                .filter { $0 == "," || $0 == ";" }.count + 1
            concentration = maxConcentration * pow(0.5, Double(rank - 1))
        }

        let portionG = servingQuantityG.flatMap { $0 > 0 ? $0 : nil }
        let doseMg = concentration * (portionG ?? fallbackPortionG) * 1000.0
        let dailyLimitMg = adi * bodyWeightKg
        return DoseEstimate(
            percentOfDailyLimit: doseMg / dailyLimitMg * 100.0,
            fromLowLevelMarker: fromMarker,
            basis: portionG != nil ? .serving : .per100g
        )
    }

    /// First position where the additive appears in the ingredient text,
    /// matched by name (including slash/parenthesis variants like
    /// "Azorubine (Carmoisine)"), US label name, or E-number.
    private static func matchIndex(in text: String, additive: Additive) -> String.Index? {
        var candidates: [String] = additive.name
            .components(separatedBy: CharacterSet(charactersIn: "/()"))
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { $0.count >= 3 }
        if let usName = additive.usName?
            .trimmingCharacters(in: .whitespaces).lowercased(), usName.count >= 3 {
            candidates.append(usName)
        }
        let eNumber = additive.eNumber
            .trimmingCharacters(in: .whitespaces).lowercased()
        if !eNumber.isEmpty { candidates.append(eNumber) }
        return candidates
            .compactMap { text.range(of: $0)?.lowerBound }
            .min()
    }
}
