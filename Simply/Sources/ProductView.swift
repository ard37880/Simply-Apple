import SwiftUI

// MARK: - Shared colors (same palette as Android)

extension Color {
    static let riskNone = Color(red: 0x1B / 255, green: 0x8E / 255, blue: 0x3E / 255)
    static let riskLimited = Color(red: 0xE8 / 255, green: 0xB8 / 255, blue: 0x00 / 255)
    static let riskModerate = Color(red: 0xF2 / 255, green: 0xA9 / 255, blue: 0x3B / 255)
    static let riskHigh = Color(red: 0xE6 / 255, green: 0x3E / 255, blue: 0x32 / 255)
    static let scoreGood = Color(red: 0x7C / 255, green: 0xB9 / 255, blue: 0x2C / 255)
    static let simplyYellow = Color(red: 0xFD / 255, green: 0xE8 / 255, blue: 0x98 / 255)
}

extension AdditiveRisk {
    /// Strict three-color system: green / yellow / red
    var color: Color {
        switch self {
        case .none: return .riskNone
        case .limited, .moderate: return .riskLimited
        case .high: return .riskHigh
        }
    }
}

extension ScoreBand {
    var color: Color {
        switch self {
        case .excellent: return .riskNone
        case .good: return .scoreGood
        case .poor: return .riskModerate
        case .bad: return .riskHigh
        }
    }
}

// MARK: - Product screen

struct ProductView: View {
    let barcode: String
    let onProduct: (String) -> Void

    @EnvironmentObject var profile: ProfileStore
    @State private var state: LoadState = .loading
    @State private var perServing = true
    @State private var alternatives: [ProductRepository.Alternative] = []
    @State private var showSubmit = false

