import SwiftUI

/// Maps the short evidence-source names carried by the risk databases
/// (for example "EFSA (2021 opinion)" or "Japan MHLW positive list") to
/// the authority's canonical page, so every citation in the app can be
/// a working link. Unmatched names fall back to plain text.
enum SourceLinks {
    static func url(for name: String) -> URL? {
        let lower = name.lowercased()
        func u(_ s: String) -> URL? { URL(string: s) }
        if lower.contains("southampton") {
            return u("https://doi.org/10.1016/S0140-6736(07)61306-3")
        }
        if lower.contains("2021") && lower.contains("efsa") {
            return u("https://www.efsa.europa.eu/en/efsajournal/pub/6585")
        }
        if lower.contains("nitrite") {
            return u("https://www.efsa.europa.eu/en/efsajournal/pub/7884")
        }
        if lower.contains("2022/63") {
            return u("https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32022R0063")
        }
        if lower.contains("efsa") {
            return u("https://www.efsa.europa.eu/en/topics/topic/food-additives")
        }
        if lower.contains("iarc") {
            return u("https://monographs.iarc.who.int/list-of-classifications")
        }
        if lower.contains("mhlw") || lower.contains("japan") {
            return u("https://www.mhlw.go.jp/english/topics/foodsafety/foodadditives/index.html")
        }
        if lower.contains("health canada") {
            return u("https://www.canada.ca/en/health-canada/services/food-nutrition/food-safety/food-additives/lists-permitted.html")
        }
        if lower.contains("singapore") {
            return u("https://www.sfa.gov.sg/food-information/food-additives")
        }
        if lower.contains("fda") {
            return u("https://www.fda.gov/food/food-additives-petitions")
        }
        if lower.contains("additives database") || lower.contains("european commission") {
            return u("https://food.ec.europa.eu/food-safety/food-improvement-agents/additives/database_en")
        }
        if lower.contains("jecfa") {
            return u("https://www.who.int/groups/joint-fao-who-expert-committee-on-food-additives-(jecfa)")
        }
        return nil
    }
}

