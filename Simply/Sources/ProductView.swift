import SwiftUI

// MARK: - Shared colors (same palette as Android)

extension Color {
    static let riskNone = Color(red: 0x1B / 255, green: 0x8E / 255, blue: 0x3E / 255)
    static let riskLimited = Color(red: 0xE8 / 255, green: 0xB8 / 255, blue: 0x00 / 255)
    static let riskModerate = Color(red: 0xF2 / 255, green: 0xA9 / 255, blue: 0x3B / 255)
    static let riskHigh = Color(red: 0xE6 / 255, green: 0x3E / 255, blue: 0x32 / 255)
    static let scoreGood = Color(red: 0x7C / 255, green: 0xB9 / 255, blue: 0x2C / 255)
    /// Accent-container tone: brand yellow, or the active theme preset's
    /// accent container when one is selected.
    static var simplyYellow: Color {
        presetFor(ProfileStore.shared.appearance)?.accentContainer
            ?? Color(red: 0xFD / 255, green: 0xE8 / 255, blue: 0x98 / 255)
    }
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
    /// Jumps straight back to a live scanner with a clean stack.
    var onScanNext: () -> Void = {}

    @EnvironmentObject var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState = .loading
    @State private var perServing = true
    @State private var alternatives: [ProductRepository.Alternative] = []
    @State private var showSubmit = false
    @State private var userState: String?
    @State private var crowdSignal: String?
    @State private var crowdShowAsk = false
    @State private var bioShowAsk = false
    @State private var bioJustAnswered = false

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
                VStack(spacing: 8) {
                    Image("mascot_surprised")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .padding(.bottom, 8)
                    Text("Not in any database yet")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("Be the first to add it: a photo of the front and the ingredient label takes about 30 seconds, and it goes live for every Simply Pure user once reviewed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    // Kind is unknown for a product not in any database yet;
                    // currentKind falls back to .food so all sections are offered.
                    Button("Add this product") { showSubmit = true }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    Button("Scan again") { dismiss() }
                }
                .padding(24)
                .background(Color.simplyCard,
                            in: RoundedRectangle(cornerRadius: 12))
                .padding()
            case .error(let message):
                VStack(spacing: 8) {
                    Text("Couldn't reach the database")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("Check your connection and try again. This doesn't mean the product isn't listed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                }
                .padding()
            case .loaded(let product, let score):
                detail(product, score)
            }
        }
        .simplyScreenBackground()
        .navigationTitle("Product")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Scan next") { onScanNext() }
            }
        }
        .sheet(isPresented: $showSubmit) {
            SubmitView(barcode: barcode, kind: currentKind, unknownKind: isUnknown)
        }
        .task {
            // With the location toggle on, order the "Available at" chains
            // by the user's cached state and drop chains that don't operate
            // there; the cache refreshes in the background so rendering
            // never waits on GPS.
            if profile.locationTagging {
                userState = LocationTagger.shared.cachedStateCode
            }
            await load()
            if profile.locationTagging,
               let fresh = await LocationTagger.shared.stateCode() {
                userState = fresh
            }
        }
    }

    /// Kind is unknown for a product not in any database yet; treat it as
    /// food so all sections are offered.
    private var currentKind: ProductKind {
        if case .loaded(let product, _) = state { return product.kind }
        return .food
    }

    /// Not in any database yet — the submit form asks what kind it is.
    private var isUnknown: Bool {
        if case .notFound = state { return true }
        return false
    }

    private func load() async {
        state = .loading
        crowdSignal = nil
        crowdShowAsk = false
        bioShowAsk = false
        bioJustAnswered = false
        switch await ProductRepository.shared.lookup(barcode: barcode) {
        case .found(let product, let score):
            perServing = product.servingQuantity != nil
            state = .loaded(product, score)
            // Only food carries the US Bioengineered Food disclosure, only
            // ask while the database has no answer yet, and only ask people
            // who opted into crowdsourcing at all.
            bioShowAsk = CrowdRepository.shared.enabled &&
                product.kind == .food &&
                product.bioengineered == nil &&
                !BioAnswers.answered(barcode)
            // A fresh scan is exactly what the paired device wants to hear
            // about; the engine throttles to once a minute.
            if SyncEngine.shared.paired {
                Task { await SyncEngine.shared.syncNow() }
            }
            if CrowdRepository.shared.enabled {
                crowdShowAsk = !CrowdRepository.shared.answered(barcode)
                crowdSignal = await CrowdRepository.shared.signal(barcode)
            }
            alternatives = await ProductRepository.shared
                .alternatives(for: product, currentScore: score.displayTotal)
        case .notFound: state = .notFound
        case .error(let message): state = .error(message)
        }
    }

    // MARK: Sections

    private func detail(_ product: Product, _ score: ScoreResult) -> some View {
        // Preference alerts join premium when the production gates flip on.
        let hits = Entitlements.shared.locked(.preferenceAlerts)
            ? [] : PreferenceChecker.check(product, profile: profile)
        let servingFactor = (perServing ? product.servingQuantity : nil).map { $0 / 100 } ?? 1
        let metrics = Metric.build(product)
        let negatives = metrics.filter { !$0.higherIsBetter && $0.verdict != .good }
        let positives = metrics.filter { $0.higherIsBetter || $0.verdict == .good }
        let risky = product.additives.contains { $0.effectiveRisk >= .moderate }

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(product, score)

                if !hits.isEmpty { preferenceBanner(hits) }
                if crowdSignal != nil || crowdShowAsk { crowdCard }
                // One question at a time: the buy question leads, the
                // bioengineered label question takes its place once that
                // is answered or absent. Same rule as Android.
                if product.kind == .food,
                   (bioShowAsk && !crowdShowAsk) || bioJustAnswered || product.bioengineered != nil {
                    bioCard(product)
                }
                if score.total == nil || score.isPartial { missingDataCard(score) }
                if !score.euBanned.isEmpty { bannedBanner(score.euBanned) }

                if product.servingQuantity != nil, !score.ingredientBased {
                    // OFF serving sizes are often shouty label text
                    // ("1 TORTILLA (41 g)"); lowercase all-caps strings so
                    // the toggle reads naturally.
                    let serving = product.servingSize.map { s in
                        s.contains(where: { $0.isLetter }) &&
                            !s.contains(where: { $0.isLowercase })
                            ? s.lowercased() : s
                    }
                    Toggle(isOn: $perServing) {
                        Text(perServing
                            ? "per serving: \(serving ?? "?")"
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

                if !score.ingredientBased, let summary = Self.perServingSummary(product) {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }

                if !score.ingredientBased {
                    AllNutrientsSection(
                        product: product,
                        servingFactor: servingFactor,
                        perServing: perServing)
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
                if score.kind == .household || score.kind == .cosmetic,
                   score.additivesKnown {
                    environmentSection(product)
                }

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
                    .padding(.top, 16)

                Text(disclaimerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Link(destination: URL(string: "https://simplypure.studio86.dev/methodology.html")!) {
                    Text("Read the full methodology").underline()
                }
                .font(.caption)
                .padding(.top, 2)
                .padding(.bottom, 16)
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
                if !product.stores.isEmpty {
                    let stores = StoreNames.forState(product.stores, userState)
                    Text("Available at: \(stores.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    /// Opt-in crowdsourcing card: what other scanners chose (once a product
    /// has enough anonymous answers) and, if this user hasn't answered yet,
    /// the one ask. Answering hides the question for this product forever.
    private var crowdCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let line = crowdSignal {
                Text(line).bold()
                Text("Based on anonymous answers from Simply Pure users.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if crowdShowAsk {
                Text("Did you buy this product?")
                    .bold()
                    .padding(.top, crowdSignal != nil ? 8 : 0)
                HStack(spacing: 8) {
                    Button("Yes") { answerCrowd(true) }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("No") { answerCrowd(false) }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.simplyCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private func answerCrowd(_ bought: Bool) {
        crowdShowAsk = false
        Task { await CrowdRepository.shared.answer(barcode, bought: bought) }
    }

    /// Bioengineered (GMO) product data: shows the reviewed answer when
    /// the database has one, otherwise asks the user to check the package
    /// for the US Bioengineered Food disclosure. One tap submits; the
    /// answer goes live after review, same as every other correction.
    private func bioCard(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bioengineered (GMO)").bold()
            if product.bioengineered == "yes" {
                Text("The package shows the US Bioengineered Food disclosure.")
                    .font(.subheadline)
            } else if product.bioengineered == "no" {
                Text("The package shows no bioengineered food disclosure.")
                    .font(.subheadline)
            } else if bioJustAnswered {
                Text("Thanks. Your answer goes live for everyone once reviewed.")
                    .font(.subheadline)
            } else if bioShowAsk {
                Text("Does the package say Bioengineered food or Contains a bioengineered food ingredient? It is usually near the ingredient list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Yes") { answerBio(true) }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("No") { answerBio(false) }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.simplyCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private func answerBio(_ disclosed: Bool) {
        // Remember locally first: even if the post fails, never re-ask.
        BioAnswers.markAnswered(barcode)
        bioShowAsk = false
        bioJustAnswered = true
        Task {
            _ = await ProductRepository.shared.submitFacts(
                barcode: barcode, bioengineered: disclosed ? "yes" : "no")
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
            Text("Contains \(banned.map(\.displayName).joined(separator: ", ")), not permitted in European products but legal in the US.")
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
                breakdownRow("Nutrition (Simply Pure model)",
                             score.nutritionKnown ? "\(score.nutritionPoints) / 60" : "no data")
                breakdownRow("Additives",
                             score.additivesKnown ? "\(score.additivePoints) / 30" : "no data")
                breakdownRow("Processing (NOVA)",
                             score.processingKnown ? "\(score.processingPoints) / 10" : "no data")
            }
            if score.cappedByBanned {
                Text("Score capped at 24: an ingredient banned in the EU is present. No other points can raise it above that.")
                    .font(.caption).foregroundStyle(Color.riskHigh)
            } else if score.cappedByHighRisk {
                Text("Score capped at 49: a high-risk additive is present. No nutrition numbers can raise it above that.")
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

    /// Household products only: whether anything in the ingredient list
    /// carries a documented environmental concern (EU CLP aquatic-toxicity
    /// classification, poor biodegradability, eutrophication). Display
    /// only; the score itself rates human safety.
    private func environmentSection(_ product: Product) -> some View {
        let flagged = product.additives.filter { $0.envNote != nil }
        return VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Environment")
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(flagged.isEmpty ? Color.riskNone : Color.riskModerate)
                Text(flagged.isEmpty
                    ? "No environmental red flags"
                    : "\(flagged.count) ingredient\(flagged.count == 1 ? "" : "s") flagged for the environment")
                    .font(.subheadline.weight(.medium))
            }
            if flagged.isEmpty {
                Text("Nothing in the ingredient list is flagged for aquatic toxicity, poor biodegradability, or waterway damage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(flagged) { ingredient in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(ingredient.envNote ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            Text("Based on EU environmental-hazard classifications, reef-protection bans, and the EU microplastics and detergent rules. Shown for information; the score rates safety for you, not the planet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private func additivesSection(_ product: Product, _ score: ScoreResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeading(score.ingredientBased && score.kind != .petFood
                ? "Ingredients of note (\(product.additives.count))"
                : "Additives (\(product.additives.count + product.unratedAdditives.count))")
            if product.additives.isEmpty && product.unratedAdditives.isEmpty {
                Text(score.additivesKnown
                    ? "No additives detected, a good sign."
                    : "No ingredient information for this product yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(product.additives.sorted { $0.effectiveRisk > $1.effectiveRisk }) { additive in
                // Dose vs. daily limit only makes sense for things you eat.
                let doseText: String? = score.kind == .food
                    ? AdiEstimator.estimate(
                        additive: additive,
                        ingredientsText: product.ingredientsText,
                        servingQuantityG: product.servingQuantity
                      )?.displayText ?? AdiEstimator.notEstimated
                    : nil
                AdditiveRow(additive: additive, doseText: doseText)
            }
            ForEach(product.unratedAdditives) { unrated in
                Label("\(unrated.eNumber) (not yet rated)", systemImage: "circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if score.kind == .food {
                EuStandardExplainer()
            }
        }
    }

    /// One-line "what a serving means against a day" summary. Adult daily
    /// reference amounts: sugars 50 g, saturated fat 20 g, sodium 2300 mg,
    /// energy 2000 kcal. Display only — the score stays per-100g based.
    static func perServingSummary(_ product: Product) -> String? {
        guard let serving = product.servingQuantity, serving > 0,
              let n = product.nutriments else { return nil }
        let factor = serving / 100.0
        func amount(_ v: Double) -> String {
            v < 10 ? String(format: "%.1f", v) : "\(Int(v.rounded()))"
        }
        func pct(_ v: Double, _ reference: Double) -> String {
            "\(Int((v / reference * 100).rounded()))"
        }
        var parts: [String] = []
        if let sugars = n.sugars {
            let v = sugars * factor
            parts.append("\(amount(v)) g sugar (\(pct(v, 50))% of daily reference)")
        }
        if let satFat = n.saturatedFat {
            let v = satFat * factor
            parts.append("\(amount(v)) g sat fat (\(pct(v, 20))%)")
        }
        if let sodium = n.sodium ?? n.salt.map({ $0 / 2.5 }) {
            let v = sodium * 1000 * factor
            parts.append("\(Int(v.rounded())) mg sodium (\(pct(v, 2300))%)")
        }
        if let kcal = n.energyKcal {
            let v = kcal * factor
            parts.append("\(Int(v.rounded())) kcal (\(pct(v, 2000))%)")
        }
        guard !parts.isEmpty else { return nil }
        let servingText = serving == serving.rounded()
            ? "\(Int(serving))" : String(format: "%.1f", serving)
        // The first entry carries the "of daily reference" wording for all.
        return "Per \(servingText) g serving: \(parts.joined(separator: " · "))"
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
            return "Scores reflect EU/EFSA safety assessments and the Simply Pure nutrition model. Product data from the Open Food Facts community (ODbL)."
        }
    }

    private var disclaimerText: String {
        "Scores summarize cited regulatory assessments of ingredients and " +
        "nutrition data; they aren't medical advice."
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
            .background(Color.simplyCard,
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Score ring

struct ScoreRing: View {
    let score: ScoreResult
    @State private var showStandard = false

    var body: some View {
        let shownTotal = score.displayTotal
        let color = score.displayBand?.color ?? .gray
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 8)
                if let total = shownTotal {
                    Circle()
                        .trim(from: 0, to: CGFloat(total) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(shownTotal.map(String.init) ?? "?")
                    .font(.title3.bold())
                    .foregroundStyle(color)
            }
            .frame(width: 68, height: 68)
            Text(score.displayLabel)
                .font(.caption.bold())
                .foregroundStyle(color)
            if score.personalized != nil {
                Text("Personalized")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.simplyCard, in: Capsule())
                if showStandard, let standard = score.total {
                    Text("Standard score: \(standard)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if score.personalized != nil { showStandard.toggle() }
        }
    }
}

// MARK: - "Why the European standard?" explainer

let euStandardExplainer =
    "Simply Pure rates additives against the European Union's food-safety " +
    "system, the strictest widely adopted in the world. The EU reviews " +
    "additives before they reach shelves and withdraws approval when new " +
    "evidence raises doubt, a precautionary approach. In the US, an " +
    "additive can stay in food while evidence is re-examined.\n\n" +
    "Titanium dioxide (E171) was withdrawn in the EU in 2022 but remains " +
    "legal in the US. Potassium bromate is not permitted in the EU, " +
    "Canada, or Japan, yet still appears in some US breads.\n\n" +
    "An EU flag doesn't mean a product is acutely dangerous, because dose " +
    "matters. That's why Simply Pure also estimates, where reliable intake " +
    "limits exist, how much of an additive one serving contains.\n\n" +
    "Reading the dose line: the daily limit is the acceptable daily " +
    "intake set by regulators for a 70 kg adult. At 15% of the daily " +
    "limit per serving, it would take several servings a day, every day, " +
    "to reach the level regulators still consider safe over a lifetime. " +
    "When the line says the amount is unknown, no reliable estimate was " +
    "possible; the color then reflects the additive's risk class alone, " +
    "and the note on the row explains the specific concern.\n\n" +
    "Sources: EFSA, SCCS, Health Canada, Japan's MHLW."

struct EuStandardExplainer: View {
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Why the European standard?") {
                expanded.toggle()
            }
            .font(.footnote)
            if expanded {
                Text(euStandardExplainer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
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
        // Protein and fiber are positives, so a trace amount (or zero) must
        // not produce a "Contains ..." row — that reads as a contradiction
        // next to the 0 g value. Below 0.5 g/100 g the row is not a positive.
        if let protein = n.proteins, protein >= 0.5 {
            metrics.append(Metric(label: "Protein", valuePer100g: protein, unit: "g",
                cutoffs: [8], gaugeMax: 16, verdict: .good,
                comment: protein >= 8 ? "Rich in protein" : "Contains protein",
                higherIsBetter: true))
        }
        if let fiber = n.fiber, fiber >= 0.5 {
            metrics.append(Metric(label: "Fiber", valuePer100g: fiber, unit: "g",
                cutoffs: [3.5], gaugeMax: 7, verdict: .good,
                comment: fiber >= 3.5 ? "Rich in fiber" : "Contains fiber",
                higherIsBetter: true))
        }
        return metrics
    }
}

/// Every other nutrient on the record (trans fat, cholesterol, vitamins,
/// minerals, …) behind a tap-to-expand card, labeled and unit-converted
/// via the same catalog the submit flow uses. Follows the per-100g /
/// per-serving toggle like the gauges above. Mirrors Android.
struct AllNutrientsSection: View {
    let product: Product
    let servingFactor: Double
    let perServing: Bool
    @State private var expanded = false

    // Nutriment keys already shown as gauges in Negatives/Positives.
    private static let gaugeKeys: Set<String> = [
        "energy-kcal_100g", "sugars_100g", "saturated-fat_100g",
        "sodium_100g", "proteins_100g", "fiber_100g",
    ]

    private struct RowItem: Identifiable {
        let id: String
        let label: String
        let value: String
    }

    private var rows: [RowItem] {
        let values = product.nutriments?.all ?? [:]
        return nutrientFields.compactMap { field in
            guard let key = field.offKey,
                  !Self.gaugeKeys.contains(key),
                  let per100 = values[key] else { return nil }
            // OFF stores grams per 100 g; convert into the label's unit.
            let display = per100 * servingFactor * field.unit.perGram
            return RowItem(
                id: key, label: field.label,
                value: "\(Self.format(display)) \(field.unit.rawValue)")
        }
    }

    private var otherLines: [String] {
        (product.nutritionOther ?? "")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        let rows = rows
        let other = otherLines
        if !rows.isEmpty || !other.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("More nutrition facts (\(rows.count + other.count))")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(perServing ? "Per serving" : "Per 100 g")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    ForEach(rows) { row in
                        Divider().padding(.vertical, 8)
                        HStack {
                            Text(row.label).font(.subheadline)
                            Spacer()
                            Text(row.value).font(.subheadline.weight(.semibold))
                        }
                    }
                    ForEach(other, id: \.self) { line in
                        Divider().padding(.vertical, 8)
                        Text(line).font(.subheadline)
                    }
                }
            }
            .padding(16)
            .background(Color.simplyCard, in: RoundedRectangle(cornerRadius: 12))
            .padding(.vertical, 8)
        }
    }

    private static func format(_ value: Double) -> String {
        if value == 0 { return "0" }
        if abs(value) >= 100 { return String(Int(value.rounded())) }
        let text = abs(value) >= 0.1
            ? String(format: "%.2f", value)
            : String(format: "%.3f", value)
        return text.replacingOccurrences(
            of: "\\.?0+$", with: "", options: .regularExpression)
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
                    // Calories and milligrams read as whole numbers:
                    // "118.4Cal" and "270.2 mg" imply precision the label
                    // data doesn't have.
                    Text((metric.unit == "Cal" || metric.unit == "mg"
                        ? String(Int(value.rounded()))
                        : format(value)) + " " + metric.unit)
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

    // Gauge scale labels stay whole numbers: per-serving scaling turns tidy
    // per-100g cutoffs into values like 945.6, which read as noise. Labels
    // are evenly spaced along the bar, so display rounding shifts nothing.
    private func format(_ value: Double) -> String {
        value >= 100
            ? String(Int((value / 10).rounded()) * 10)
            : String(Int(value.rounded()))
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
    var doseText: String?
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
                            : "\(additive.eNumber): \(additive.displayName)")
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
                        if let doseText {
                            Text(doseText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