    enum LoadState {
        case loading
        case loaded(Product, ScoreResult)
        case notFound
        case error(String)
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
            case .notFound:
                VStack(spacing: 12) {
                    Text("Product not found")
                        .font(.headline)
                    Text("Barcode \(barcode) isn't in the database yet — you can be the first to add it.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Add product photos") { showSubmit = true }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            case .error(let message):
                VStack(spacing: 12) {
                    Text(message)
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            case .loaded(let product, let score):
                detail(product, score)
            }
        }
        .navigationTitle("Product")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSubmit) { SubmitView(barcode: barcode) }
        .task { await load() }
    }

    private func load() async {
        state = .loading
        switch await ProductRepository.shared.lookup(barcode: barcode) {
        case .found(let product, let score):
            perServing = product.servingQuantity != nil
            state = .loaded(product, score)
            alternatives = await ProductRepository.shared
                .alternatives(for: product, currentScore: score.total)
        case .notFound: state = .notFound
        case .error(let message): state = .error(message)
        }
    }

    // MARK: Sections

    private func detail(_ product: Product, _ score: ScoreResult) -> some View {
        let hits = PreferenceChecker.check(product, profile: profile)
        let servingFactor = (perServing ? product.servingQuantity : nil).map { $0 / 100 } ?? 1
        let metrics = Metric.build(product)
        let negatives = metrics.filter { !$0.higherIsBetter && $0.verdict != .good }
        let positives = metrics.filter { $0.higherIsBetter || $0.verdict == .good }
        let risky = product.additives.contains { $0.effectiveRisk >= .moderate }

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(product, score)

                if !hits.isEmpty { preferenceBanner(hits) }
                if score.total == nil || score.isPartial { missingDataCard(score) }
                if !score.euBanned.isEmpty { bannedBanner(score.euBanned) }

                if product.servingQuantity != nil, !score.ingredientBased {
                    Toggle(isOn: $perServing) {
                        Text(perServing
                            ? "per serving (\(product.servingSize ?? "?"))"
                            : "per 100 g")
                            .font(.callout)
                    }
                    .toggleStyle(.button)
                }

                if !negatives.isEmpty || !product.flaggedIngredients.isEmpty ||
                    (score.additivesKnown && risky) {
                    sectionHeading("Negatives")
                    ForEach(product.flaggedIngredients) { FlaggedRow(flag: $0) }
                    if score.additivesKnown && risky {
                        AdditiveSummaryRow(product: product, score: score)
                    }
                    ForEach(negatives) { MetricRow(metric: $0, factor: servingFactor) }
                }

                if !positives.isEmpty || (score.additivesKnown && !risky) || product.isOrganic {
                    sectionHeading("Positives")
                    if score.additivesKnown && !risky {
                        AdditiveSummaryRow(product: product, score: score)
                    }
                    if product.isOrganic {
                        Label("Certified organic product", systemImage: "leaf.fill")
                            .foregroundStyle(Color.riskNone)
                    }
                    ForEach(positives) { MetricRow(metric: $0, factor: servingFactor) }
                }

                if !alternatives.isEmpty {
                    sectionHeading("Better options in this category")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(alternatives) { alternative in
                                AlternativeCard(alternative: alternative) {
                                    onProduct(alternative.barcode)
                                }
                            }
                        }
                    }
                }

                breakdown(score)
                additivesSection(product, score)

                if let ingredients = product.ingredientsText {
                    sectionHeading("Ingredients")
                    Text(ingredients)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Wrong or missing data? Improve this product") {
                    showSubmit = true
                }
                .font(.subheadline)
                .padding(.top, 4)

                Text(footerText(score.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            }
            .padding(.horizontal)
        }
    }

    private func header(_ product: Product, _ score: ScoreResult) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AsyncImage(url: product.imageUrl) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12).fill(.quaternary)
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(product.name).font(.headline)
                if let brand = product.brand {
                    Text(brand).font(.subheadline).foregroundStyle(.secondary)
                }
                if let quantity = product.quantity {
                    Text(quantity).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScoreRing(score: score)
        }
        .padding(.top, 8)
    }

    private func preferenceBanner(_ hits: [PreferenceHit]) -> some View {
        let worst = hits.map(\.severity.rawValue).min() ?? 2
        let color: Color = worst == 0 ? .riskHigh : .riskModerate
        return bannerCard(color: color, icon: "exclamationmark.triangle.fill") {
            Text("Against your preferences").bold().foregroundStyle(color)
            ForEach(hits) { Text($0.label).font(.subheadline) }
        }
    }

    private func missingDataCard(_ score: ScoreResult) -> some View {
        bannerCard(color: .secondary, icon: "questionmark.circle") {
            Text(score.total == nil ? "Not enough data to score" : "Partial data").bold()
            Text(score.ingredientBased
                ? "This product's ingredient list is missing from the database, so its safety can't be assessed yet."
                : "Some of this product's data is missing, so the score only reflects what's available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func bannedBanner(_ banned: [Additive]) -> some View {
        bannerCard(color: .riskHigh, icon: "exclamationmark.octagon.fill") {
            Text("Banned in the EU").bold().foregroundStyle(Color.riskHigh)
            Text("Contains \(banned.map(\.displayName).joined(separator: ", ")) — not permitted in European products but legal in the US.")
                .font(.subheadline)
        }
    }

    private func bannerCard<Content: View>(
        color: Color, icon: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4, content: content)
            Spacer(minLength: 0)
        }
        .padding()
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func breakdown(_ score: ScoreResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading(score.ingredientBased ? "Ingredient safety" : "Score breakdown")
            if score.ingredientBased {
                breakdownRow("Worst ingredient risk", score.worstRisk?.label ?? "None found")
                breakdownRow("EU-banned ingredients", "\(score.euBanned.count)")
                breakdownRow("EU-restricted ingredients", "\(score.euRestricted.count)")
            } else {
                breakdownRow("Nutrition (Simply model)",
                             score.nutritionKnown ? "\(score.nutritionPoints) / 60" : "no data")
                breakdownRow("Additives",
                             score.additivesKnown ? "\(score.additivePoints) / 30" : "no data")
                breakdownRow("Organic", "\(score.organicPoints) / 10")
            }
            if score.cappedByBanned {
                Text("Score capped because an EU-banned ingredient is present.")
                    .font(.caption).foregroundStyle(Color.riskHigh)
            }
        }
    }

    private func breakdownRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.bold())
        }
    }

    private func additivesSection(_ product: Product, _ score: ScoreResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeading(score.ingredientBased && score.kind != .petFood
                ? "Ingredients of note (\(product.additives.count))"
                : "Additives (\(product.additives.count + product.unratedAdditives.count))")
            if product.additives.isEmpty && product.unratedAdditives.isEmpty {
                Text(score.additivesKnown
                    ? "No additives detected — a good sign."
                    : "No ingredient information for this product yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(product.additives.sorted { $0.effectiveRisk > $1.effectiveRisk }) {
                AdditiveRow(additive: $0)
            }
            ForEach(product.unratedAdditives) { unrated in
                Label("\(unrated.eNumber) — not yet rated", systemImage: "circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionHeading(_ text: String) -> some View {
        Text(text)
            .font(.title3.bold())
            .padding(.top, 12)
    }

    private func footerText(_ kind: ProductKind) -> String {
        switch kind {
        case .cosmetic:
            return "Ratings reflect the EU Cosmetics Regulation and SCCS safety assessments. Product data from the Open Beauty Facts community (ODbL)."
        case .petFood:
            return "Ratings reflect EU feed-additive rules and documented pet toxicity. Product data from the Open Pet Food Facts community (ODbL)."
        case .household:
            return "Ratings reflect EU CLP/REACH classifications and the Detergent Regulation. Product data from the Open Products Facts community (ODbL)."
        case .food:
            return "Scores reflect EU/EFSA safety assessments and the Simply nutrition model. Product data from the Open Food Facts community (ODbL)."
        }
    }
}

struct AlternativeCard: View {
    let alternative: ProductRepository.Alternative
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                AsyncImage(url: alternative.imageUrl) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                }
                .frame(width: 130, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(alternative.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let brand = alternative.brand {
                    Text(brand).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Circle().fill(alternative.band.color).frame(width: 10, height: 10)
                    Text("\(alternative.score)/100 · \(alternative.band.rawValue)")
                        .font(.caption)
                }
            }
            .frame(width: 140)
            .padding(10)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Score ring

struct ScoreRing: View {
    let score: ScoreResult

    var body: some View {
        let color = score.band?.color ?? .gray
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 8)
                if let total = score.total {
                    Circle()
                        .trim(from: 0, to: CGFloat(total) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(score.total.map(String.init) ?? "?")
                    .font(.title3.bold())
                    .foregroundStyle(color)
            }
            .frame(width: 68, height: 68)
            Text(score.displayLabel)
                .font(.caption.bold())
                .foregroundStyle(color)
        }
    }
}

// MARK: - Nutrient metrics (thresholds identical to Android)

struct Metric: Identifiable {
    var id: String { label }
    let label: String
    let valuePer100g: Double
    let unit: String
    let cutoffs: [Double]
    let gaugeMax: Double
    let verdict: Verdict
    let comment: String
    let higherIsBetter: Bool

    enum Verdict { case good, moderate, bad
        var color: Color {
            switch self {
            case .good: return .riskNone
            case .moderate: return .riskModerate
            case .bad: return .riskHigh
            }
        }
    }

    static func negative(
        _ label: String, _ value: Double, _ unit: String,
        cutoffs: [Double], comments: [String]
    ) -> Metric {
        let verdict: Verdict = value <= cutoffs[0] ? .good
            : value <= cutoffs[2] ? .moderate : .bad
        let comment = value <= cutoffs[0] ? comments[0]
            : value <= cutoffs[1] ? comments[1]
            : value <= cutoffs[2] ? comments[2] : comments[3]
        return Metric(label: label, valuePer100g: value, unit: unit,
                      cutoffs: cutoffs, gaugeMax: cutoffs[2] * 1.6,
                      verdict: verdict, comment: comment, higherIsBetter: false)
    }

    static func build(_ product: Product) -> [Metric] {
        guard let n = product.nutriments else { return [] }
        var metrics: [Metric] = []
        if let kcal = n.energyKcal {
            metrics.append(.negative("Calories", kcal, "Cal",
                cutoffs: [160, 330, 500],
                comments: ["Low calories", "Moderately caloric", "Quite caloric", "Very caloric"]))
        }
        if let sugars = n.sugars {
            metrics.append(.negative("Sugar", sugars, "g",
                cutoffs: [5, 13.5, 22.5],
                comments: ["Low sugar", "Moderate sugar", "Quite sweet", "Very sweet"]))
        }
        if let satFat = n.saturatedFat {
            metrics.append(.negative("Saturated fat", satFat, "g",
                cutoffs: [1.5, 3.25, 5],
                comments: ["Low saturated fat", "Moderate saturated fat",
                           "Quite high in saturated fat", "Very high in saturated fat"]))
        }
        if let sodiumMg = (n.sodium ?? n.salt.map { $0 / 2.5 }).map({ $0 * 1000 }) {
            metrics.append(.negative("Sodium", sodiumMg, "mg",
                cutoffs: [120, 360, 600],
                comments: ["Low sodium", "Moderate sodium", "Quite salty", "Very salty"]))
        }
        if let protein = n.proteins {
            metrics.append(Metric(label: "Protein", valuePer100g: protein, unit: "g",
                cutoffs: [8], gaugeMax: 16, verdict: .good,
                comment: protein >= 8 ? "Rich in protein" : "Contains protein",
                higherIsBetter: true))
        }
        if let fiber = n.fiber {
            metrics.append(Metric(label: "Fiber", valuePer100g: fiber, unit: "g",
                cutoffs: [3.5], gaugeMax: 7, verdict: .good,
                comment: fiber >= 3.5 ? "Rich in fiber" : "Contains fiber",
                higherIsBetter: true))
        }
        return metrics
    }
}

struct MetricRow: View {
    let metric: Metric
    let factor: Double
    @State private var expanded = false

    var body: some View {
        let value = metric.valuePer100g * factor
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Circle().fill(metric.verdict.color).frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(metric.label).font(.body.weight(.medium))
                        Text(metric.comment).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(format(value) + (metric.unit == "Cal" ? "" : " ") + metric.unit)
                        .font(.body.weight(.semibold))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                GaugeBar(
                    value: value,
                    boundaries: [0] + metric.cutoffs.map { $0 * factor } + [metric.gaugeMax * factor],
                    colors: metric.higherIsBetter
                        ? [.scoreGood, .riskNone]
                        : [.riskNone, .riskLimited, .riskModerate, .riskHigh]
                )
            }
            Divider()
        }
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Segmented color gauge with a theme-aware position marker.
struct GaugeBar: View {
    let value: Double
    let boundaries: [Double]
    let colors: [Color]

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let segments = colors.count
                let gap: CGFloat = 3
                let segWidth = (geo.size.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
                ZStack(alignment: .topLeading) {
                    HStack(spacing: gap) {
                        ForEach(0..<segments, id: \.self) { index in
                            Capsule().fill(colors[index]).frame(height: 6)
                        }
                    }
                    .padding(.top, 14)

                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.primary)
                        .offset(x: markerX(width: geo.size.width) - 5)
                }
            }
            .frame(height: 24)

            HStack {
                ForEach(boundaries.indices, id: \.self) { index in
                    Text(format(boundaries[index]))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity,
                               alignment: index == 0 ? .leading
                                   : index == boundaries.count - 1 ? .trailing : .center)
                }
            }
        }
    }

    private func markerX(width: CGFloat) -> CGFloat {
        let segments = colors.count
        let clamped = min(max(value, 0), boundaries.last ?? 1)
        var index = 0
        while index < segments - 1 && clamped > boundaries[index + 1] { index += 1 }
        let lo = boundaries[index], hi = boundaries[index + 1]
        let within = hi > lo ? (clamped - lo) / (hi - lo) : 0
        return width * CGFloat((Double(index) + within) / Double(segments))
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

// MARK: - Additive rows

struct AdditiveSummaryRow: View {
    let product: Product
    let score: ScoreResult
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Circle().fill((score.worstRisk ?? .none).color)
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Additives").font(.body.weight(.medium))
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(product.additives.count + product.unratedAdditives.count)")
                        .font(.body.weight(.semibold))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(riskCounts, id: \.0.rawValue) { risk, count in
                    HStack(spacing: 8) {
                        Text("\(count)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(risk.color, in: Circle())
                        Text(risk.label).font(.subheadline)
                    }
                }
            }
            Divider()
        }
    }

    private var subtitle: String {
        let worst = score.worstRisk
        if product.additives.isEmpty && product.unratedAdditives.isEmpty { return "No additives" }
        if worst == nil || worst! <= .limited { return "No concerning additives" }
        return worst == .moderate ? "Contains additives to watch" : "Contains high-risk additives"
    }

    private var riskCounts: [(AdditiveRisk, Int)] {
        [AdditiveRisk.high, .moderate, .limited, .none].compactMap { risk in
            let count = product.additives.filter { $0.effectiveRisk == risk }.count
            return count > 0 ? (risk, count) : nil
        }
    }
}

