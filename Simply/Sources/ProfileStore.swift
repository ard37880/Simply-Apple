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

    // Whole-word matching for short ingredient words: plain substring read
    // "xantham gum" (an OCR misspelling of xanthan) as ham, and would read
    // graham crackers as pork, crumbs as rum, licorice as rice. A single
    // word matches on its own (plus a simple plural); phrases with spaces
    // still match as phrases. Mirrors Android's wordIn().
    private static var wordRegexCache: [String: NSRegularExpression] = [:]
    private static func wordIn(_ text: String, _ word: String) -> Bool {
        if word.contains(" ") || word.contains("-") { return text.contains(word) }
        let regex: NSRegularExpression
        if let cached = wordRegexCache[word] {
            regex = cached
        } else {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))(?:e?s)?\\b"
            guard let built = try? NSRegularExpression(pattern: pattern) else {
                return text.contains(word)
            }
            wordRegexCache[word] = built
            regex = built
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    // Label phrases that name no actual alcohol, stripped before the
    // alcohol scan so root beer and bourbon vanilla stay halal.
    private static func stripAlcoholFalseFriends(_ text: String) -> String {
        var out = text
        for phrase in ["root beer", "ginger beer", "birch beer", "bourbon vanilla"] {
            out = out.replacingOccurrences(of: phrase, with: " ")
        }
        return out
    }

    static func check(_ product: Product, profile: ProfileStore) -> [PreferenceHit] {
        guard product.kind == .food else { return [] }
        var hits: [PreferenceHit] = []
        let text = (product.ingredientsText ?? "").lowercased()

        // Allergens: declared tags and declared traces only. No keyword
        // guessing: this is a fact-based app, and "Likely contains milk"
        // from a substring match flagged coconut milk as dairy. When the
        // record declares nothing, allergenDataMissing() drives an honest
        // "not verified" card instead. Same rules as Android.
        for key in profile.allergens {
            guard let option = ProfileStore.allergenOptions.first(where: { $0.key == key })
            else { continue }
            if product.allergensTags.contains(option.offTag) {
                hits.append(.init(label: "Contains \(option.label.lowercased())", severity: .contains))
            } else if product.tracesTags.contains(option.offTag) {
                hits.append(.init(label: "May contain traces of \(option.label.lowercased())", severity: .traces))
            }
        }

        // Bioengineered (GMO): only the label disclosure counts. No crop
        // guessing; when the disclosure is unknown the product page asks
        // the user instead. Same rules as Android.
        if profile.diets.contains("no_bioengineered"), product.bioengineered == "yes" {
            hits.append(.init(label: "Contains bioengineered ingredients", severity: .contains))
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
        // Compounds a word-boundary match would miss are listed outright
        // (popcorn is corn, buttermilk is dairy); buckwheat deliberately
        // stops counting as wheat — it contains none.
        let grainsAndSugars = ["wheat", "corn", "rice", "oat", "barley", "flour", "sugar",
                               "corn syrup", "maltodextrin", "popcorn", "oatmeal",
                               "cornmeal", "cornstarch"]
        let alcoholText = stripAlcoholFalseFriends(text)

        if diets.contains("pescatarian"), landMeat.contains(where: { wordIn(text, $0) }) {
            hits.append(.init(label: "Contains meat (not pescatarian)", severity: .contains))
        }
        if diets.contains("halal") {
            if porkWords.contains(where: { wordIn(text, $0) }) {
                hits.append(.init(label: "Not halal (contains pork)", severity: .contains))
            } else if let match = alcoholWords.first(where: { wordIn(alcoholText, $0) }) {
                hits.append(.init(label: "May not be halal (contains \(match))", severity: .contains))
            } else if text.contains("gelatin"), !text.contains("fish gelatin") {
                hits.append(.init(label: "May not be halal (unspecified gelatin)", severity: .likely))
            }
        }
        if diets.contains("kosher") {
            if porkWords.contains(where: { wordIn(text, $0) }) {
                hits.append(.init(label: "Not kosher (contains pork)", severity: .contains))
            } else if shellfish.contains(where: { wordIn(text, $0) }) {
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
                ["soy", "soybean", "soya", "bean", "lentil", "peanut",
                 "milk", "buttermilk", "cheese"]
            if nonPaleo.contains(where: { wordIn(text, $0) }) {
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
                hits.append(.init(label: "Contains unspecified vegetable oil (often a seed oil)", severity: .likely))
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
           let source = ["caffeine", "guarana", "coffee", "yerba mate"]
               .first(where: text.contains) {
            hits.append(.init(
                label: source == "caffeine"
                    ? "Contains caffeine"
                    : "Contains \(source) (a caffeine source)",
                severity: .contains))
        }

        var seen = Set<String>()
        return hits.filter { seen.insert($0.label).inserted }
    }

    enum AllergenAnswer { case noneDeclared, unknown }

    /// What the record can honestly tell a user who tracks allergens when
    /// none of them hit. noneDeclared: the record has real data to check
    /// (an ingredient list or analyzed allergen tags) and none of the
    /// tracked allergens are declared, so a green "none declared, check
    /// the label" card is earned. unknown: nothing to check against, so
    /// the neutral "not verified" card shows instead. Never a guess in
    /// either direction: a tracked allergen word in the raw text (real
    /// dairy words, not coconut milk) withholds the all-clear but never
    /// creates a warning. Nil when no card applies. Same rules as Android.
    static func allergenAnswer(_ product: Product, profile: ProfileStore) -> AllergenAnswer? {
        guard product.kind == .food, !profile.allergens.isEmpty else { return nil }
        let options = ProfileStore.allergenOptions.filter { profile.allergens.contains($0.key) }
        if options.contains(where: {
            product.allergensTags.contains($0.offTag) || product.tracesTags.contains($0.offTag)
        }) { return nil }
        let text = (product.ingredientsText ?? "").lowercased()
        if product.allergensTags.isEmpty,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .unknown
        }
        let guarded = options.contains { option in
            guard let words = allergenGuardWords[option.key] else { return false }
            var scanned = text
            if option.key == "milk" {
                scanned = scanned.replacingOccurrences(
                    of: dairyFalseFriends, with: " ", options: .regularExpression)
            } else if option.key == "eggs" {
                scanned = scanned.replacingOccurrences(of: "eggplant", with: " ")
            }
            return words.contains(where: scanned.contains)
        }
        return guarded ? .unknown : .noneDeclared
    }

    // Guard words per allergen: used ONLY to withhold the "none declared"
    // reassurance when the raw ingredient text names a tracked allergen
    // that the tags missed. Never used to claim presence.
    private static let allergenGuardWords: [String: [String]] = [
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
        "gluten": ["wheat", "barley", "rye", "malt", "spelt", "semolina", "durum",
                   "farro", "triticale", "seitan", "graham", "gluten"],
    ]

    // Phrases that contain a dairy keyword but no dairy: plant milks and
    // creams, cocoa/shea/nut butters, butternut squash, cream of tartar.
    private static let dairyFalseFriends =
        "\\b(coconut|almond|oat|soy|soya|rice|cashew|hemp|pea|macadamia|walnut)\\s?milk\\b|" +
        "\\bcoconut cream\\b|\\bcream of (tartar|coconut)\\b|" +
        "\\b(cocoa|shea|peanut|almond|cashew|sunflower|seed|nut) butter\\b|" +
        "\\bbutternut\\b|\\bmilk thistle\\b"
}
