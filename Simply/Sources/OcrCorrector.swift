import Foundation

/// Fixes the OCR misreads that plague ingredient labels before the text
/// reaches the editor or the additive detector. Three conservative passes per
/// unknown word, in order:
///
///  1. character confusions (0/o, 1/l, 5/s, 8/b, rn/m ...) — "PH0SPH0RIC"
///  2. glued words split at a point where both halves are known — "CITRICACID"
///  3. a unique near-miss spelling in the vocabulary — "carrageenen"
///
/// A word is only ever replaced by vocabulary words, and only when the match
/// is unambiguous, so clean text passes through untouched. The vocabulary is
/// every word of every additive name/synonym in the risk database plus a
/// curated list of common label words. Same rules as Android's OcrCorrector.
final class OcrCorrector {
    static let shared = OcrCorrector(additives: AdditiveRepository.shared)

    private let additives: AdditiveRepository
    private lazy var lexicon: Set<String> = additives.lexiconWords.union(Self.commonWords)

    init(additives: AdditiveRepository) {
        self.additives = additives
    }

    /// One word the corrector rewrote, so the user can double-check it.
    struct Correction: Hashable {
        let from: String
        let to: String
    }

    func correct(_ text: String) -> String {
        correctWithReport(text).corrected
    }

    /// Corrected text plus the list of rewrites that were applied, for the
    /// submit form to show: the user proofreads exactly the words the
    /// corrector touched instead of re-reading the whole label.
    func correctWithReport(_ text: String) -> (corrected: String, corrections: [Correction]) {
        guard let regex = try? NSRegularExpression(pattern: "[A-Za-z0-9]{4,}") else {
            return (text, [])
        }
        var corrections: [Correction] = []
        var seen = Set<Correction>()
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let token = ns.substring(with: match.range)
            if token.contains(where: { $0.isLetter }) {
                let fixed = correctToken(token)
                if fixed != token {
                    let correction = Correction(from: token, to: fixed)
                    if seen.insert(correction).inserted { corrections.append(correction) }
                }
                result += fixed
            } else {
                result += token
            }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return (result, corrections)
    }

    private func correctToken(_ token: String) -> String {
        let lower = token.lowercased()
        if lexicon.contains(lower) { return token }

        if let fixed = confusionFix(lower) { return matchCase(token, fixed) }
        if let split = splitGlued(lower) { return matchCase(token, split) }
        if let near = nearest(lower) { return matchCase(token, near) }
        return token
    }

