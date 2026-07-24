import Foundation
import SwiftUI

struct DietOption: Identifiable {
    var id: String { key }
    let key: String
    let label: String
}

struct AllergenOption: Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let offTag: String
}

/// Profile lives ONLY on this device (UserDefaults) — no accounts, no
/// cloud, nothing shared. Mirrors the Android app's option set exactly.
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @AppStorage("profile.name") var name: String = ""
    @AppStorage("profile.onboarded") var onboarded: Bool = false
    /// Check scan history against FDA recalls and notify.
    @AppStorage("profile.recallAlerts") var recallAlerts: Bool = false
    /// Tag store submissions with a coarse "City, State".
    @AppStorage("profile.locationTagging") var locationTagging: Bool = false
    /// Answer "did you buy this?" and see what other scanners chose.
    @AppStorage("profile.crowdsourcing") var crowdsourcing: Bool = false
    /// App appearance: "light" (default), "dark", or "system".
    /// Older releases stored "khaki" for light; readers map it to light.
    @AppStorage("profile.appearance") var appearance: String = "light"
    @AppStorage("profile.diets") private var dietsRaw: String = ""
    @AppStorage("profile.allergens") private var allergensRaw: String = ""

    var diets: Set<String> {
        // Chips removed in 1.9 (carnivore, no_pork, no_beef, no_alcohol)
        // may still be stored on older installs — drop them on read.
        get {
            Set(dietsRaw.split(separator: ",").map(String.init))
                .intersection(Self.knownDietKeys)
        }
        set { dietsRaw = newValue.sorted().joined(separator: ",") }
    }

    var allergens: Set<String> {
        get { Set(allergensRaw.split(separator: ",").map(String.init)) }
        set { allergensRaw = newValue.sorted().joined(separator: ",") }
    }

    /// When the user last edited preferences on THIS device (milliseconds
    /// since epoch, matching the Android value). Sync merges by this,
    /// never by sync time, so a frequently syncing device can't clobber a
    /// fresh edit made on its partner.
    var prefsEditedAt: Int64 {
        Int64(UserDefaults.standard.double(forKey: "profile.prefsEditedAt"))
    }

    private func stampPrefsEdited() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970 * 1000,
            forKey: "profile.prefsEditedAt")
    }

    /// Applies the paired device's preferences without claiming a fresh
    /// local edit: the remote edit time is adopted as-is.
    func applySyncedPrefs(
        name: String, diets: Set<String>, allergens: Set<String>, editedAt: Int64
    ) {
        objectWillChange.send()
        self.name = name
        self.diets = diets.intersection(Self.knownDietKeys)
        self.allergens = allergens
        UserDefaults.standard.set(Double(editedAt), forKey: "profile.prefsEditedAt")
    }

    /// Name edits route through here so they stamp prefsEditedAt like any
    /// other preference edit.
    func setName(_ value: String) {
        guard value != name else { return }
        name = value
        stampPrefsEdited()
    }

    func toggleDiet(_ key: String) {
        objectWillChange.send()
        var d = diets
        if d.contains(key) { d.remove(key) } else { d.insert(key) }
        diets = d
        stampPrefsEdited()
    }

    func toggleAllergen(_ key: String) {
        objectWillChange.send()
        var a = allergens
        if a.contains(key) { a.remove(key) } else { a.insert(key) }
        allergens = a
        stampPrefsEdited()
    }

    // Actual ways of eating. Halal covers pork and alcohol; the old
    // standalone no-pork / no-beef / no-alcohol / carnivore chips were
    // removed (stored keys from older installs are dropped on read).
    static let dietOptions: [DietOption] = [
        .init(key: "vegetarian", label: "Vegetarian"),
        .init(key: "vegan", label: "Vegan"),
        .init(key: "pescatarian", label: "Pescatarian"),
        .init(key: "halal", label: "Halal"),
        .init(key: "kosher", label: "Kosher"),
        .init(key: "keto", label: "Keto / low-carb"),
        .init(key: "paleo", label: "Paleo"),
        .init(key: "low_sodium", label: "Low sodium"),
        .init(key: "anti_inflammatory", label: "Anti-inflammatory"),
    ]

    // Specific ingredients to flag — its own profile section, same
    // underlying storage set as dietOptions so nothing migrates.
    static let avoidOptions: [DietOption] = [
        .init(key: "no_bioengineered", label: "Bioengineered (GMO)"),
        .init(key: "no_palm_oil", label: "Palm oil"),
        .init(key: "no_seed_oils", label: "Seed oils"),
        .init(key: "no_hydrogenated", label: "Hydrogenated oils"),
        .init(key: "no_artificial_sweeteners", label: "Artificial sweeteners"),
        .init(key: "no_artificial_colors", label: "Artificial dyes"),
        .init(key: "no_hfcs", label: "High-fructose corn syrup"),
        .init(key: "no_msg", label: "MSG"),
        .init(key: "no_nitrites", label: "Nitrites/nitrates"),
        .init(key: "no_caffeine", label: "Caffeine"),
    ]

    static let knownDietKeys: Set<String> =
        Set((dietOptions + avoidOptions).map(\.key))

    static let allergenOptions: [AllergenOption] = [
        .init(key: "gluten", label: "Gluten / wheat", offTag: "en:gluten"),
        .init(key: "milk", label: "Milk / dairy", offTag: "en:milk"),
        .init(key: "eggs", label: "Eggs", offTag: "en:eggs"),
        .init(key: "peanuts", label: "Peanuts", offTag: "en:peanuts"),
        .init(key: "nuts", label: "Tree nuts", offTag: "en:nuts"),
        .init(key: "soy", label: "Soy", offTag: "en:soybeans"),
        .init(key: "fish", label: "Fish", offTag: "en:fish"),
        .init(key: "crustaceans", label: "Shellfish (crustaceans)", offTag: "en:crustaceans"),
        .init(key: "molluscs", label: "Molluscs", offTag: "en:molluscs"),
        .init(key: "sesame", label: "Sesame", offTag: "en:sesame-seeds"),
        .init(key: "mustard", label: "Mustard", offTag: "en:mustard"),
        .init(key: "celery", label: "Celery", offTag: "en:celery"),
        .init(key: "sulphites", label: "Sulphites", offTag: "en:sulphur-dioxide-and-sulphites"),
        .init(key: "lupin", label: "Lupin", offTag: "en:lupin"),
    ]
}