struct AdditiveRow: View {
    let additive: Additive
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(additive.risk.color)
                        .frame(width: 12, height: 12)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(additive.eNumber.isEmpty
                            ? additive.displayName
                            : "\(additive.eNumber) — \(additive.displayName)")
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(additive.risk.label)
                                .font(.caption)
                                .foregroundStyle(additive.risk.color)
                            if additive.euStatus == .banned {
                                chip("EU: banned", .riskHigh)
                            } else if additive.euStatus == .restricted {
                                chip("EU: restricted", .riskModerate)
                            }
                        }
                        if !expanded {
                            Text(additive.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !additive.notPermittedIn.isEmpty {
                Text("Also not permitted in: \(additive.notPermittedIn.joined(separator: ", "))")
                    .font(.caption.bold())
                    .foregroundStyle(Color.riskModerate)
                    .padding(.leading, 22)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    AdditiveRiskGauge(risk: additive.effectiveRisk)
                    Text(additive.note).font(.caption).foregroundStyle(.secondary)
                    regulatory("Warning category", additive.warningCategory.capitalized)
                    regulatory("Country/region status",
                               additive.regionStatus.map { "\($0.0): \($0.1)" }
                                   .joined(separator: "\n"))
                    regulatory("Max permitted level", additive.maxLevelDisplay)
                    regulatory("Evidence source", additive.evidenceSources.joined(separator: ", "))
                }
                .padding(.leading, 22)
            }
        }
        .padding(.vertical, 4)
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private func regulatory(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(label):").font(.caption2.bold()).foregroundStyle(.secondary)
            Text(value).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct FlaggedRow: View {
    let flag: FlaggedIngredient
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Circle().fill(flag.risk.color).frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(flag.name).font(.body.weight(.medium))
                        Text(flag.risk.label).font(.caption).foregroundStyle(flag.risk.color)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    AdditiveRiskGauge(risk: flag.risk)
                    Text(flag.note).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.leading, 24)
            }
            Divider()
        }
    }
}

/// Three-segment risk-scale gauge (green / yellow / red) with marker.
struct AdditiveRiskGauge: View {
    let risk: AdditiveRisk

    var body: some View {
        let fraction: Double = {
            switch risk {
            case .none: return 1.0 / 6
            case .limited: return 0.42
            case .moderate: return 0.58
            case .high: return 5.0 / 6
            }
        }()
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 3) {
                        Capsule().fill(Color.riskNone).frame(height: 6)
                        Capsule().fill(Color.riskLimited).frame(height: 6)
                        Capsule().fill(Color.riskHigh).frame(height: 6)
                    }
                    .padding(.top, 14)
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.primary)
                        .offset(x: geo.size.width * fraction - 5)
                }
            }
            .frame(height: 24)
            HStack {
                Text("No known risk").frame(maxWidth: .infinity)
                Text("Caution").frame(maxWidth: .infinity)
                Text("High risk").frame(maxWidth: .infinity)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