    /// Common OCR character swaps; accepted only if the result is a known word.
    private func confusionFix(_ word: String) -> String? {
        let mapped = String(word.map { Self.charConfusions[$0] ?? $0 })
        var candidates: [String] = [mapped]
        // Multi-character confusions on both the raw and the char-mapped form.
        for base in [word, mapped] {
            candidates.append(base.replacingOccurrences(of: "rn", with: "m"))
            candidates.append(base.replacingOccurrences(of: "vv", with: "w"))
            candidates.append(base.replacingOccurrences(of: "cl", with: "d"))
        }
        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            if candidate != word && lexicon.contains(candidate) { return candidate }
        }
        return nil
    }

    /// "citricacid" -> "citric acid" when both halves are known words.
    private func splitGlued(_ word: String) -> String? {
        guard word.count >= 7, !word.contains(where: \.isNumber) else { return nil }
        let chars = Array(word)
        for i in 3...(chars.count - 3) {
            let a = String(chars[0..<i])
            let b = String(chars[i...])
            if lexicon.contains(a) && lexicon.contains(b) { return "\(a) \(b)" }
            // The right half may itself carry a confusion ("acld").
            if lexicon.contains(a), let fixed = confusionFix(b) { return "\(a) \(fixed)" }
        }
        return nil
    }

    /// Unique vocabulary word within a length-scaled edit distance.
    private func nearest(_ word: String) -> String? {
        guard word.count >= 5, !word.contains(where: \.isNumber) else { return nil }
        let maxDistance = word.count >= 9 ? 2 : 1
        var best: String?
        var bestDistance = maxDistance + 1
        var tie = false
        for candidate in lexicon {
            if abs(candidate.count - word.count) > maxDistance { continue }
            let d = editDistance(word, candidate, cap: bestDistance)
            if d < bestDistance {
                bestDistance = d
                best = candidate
                tie = false
            } else if d == bestDistance && d <= maxDistance && candidate != best {
                tie = true
            }
        }
        return (!tie && bestDistance <= maxDistance) ? best : nil
    }

    /// Levenshtein with early exit once the distance exceeds `cap`.
    private func editDistance(_ a: String, _ b: String, cap: Int) -> Int {
        if a == b { return 0 }
        let aChars = Array(a)
        let bChars = Array(b)
        var previous = Array(0...bChars.count)
        var current = [Int](repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = min(current[j - 1] + 1, previous[j] + 1, previous[j - 1] + cost)
                if current[j] < rowMin { rowMin = current[j] }
            }
            if rowMin > cap { return cap + 1 }
            swap(&previous, &current)
        }
        return previous[bChars.count]
    }

    private func matchCase(_ original: String, _ replacement: String) -> String {
        if original.allSatisfy({ !$0.isLetter || $0.isUppercase }) {
            return replacement.uppercased()
        }
        if original.first?.isUppercase == true {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }

    private static let charConfusions: [Character: Character] = [
        "0": "o", "1": "l", "5": "s", "8": "b", "6": "g", "2": "z",
    ]

    /// Common US ingredient-label words that are not additive names, so
    /// misreads of everyday words also snap back ("VVATER", "SUGAF").
    private static let commonWords: Set<String> = [
        "water", "sugar", "salt", "flour", "wheat", "corn", "syrup", "oil",
        "oils", "palm", "soybean", "canola", "cottonseed", "sunflower",
        "safflower", "coconut", "olive", "cocoa", "butter", "milk",
        "cream", "whey", "casein", "yeast", "vinegar", "garlic", "onion",
        "tomato", "paste", "concentrate", "juice", "puree", "natural",
        "artificial", "flavor", "flavors", "flavoring", "flavorings",
        "color", "colors", "colored", "added", "preservative",
        "preservatives", "acid", "acids", "acidity", "regulator",
        "enzymes", "cultures", "spices", "spice", "seasoning", "dextrose",
        "maltodextrin", "fructose", "glucose", "sucrose", "lactose",
        "honey", "molasses", "cane", "beet", "invert", "brown", "raw",
        "soy", "rice", "oat", "oats", "barley", "malt", "malted", "rye",
        "extract", "extracts", "starch", "modified", "enriched",
        "bleached", "unbleached", "degermed", "whole", "grain", "grains",
        "bran", "germ", "gluten", "protein", "isolate", "hydrolyzed",
        "potassium", "sodium", "calcium", "magnesium", "iron", "zinc",
        "chloride", "carbonate", "bicarbonate", "sulfate", "sulfite",
        "nitrite", "nitrate", "phosphate", "phosphoric", "citrate",
        "citric", "ascorbic", "lactic", "malic", "acetic", "tartaric",
        "benzoate", "sorbate", "propionate", "erythorbate", "gum",
        "xanthan", "guar", "cellulose", "carrageenan", "pectin",
        "gelatin", "glycerin", "glycerol", "lecithin", "mono", "and",
        "diglycerides", "monoglycerides", "vitamin", "vitamins",
        "riboflavin", "niacin", "thiamine", "thiamin", "folic", "folate",
        "mononitrate", "palmitate", "tocopherol", "tocopherols",
        "contains", "less", "than", "the", "following", "may", "contain",
        "one", "more", "each", "ingredients", "organic", "dried",
        "dehydrated", "powder", "powdered", "granulated", "ground",
        "roasted", "toasted", "cooked", "smoked", "cured", "sea",
        "kosher", "iodized", "baking", "soda", "eggs", "egg", "yolks",
        "whites", "chicken", "beef", "pork", "turkey", "fish", "shrimp",
        "anchovy", "sardine", "tuna", "salmon", "broth", "stock",
        "vegetable", "vegetables", "fruit", "fruits", "apple", "grape",
        "orange", "lemon", "lime", "cherry", "strawberry", "raspberry",
        "blueberry", "banana", "pineapple", "peach", "mango", "carrot",
        "celery", "potato", "potatoes", "pea", "peas", "bean", "beans",
        "lentil", "almond", "almonds", "peanut", "peanuts", "cashew",
        "cashews", "walnut", "walnuts", "pecan", "pecans", "hazelnut",
        "hazelnuts", "pistachio", "sesame", "seed", "seeds", "chia",
        "flax", "quinoa", "vanilla", "chocolate", "caramel", "cinnamon",
        "ginger", "paprika", "turmeric", "cumin", "oregano", "basil",
        "parsley", "cilantro", "pepper", "peppers", "chili", "jalapeno",
        "mustard", "horseradish", "wasabi", "tamari", "miso", "tofu",
        "cheese", "cheddar", "parmesan", "mozzarella", "romano", "swiss",
        "buttermilk", "yogurt", "skim", "nonfat", "lowfat", "reduced",
        "partially", "fully", "hydrogenated", "interesterified",
        "expeller", "pressed", "refined", "virgin", "cold", "filtered",
        "pasteurized", "homogenized", "condensed", "evaporated",
        "sweetened", "unsweetened", "solids", "crystals", "pieces",
        "chips", "flakes", "shortening", "margarine", "lard", "tallow",
        "gelatine", "collagen", "agar", "inulin", "fiber", "psyllium",
    ]
}