// MARK: - Preference checking (same rules as Android)

enum HitSeverity: Int { case contains = 0, traces, likely }

struct PreferenceHit: Identifiable {
    var id: String { label }
    let label: String
    let severity: HitSeverity
}

enum PreferenceChecker {

    static func check(_ product: Product, profile: ProfileStore) -> [PreferenceHit] {
        guard product.kind == .food else { return [] }
        var hits: [PreferenceHit] = []
        let text = (product.ingredientsText ?? "").lowercased()

        // Allergens: declared tags, then traces, then keyword fallback.
        // The fallback runs per allergen: partially tagged records are
        // common (a community member tagged milk, nobody tagged sesame),
        // so one present tag must not silence the text check for the rest.
        for key in profile.allergens {
            guard let option = ProfileStore.allergenOptions.first(where: { $0.key == key })
            else { continue }
            if product.allergensTags.contains(option.offTag) {
                hits.append(.init(label: "Contains \(option.label.lowercased())", severity: .contains))
            } else if product.tracesTags.contains(option.offTag) {
                hits.append(.init(label: "May contain traces of \(option.label.lowercased())", severity: .traces))
            } else if !text.isEmpty,
                      keywordLikely(key, text: text, labelsTags: product.labelsTags) {
                hits.append(.init(label: "Likely contains \(option.label.lowercased())", severity: .likely))
            }
        }

        // Bioengineered (GMO): the user-reported label disclosure wins,
        // then a non-GMO or organic claim clears it, then the major US
        // bioengineered crops make it "likely". Same rules as Android.
        if profile.diets.contains("no_bioengineered") {
            if product.bioengineered == "yes" {
                hits.append(.init(label: "Contains bioengineered ingredients", severity: .contains))
            } else if product.bioengineered == nil,
                      !product.isOrganic,
                      !product.labelsTags.contains(where: { nonGmoLabels.contains($0) }),
                      text.range(of: beCropWords, options: .regularExpression) != nil {
                hits.append(.init(label: "Likely contains bioengineered ingredients", severity: .likely))
            }
        }

        let diets = profile.diets
        let analysis = product.ingredientsAnalysisTags

        if diets.contains("vegan"), analysis.contains("en:non-vegan") {
            hits.append(.init(label: "Not vegan", severity: .contains))
        }
        if diets.contains("vegetarian"), analysis.contains("en:non-vegetarian") {
            hits.append(.init(label: "Not vegetarian", severity: .contains))
        }
        if diets.contains("no_palm_oil"), analysis.contains("en:palm-oil") {
            hits.append(.init(label: "Contains palm oil", severity: .contains))
        }

        let landMeat = ["pork", "bacon", "ham", "lard", "beef", "chicken", "turkey",
                        "lamb", "veal", "duck", "venison", "pepperoni", "salami"]
        let porkWords = ["pork", "bacon", "ham", "lard"]
        let shellfish = ["shrimp", "crab", "lobster", "prawn", "oyster", "clam", "mussel"]
        let alcoholWords = ["alcohol", "wine", "beer", "rum", "whiskey", "bourbon", "liqueur"]
        let grainsAndSugars = ["wheat", "corn", "rice", "oat", "barley", "flour", "sugar",
                               "corn syrup", "maltodextrin"]

        if diets.contains("pescatarian"), landMeat.contains(where: text.contains) {
            hits.append(.init(label: "Contains meat (not pescatarian)", severity: .contains))
        }
        if diets.contains("halal") {
            if porkWords.contains(where: text.contains) {
                hits.append(.init(label: "Not halal (contains pork)", severity: .contains))
            } else if let match = alcoholWords.first(where: text.contains) {
                hits.append(.init(label: "May not be halal (contains \(match))", severity: .contains))
            } else if text.contains("gelatin"), !text.contains("fish gelatin") {
                hits.append(.init(label: "May not be halal (unspecified gelatin)", severity: .likely))
            }
        }
        if diets.contains("kosher") {
            if porkWords.contains(where: text.contains) {
                hits.append(.init(label: "Not kosher (contains pork)", severity: .contains))
            } else if shellfish.contains(where: text.contains) {
                hits.append(.init(label: "Not kosher (contains shellfish)", severity: .contains))
            } else if text.contains("gelatin"), !text.contains("fish gelatin") {
                hits.append(.init(label: "May not be kosher (unspecified gelatin)", severity: .likely))
            }
        }
        if diets.contains("keto"), let sugars = product.nutriments?.sugars, sugars > 5 {
            hits.append(.init(
                label: "High sugar, not keto-friendly (\(Int(sugars)) g/100 g)",
                severity: .contains))
        }
        if diets.contains("paleo") {
            let nonPaleo: [String] = grainsAndSugars +
                ["soy", "bean", "lentil", "peanut", "milk", "cheese"]
            if nonPaleo.contains(where: { text.contains($0) }) {
                hits.append(.init(label: "Contains grains/dairy/legumes (not paleo)", severity: .contains))
            }
        }
        if diets.contains("low_sodium") {
            let sodiumMg = (product.nutriments?.sodium
                ?? product.nutriments?.salt.map { $0 / 2.5 }).map { $0 * 1000 }
            if let mg = sodiumMg, mg > 400 {
                hits.append(.init(label: "High sodium (\(Int(mg)) mg/100 g)", severity: .contains))
            }
        }

        let eNumbers = Set(product.additives.map { $0.eNumber.uppercased() })

        if diets.contains("anti_inflammatory") {
            if let sugars = product.nutriments?.sugars, sugars > 13.5 {
                hits.append(.init(
                    label: "High sugar, not anti-inflammatory friendly (\(Int(sugars)) g/100 g)",
                    severity: .contains))
            }
            if text.contains("hydrogenated") {
                hits.append(.init(
                    label: "Contains hydrogenated oils (pro-inflammatory fats)",
                    severity: .contains))
            }
            if !eNumbers.isDisjoint(with: ["E249", "E250", "E251", "E252"]) {
                hits.append(.init(
                    label: "Contains nitrites/nitrates (processed-meat preservatives)",
                    severity: .contains))
            }
            if product.novaGroup == 4 {
                hits.append(.init(label: "Ultra-processed (NOVA 4)", severity: .likely))
            }
        }

        if diets.contains("no_seed_oils") {
            let named = ["canola", "rapeseed", "soybean oil", "corn oil", "sunflower oil",
                         "safflower", "cottonseed", "grapeseed", "rice bran oil"]
            if named.contains(where: text.contains) {
                hits.append(.init(label: "Contains seed oil", severity: .contains))
            } else if text.contains("vegetable oil") {
                hits.append(.init(label: "Likely contains seed oil (unspecified vegetable oil)", severity: .likely))
            }
        }
        if diets.contains("no_hydrogenated"),
           text.contains("hydrogenated") || text.contains("interesterified") {
            hits.append(.init(label: "Contains hydrogenated/interesterified oil", severity: .contains))
        }
        if diets.contains("no_artificial_sweeteners") {
            let es: Set<String> = ["E950", "E951", "E952", "E954", "E955", "E961", "E962", "E969"]
            if !eNumbers.isDisjoint(with: es) ||
                ["aspartame", "sucralose", "acesulfame", "saccharin", "neotame"]
                    .contains(where: text.contains) {
                hits.append(.init(label: "Contains artificial sweetener", severity: .contains))
            }
        }
        if diets.contains("no_artificial_colors") {
            let es: Set<String> = ["E102", "E104", "E110", "E122", "E124", "E127", "E129",
                                   "E131", "E132", "E133", "E142", "E155"]
            if !eNumbers.isDisjoint(with: es) ||
                ["red 40", "red 3", "yellow 5", "yellow 6", "blue 1", "blue 2"]
                    .contains(where: text.contains) {
                hits.append(.init(label: "Contains artificial dye", severity: .contains))
            }
        }
        if diets.contains("no_hfcs"),
           ["high fructose corn syrup", "high-fructose corn syrup", "glucose-fructose syrup"]
               .contains(where: text.contains) {
            hits.append(.init(label: "Contains high-fructose corn syrup", severity: .contains))
        }
        if diets.contains("no_msg"),
           eNumbers.contains("E621") || text.contains("monosodium glutamate") {
            hits.append(.init(label: "Contains MSG", severity: .contains))
        }
        if diets.contains("no_nitrites") {
            let es: Set<String> = ["E249", "E250", "E251", "E252"]
            if !eNumbers.isDisjoint(with: es) || text.contains("nitrite") || text.contains("nitrate") {
                hits.append(.init(label: "Contains nitrites/nitrates", severity: .contains))
            }
        }
        if diets.contains("no_caffeine"),
           ["caffeine", "guarana", "coffee", "yerba mate"].contains(where: text.contains) {
            hits.append(.init(label: "Likely contains caffeine", severity: .likely))
        }

        var seen = Set<String>()
        return hits.filter { seen.insert($0.label).inserted }
    }