/// Every assessment, regulation, and study behind Simply Pure's scores,
/// as tappable citations. Reached from the product footer, the additives
/// section, and the profile — App Review Guideline 1.4.1 requires health
/// information to carry easy-to-find citations, and honesty requires it
/// anyway.
struct SourcesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Every score summarizes published assessments by "
                        + "public authorities and peer-reviewed research. "
                        + "These are the sources; each additive's row also "
                        + "names the specific assessments behind it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    section("Additive safety", [
                        ("EFSA — food additive re-evaluations",
                         "The EU's scientific risk assessments, additive by additive.",
                         "https://www.efsa.europa.eu/en/topics/topic/food-additives"),
                        ("Regulation (EC) No 1333/2008",
                         "The EU list of permitted food additives and their conditions of use.",
                         "https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32008R1333"),
                        ("EU Food Additives Database",
                         "Per-additive permissions and maximum levels by food category.",
                         "https://food.ec.europa.eu/food-safety/food-improvement-agents/additives/database_en"),
                        ("JECFA (FAO/WHO)",
                         "International expert committee setting acceptable daily intakes.",
                         "https://www.who.int/groups/joint-fao-who-expert-committee-on-food-additives-(jecfa)"),
                    ])

                    section("Key assessments behind red flags", [
                        ("EFSA 2021 opinion on titanium dioxide (E171)",
                         "Why E171 is no longer considered safe as a food additive in the EU.",
                         "https://www.efsa.europa.eu/en/efsajournal/pub/6585"),
                        ("Commission Regulation (EU) 2022/63",
                         "The EU ban on titanium dioxide in food.",
                         "https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32022R0063"),
                        ("EFSA 2023 re-evaluation of nitrites and nitrates",
                         "The assessment behind the caution on cured-meat nitrites.",
                         "https://www.efsa.europa.eu/en/efsajournal/pub/7884"),
                        ("McCann et al., The Lancet (2007)",
                         "The Southampton study linking six dyes to hyperactivity; the basis of the EU warning label.",
                         "https://doi.org/10.1016/S0140-6736(07)61306-3"),
                        ("IARC Monographs",
                         "WHO classifications of carcinogenic hazards.",
                         "https://monographs.iarc.who.int/list-of-classifications"),
                    ])

                    section("Country and region status", [
                        ("Japan MHLW — food additives",
                         "Japan's positive-list system for designated additives.",
                         "https://www.mhlw.go.jp/english/topics/foodsafety/foodadditives/index.html"),
                        ("Health Canada — permitted food additives",
                         "Canada's lists of permitted additives and conditions.",
                         "https://www.canada.ca/en/health-canada/services/food-nutrition/food-safety/food-additives/lists-permitted.html"),
                    ])

                    section("Dose estimates", [
                        ("EFSA — acceptable daily intake (ADI)",
                         "What an ADI means; the basis of per-serving dose estimates.",
                         "https://www.efsa.europa.eu/en/glossary/acceptable-daily-intake"),
                    ])

                    section("Nutrition", [
                        ("Regulation (EU) No 1169/2011",
                         "EU reference intakes used for the daily-reference percentages.",
                         "https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32011R1169"),
                        ("US FDA — Daily Values",
                         "US reference values for nutrition labeling.",
                         "https://www.fda.gov/food/nutrition-facts-label/daily-value-nutrition-and-supplement-facts-labels"),
                    ])

                    section("Processing (NOVA)", [
                        ("Monteiro et al., Public Health Nutrition (2019)",
                         "The NOVA classification of food processing.",
                         "https://doi.org/10.1017/S1368980018003762"),
                    ])

                    section("Personal care products", [
                        ("Regulation (EC) No 1223/2009",
                         "The EU Cosmetics Regulation, including banned and restricted substances.",
                         "https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32009R1223"),
                        ("SCCS — Scientific Committee on Consumer Safety",
                         "EU safety opinions on cosmetic ingredients.",
                         "https://health.ec.europa.eu/scientific-committees/scientific-committee-consumer-safety-sccs_en"),
                        ("CosIng",
                         "The EU cosmetic ingredient database.",
                         "https://ec.europa.eu/growth/tools-databases/cosing/"),
                    ])

                    section("Household products", [
                        ("CLP Regulation (ECHA)",
                         "EU hazard classifications for chemicals.",
                         "https://echa.europa.eu/regulations/clp/understanding-clp"),
                        ("Detergents Regulation (EC) No 648/2004",
                         "EU rules on detergent ingredients and biodegradability.",
                         "https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32004R0648"),
                    ])

                    section("Pet food", [
                        ("EU Register of Feed Additives",
                         "Additives authorized in animal feed in the EU.",
                         "https://food.ec.europa.eu/food-safety/animal-feed/feed-additives/eu-register_en"),
                    ])

                    section("Recalls and disclosures", [
                        ("openFDA — food enforcement reports",
                         "The US FDA recall data behind recall alerts.",
                         "https://open.fda.gov/apis/food/enforcement/"),
                        ("USDA — Bioengineered Food Disclosure Standard",
                         "The US disclosure rule behind the bioengineered card.",
                         "https://www.ams.usda.gov/rules-regulations/be"),
                    ])

                    section("Product data", [
                        ("Open Food Facts",
                         "The community database (ODbL) product data comes from.",
                         "https://world.openfoodfacts.org"),
                    ])

                    Link(destination: URL(string: "https://simplypure.studio86.dev/methodology.html")!) {
                        Text("Read the full scoring methodology").underline()
                    }
                    .font(.footnote)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .simplyScreenBackground()
            .navigationTitle("Sources & citations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, _ rows: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(rows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 2) {
                    if let url = URL(string: row.2) {
                        Link(destination: url) {
                            Text(row.0).underline().multilineTextAlignment(.leading)
                        }
                        .font(.footnote)
                    } else {
                        Text(row.0).font(.footnote)
                    }
                    Text(row.1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.simplyCard, in: RoundedRectangle(cornerRadius: 12))
    }
}