    /// Keyword fallback for one allergen. Gluten gets whole-word matching
    /// (plain substrings flagged buckwheat and maltodextrin); a gluten-free
    /// label suppresses only the bare-"flour" guess, never an explicit
    /// gluten grain in the text. Same rules as Android.
    private static func keywordLikely(_ key: String, text: String, labelsTags: [String]) -> Bool {
        guard key == "gluten" else {
            return (allergenKeywords[key] ?? []).contains(where: text.contains)
        }
        // An explicit gluten grain printed in the ingredient list outranks
        // a community-applied gluten-free label; mistagged labels are a
        // celiac hazard. The label only suppresses the vaguer bare-"flour"
        // heuristic below.
        if text.range(of: glutenWords, options: .regularExpression) != nil { return true }
        if labelsTags.contains(where: { glutenFreeLabels.contains($0) }) { return false }
        // Unqualified "flour" means wheat flour on a US label, but rice
        // flour, almond flour etc. are gluten-free.
        guard let regex = try? NSRegularExpression(pattern: "\\b(\\w*)\\s*flour\\b") else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).contains { match in
            guard let r = Range(match.range(at: 1), in: text) else { return false }
            return !glutenFreeFlours.contains(String(text[r]))
        }
    }

    private static let glutenWords =
        "\\b(wheat|barley|rye|malt|malted|spelt|semolina|durum|farro|triticale|seitan|graham)\\b"
    private static let glutenFreeFlours: Set<String> = [
        "rice", "corn", "masa", "almond", "coconut", "oat", "tapioca", "potato",
        "chickpea", "garbanzo", "cassava", "buckwheat", "quinoa", "sorghum",
        "teff", "amaranth", "millet", "soy", "pea", "lentil", "hazelnut",
        "peanut", "banana", "plantain", "arrowroot",
    ]
    private static let glutenFreeLabels: Set<String> = [
        "en:no-gluten", "en:gluten-free", "en:certified-gluten-free",
    ]

    private static let nonGmoLabels: Set<String> = [
        "en:no-gmos", "en:no-gmo", "en:gmo-free",
        "en:non-gmo-project", "en:non-gmo-project-verified",
    ]

    // Ingredients from the US crops that are overwhelmingly grown
    // bioengineered (corn, soy, canola, sugar beet, cottonseed). Note the
    // US disclosure standard exempts highly refined ingredients, so "no
    // disclosure" does not mean "no bioengineered crops" — hence "likely".
    // "Modified food starch" on a US label is usually corn-derived, so it
    // counts; "enriched" does not (enrichment adds vitamins to wheat flour,
    // and no commercially grown US wheat is bioengineered).
    private static let beCropWords =
        "\\b(corn syrup|corn starch|cornstarch|corn oil|corn flour|corn meal|cornmeal|" +
        "modified food starch|modified starch|" +
        "dextrose|maltodextrin|soybean|soy protein|soy flour|soy lecithin|" +
        "canola|cottonseed|sugar beet|beet sugar)\\b"

    /// True when the ingredient list already names a bioengineered-crop
    /// derivative: the avoid check flags these on its own, so the product
    /// page skips the disclosure question entirely.
    static func likelyBioengineered(_ product: Product) -> Bool {
        (product.ingredientsText ?? "").lowercased()
            .range(of: beCropWords, options: .regularExpression) != nil
    }

    private static let allergenKeywords: [String: [String]] = [
        "milk": ["milk", "whey", "casein", "butter", "cream", "cheese", "lactose"],
        "eggs": ["egg"],
        "peanuts": ["peanut"],
        "nuts": ["almond", "cashew", "walnut", "pecan", "hazelnut", "pistachio", "macadamia"],
        "soy": ["soy", "soybean", "soya"],
        "fish": ["fish", "anchovy", "salmon", "tuna", "cod"],
        "crustaceans": ["shrimp", "crab", "lobster", "prawn"],
        "molluscs": ["oyster", "mussel", "clam", "squid", "scallop"],
        "sesame": ["sesame", "tahini"],
        "mustard": ["mustard"],
        "celery": ["celery"],
        "sulphites": ["sulfite", "sulphite", "sulfur dioxide", "sulphur dioxide"],
        "lupin": ["lupin"],
    ]
}
