import SwiftUI
import Vision

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return self }
        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// Keep only the English ingredient section from raw OCR text — same
/// markers as the Android app (Spanish and French label sections, etc.).
func extractIngredients(from raw: String) -> String {
    let text = raw.replacingOccurrences(of: "\\s+", with: " ",
                                        options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    let lower = text.lowercased()

    var start = text.startIndex
    if let range = lower.range(of: "ingredients") {
        start = range.upperBound
    }
    while start < text.endIndex, ":;.,- ".contains(text[start]) {
        start = text.index(after: start)
    }

    var end = text.endIndex
    let stopMarkers = ["ingredientes", "ingrédients", "distributed by", "manufactured",
                       "nutrition facts", "made in", "allergen information",
                       "keep refrigerated", "best if used", "store in a cool",
                       "questions?", "www.", "©"]
    for marker in stopMarkers {
        if let range = lower.range(of: marker, range: start..<text.endIndex),
           range.lowerBound < end {
            end = range.lowerBound
        }
    }
    guard start < end else { return "" }
    return String(text[start..<end])
        .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;-"))
}

// Unit a nutrition value is entered in, exactly as printed on the label.
// OFF nutriment values are grams per 100 g (energy stays kcal), so each
// unit carries its grams divisor for the save-time conversion.
enum NutrientUnit: String {
    case kcal, g, mg, mcg
    case gOrMl = "g or ml"

    var perGram: Double {
        switch self {
        case .kcal, .g, .gOrMl: return 1
        case .mg: return 1_000
        case .mcg: return 1_000_000
        }
    }
}

// Per-serving nutrition entry (food products only), covering the full US
// nutrition-facts label. Core fields always show in the section; extended
// ones appear when the label scan finds them or the user adds them via
// the "Add a nutrient" picker. offKey is the OFF per-100g nutriment key
// (nil = the serving-size field). Same table as the Android app.
struct NutrientField {
    let key: String
    let label: String
    let unit: NutrientUnit
    let offKey: String?
    var core = false
}

let nutrientFields: [NutrientField] = [
    // Serving accepts grams or milliliters (1 ml counts as 1 g); labels
    // that give only a count ("2 cookies") need the mass typed in.
    NutrientField(key: "serving", label: "Serving size", unit: .gOrMl, offKey: nil, core: true),
    NutrientField(key: "calories", label: "Calories", unit: .kcal, offKey: "energy-kcal_100g", core: true),
    NutrientField(key: "totalfat", label: "Total fat", unit: .g, offKey: "fat_100g", core: true),
    NutrientField(key: "satfat", label: "Saturated fat", unit: .g, offKey: "saturated-fat_100g", core: true),
    NutrientField(key: "transfat", label: "Trans fat", unit: .g, offKey: "trans-fat_100g", core: true),
    NutrientField(key: "cholesterol", label: "Cholesterol", unit: .mg, offKey: "cholesterol_100g", core: true),
    NutrientField(key: "sodium", label: "Sodium", unit: .mg, offKey: "sodium_100g", core: true),
    NutrientField(key: "carbs", label: "Total carbohydrate", unit: .g, offKey: "carbohydrates_100g", core: true),
    NutrientField(key: "fiber", label: "Dietary fiber", unit: .g, offKey: "fiber_100g", core: true),
    NutrientField(key: "sugars", label: "Total sugars", unit: .g, offKey: "sugars_100g", core: true),
    NutrientField(key: "addedsugars", label: "Added sugars", unit: .g, offKey: "added-sugars_100g", core: true),
    NutrientField(key: "protein", label: "Protein", unit: .g, offKey: "proteins_100g", core: true),
    NutrientField(key: "polyfat", label: "Polyunsaturated fat", unit: .g, offKey: "polyunsaturated-fat_100g"),
    NutrientField(key: "monofat", label: "Monounsaturated fat", unit: .g, offKey: "monounsaturated-fat_100g"),
    NutrientField(key: "polyols", label: "Sugar alcohols", unit: .g, offKey: "polyols_100g"),
    NutrientField(key: "vitd", label: "Vitamin D", unit: .mcg, offKey: "vitamin-d_100g"),
    NutrientField(key: "calcium", label: "Calcium", unit: .mg, offKey: "calcium_100g"),
    NutrientField(key: "iron", label: "Iron", unit: .mg, offKey: "iron_100g"),
    NutrientField(key: "potassium", label: "Potassium", unit: .mg, offKey: "potassium_100g"),
    NutrientField(key: "vita", label: "Vitamin A", unit: .mcg, offKey: "vitamin-a_100g"),
    NutrientField(key: "vitc", label: "Vitamin C", unit: .mg, offKey: "vitamin-c_100g"),
    NutrientField(key: "vite", label: "Vitamin E", unit: .mg, offKey: "vitamin-e_100g"),
    NutrientField(key: "vitk", label: "Vitamin K", unit: .mcg, offKey: "vitamin-k_100g"),
    NutrientField(key: "thiamin", label: "Thiamin", unit: .mg, offKey: "vitamin-b1_100g"),
    NutrientField(key: "riboflavin", label: "Riboflavin", unit: .mg, offKey: "vitamin-b2_100g"),
    NutrientField(key: "niacin", label: "Niacin", unit: .mg, offKey: "vitamin-pp_100g"),
    NutrientField(key: "vitb6", label: "Vitamin B6", unit: .mg, offKey: "vitamin-b6_100g"),
    NutrientField(key: "folate", label: "Folate", unit: .mcg, offKey: "vitamin-b9_100g"),
    NutrientField(key: "vitb12", label: "Vitamin B12", unit: .mcg, offKey: "vitamin-b12_100g"),
    NutrientField(key: "biotin", label: "Biotin", unit: .mcg, offKey: "biotin_100g"),
    NutrientField(key: "pantothenic", label: "Pantothenic acid", unit: .mg, offKey: "pantothenic-acid_100g"),
    NutrientField(key: "phosphorus", label: "Phosphorus", unit: .mg, offKey: "phosphorus_100g"),
    NutrientField(key: "iodine", label: "Iodine", unit: .mcg, offKey: "iodine_100g"),
    NutrientField(key: "magnesium", label: "Magnesium", unit: .mg, offKey: "magnesium_100g"),
    NutrientField(key: "zinc", label: "Zinc", unit: .mg, offKey: "zinc_100g"),
    NutrientField(key: "selenium", label: "Selenium", unit: .mcg, offKey: "selenium_100g"),
    NutrientField(key: "copper", label: "Copper", unit: .mg, offKey: "copper_100g"),
    NutrientField(key: "manganese", label: "Manganese", unit: .mg, offKey: "manganese_100g"),
    NutrientField(key: "chromium", label: "Chromium", unit: .mcg, offKey: "chromium_100g"),
    NutrientField(key: "molybdenum", label: "Molybdenum", unit: .mcg, offKey: "molybdenum_100g"),
    NutrientField(key: "chloride", label: "Chloride", unit: .mg, offKey: "chloride_100g"),
    NutrientField(key: "choline", label: "Choline", unit: .mg, offKey: "choline_100g"),
    NutrientField(key: "caffeine", label: "Caffeine", unit: .mg, offKey: "caffeine_100g"),
]

// A label line that has no OFF nutriment key (e.g. taurine). These are
// serialized into the human-readable nutrition_other facts field instead
// of the nutriments map, since OFF wouldn't understand arbitrary keys.
struct OtherNutrient: Identifiable {
    let id = UUID()
    var name = ""
    var amount = ""
    var unit = "mg"
}

/// Best-effort read of a US nutrition-facts label from raw OCR text.
/// Returns per-serving values keyed by the nutrition field keys — prefill
/// only, the user confirms or corrects every value. Same patterns as the
/// Android app.
func parseNutritionFacts(from raw: String) -> [String: String] {
    let text = raw.replacingOccurrences(of: "\\s+", with: " ",
                                        options: .regularExpression)
    var out: [String: String] = [:]
    func grab(_ key: String, _ pattern: String) {
        guard out[key] == nil,
              let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return }
        out[key] = String(text[range])
    }
    // One nutrient line: the value in the label's printed unit comes right
    // after the name, so the %DV that follows is never captured
    // ("Sodium 190mg 8%" -> 190). mcg accepts the µg spellings OCR reads.
    func nutrient(_ key: String, _ name: String, _ unit: String) {
        let u = unit == "mcg" ? "(?:mcg|µg|ug)" : unit
        grab(key, #"\b"# + name + #"\D{0,10}(\d+(?:\.\d+)?)\s*"# + u)
    }
    // "Serving size 2/3 cup (55g)" — grams in parentheses first, then bare
    grab("serving", #"serving size[^(]{0,40}\((\d+(?:\.\d+)?)\s*(?:g|ml)\)"#)
    grab("serving", #"serving size\D{0,20}(\d+(?:\.\d+)?)\s*(?:g|ml)"#)
    grab("calories", #"\bcalories\D{0,10}(\d+(?:\.\d+)?)"#)
    nutrient("totalfat", "total fat", "g")
    nutrient("satfat", "saturated fat", "g")
    nutrient("transfat", "trans fat", "g")
    nutrient("polyfat", "polyunsaturated fat", "g")
    nutrient("monofat", "monounsaturated fat", "g")
    nutrient("cholesterol", "cholesterol", "mg")
    nutrient("sodium", "sodium", "mg")
    // "Total Carbohydrate" / "Total Carb." — \D swallows either spelling
    grab("carbs", #"\btotal carb\D{0,15}(\d+(?:\.\d+)?)\s*g"#)
    nutrient("fiber", "(?:dietary )?fiber", "g")
    // "Total Sugars 4g" but never the "Includes Xg Added Sugars" line
    grab("sugars", #"(?<!added )(?:total )?sugars\D{0,10}(\d+(?:\.\d+)?)\s*g"#)
    grab("addedsugars", #"\bincludes\s*(\d+(?:\.\d+)?)\s*g\s*(?:of\s+)?added sugars"#)
    nutrient("addedsugars", "added sugars", "g")
    nutrient("polyols", "sugar alcohols?", "g")
    nutrient("polyols", "polyols?", "g")
    nutrient("protein", "protein", "g")
    nutrient("vitd", "vitamin d", "mcg")
    nutrient("calcium", "calcium", "mg")
    nutrient("iron", "iron", "mg")
    nutrient("potassium", "potassium", "mg")
    nutrient("vita", "vitamin a", "mcg")
    nutrient("vitc", "vitamin c", "mg")
    nutrient("vite", "vitamin e", "mg")
    nutrient("vitk", "vitamin k", "mcg")
    nutrient("thiamin", "thiamine?", "mg")
    nutrient("riboflavin", "riboflavin", "mg")
    nutrient("niacin", "niacin", "mg")
    nutrient("vitb6", #"vitamin b\s*[6₆]"#, "mg")
    // "Folate 165mcg DFE (100mcg folic acid)" — the DFE amount comes first
    nutrient("folate", "folate", "mcg")
    nutrient("vitb12", #"vitamin b\s*12"#, "mcg")
    nutrient("biotin", "biotin", "mcg")
    nutrient("pantothenic", "pantothenic acid", "mg")
    nutrient("phosphorus", "phosphorus", "mg")
    nutrient("iodine", "iodine", "mcg")
    nutrient("magnesium", "magnesium", "mg")
    nutrient("zinc", "zinc", "mg")
    nutrient("selenium", "selenium", "mcg")
    nutrient("copper", "copper", "mg")
    nutrient("manganese", "manganese", "mg")
    nutrient("chromium", "chromium", "mcg")
    nutrient("molybdenum", "molybdenum", "mcg")
    nutrient("chloride", "chloride", "mg")
    nutrient("choline", "choline", "mg")
    nutrient("caffeine", "caffeine", "mg")
    return out
}

func recognizeText(in image: UIImage) async -> String {
    guard let cgImage = image.cgImage else { return "" }
    return await withCheckedContinuation { continuation in
        var resumed = false
        let request = VNRecognizeTextRequest { request, _ in
            guard !resumed else { return }
            resumed = true
            let text = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ") ?? ""
            continuation.resume(returning: text)
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        // The additive lexicon steers Vision toward real label words, so
        // "carrageenan" wins over near-miss dictionary words.
        request.usesLanguageCorrection = true
        request.customWords = Array(AdditiveRepository.shared.lexiconWords)
        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
        } catch {
            if !resumed { resumed = true; continuation.resume(returning: "") }
        }
    }
}

// MARK: - Submit screen

struct SubmitView: View {
    let barcode: String
    var kind: ProductKind = .food
    // A product in no database yet has no kind — the submitter says what
    // it is, which drives the form AND preselects the reviewer's category.
    var unknownKind = false
    @Environment(\.dismiss) private var dismiss

    init(barcode: String, kind: ProductKind = .food, unknownKind: Bool = false) {
        self.barcode = barcode
        self.kind = kind
        self.unknownKind = unknownKind
        // The picker starts on the product's current category so a
        // mis-filed item (mouthwash stored as food) can be corrected.
        _chosenKind = State(initialValue: kind)
    }

    private static let slots: [(String, String)] = [
        ("front", "Front of package"),
        ("ingredients", "Ingredient list"),
        ("nutrition", "Nutrition facts label"),
    ]

    @State private var chosenKind: ProductKind = .food
    // The picker drives the form for unknown AND known products, so
    // recategorizing immediately stops asking for nutrition facts.
    private var effectiveKind: ProductKind { chosenKind }

    // Bioengineered disclosure correction: nil = not checked, "yes"
    // needs the disclosure photo as proof, "no" is a bare statement
    // (absence can't be photographed).
    @State private var bioChoice: String?

    // Nutrition facts only apply to food; other kinds skip the section
    // and the nutrition-label photo slot.
    private var slots: [(String, String)] {
        var list = effectiveKind == .food
            ? Self.slots
            : Self.slots.filter { $0.0 != "nutrition" }
        if effectiveKind == .food, bioChoice == "yes" {
            list.append(("bioengineered", "Bioengineered disclosure"))
        }
        return list
    }

    @State private var captured: [String: UIImage] = [:]
    @State private var pickingField: String?
    @State private var ocrText = ""
    @State private var ocrRan = false
    @State private var ocrFixes: [OcrCorrector.Correction] = []
    @State private var store = ""
    @State private var productName = ""
    @State private var brandName = ""
    @State private var storeAsk = false
    @State private var storeAsked = false
    @State private var nutrition: [String: String] = [:]
    @State private var servingUnit = "g"
    @State private var servingWeight = ""
    @State private var nutritionOcrRan = false
    @State private var nutritionOcrFound = false
    // Extended fields currently shown (OCR hit or user-added via picker)
    @State private var extraVisible: Set<String> = []
    @State private var others: [OtherNutrient] = []
    @State private var saving = false
    @State private var resultMessage: String?

    private var hasWork: Bool {
        !captured.isEmpty
            || !ocrText.trimmingCharacters(in: .whitespaces).isEmpty
            || bioChoice != nil
            || !store.trimmingCharacters(in: .whitespaces).isEmpty
            || !productName.trimmingCharacters(in: .whitespaces).isEmpty
            || !brandName.trimmingCharacters(in: .whitespaces).isEmpty
            || nutrition.values.contains {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }
            || others.contains {
                !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                    || !$0.amount.trimmingCharacters(in: .whitespaces).isEmpty
            }
            // A category correction is savable work on its own.
            || chosenKind != kind
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Photograph the package, check the scanned ingredient list, then tap Save. Your contribution improves this product for every Simply Pure user.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let message = resultMessage {
                        Text(message)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(message.hasPrefix("Saved")
                                ? Color.riskNone : Color.riskHigh)
                    }

                    Text(unknownKind ? "What kind of product is this?" : "Category")
                        .font(.subheadline.weight(.bold))
                    if !unknownKind {
                        Text("Wrong category? Pick the right one and save; a reviewer will move it. Personal care covers deodorant, toothpaste, mouthwash, skin care, and similar. Non-food products aren't asked for nutrition facts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Group {
                        FlowLayout(spacing: 8) {
                            ForEach([
                                (ProductKind.food, "Food"),
                                (ProductKind.cosmetic, "Personal care"),
                                (ProductKind.petFood, "Pet food"),
                                (ProductKind.household, "Household"),
                            ], id: \.1) { k, label in
                                Button {
                                    chosenKind = k
                                    if k != .food {
                                        // Nutrition facts don't apply — drop
                                        // anything the food form collected.
                                        captured.removeValue(forKey: "nutrition")
                                        nutrition = [:]
                                        extraVisible = []
                                        others = []
                                        nutritionOcrRan = false
                                        nutritionOcrFound = false
                                        captured.removeValue(forKey: "bioengineered")
                                        bioChoice = nil
                                    }
                                } label: {
                                    Text(label)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(
                                            chosenKind == k
                                                ? Color.riskNone.opacity(0.18)
                                                : Color.simplyCard,
                                            in: Capsule())
                                        .overlay(Capsule().stroke(
                                            chosenKind == k ? Color.riskNone : .clear,
                                            lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    ForEach(slots, id: \.0) { field, label in
                        slotCard(field: field, label: label)
                    }

                    if effectiveKind == .food {
                        Text("Bioengineered disclosure")
                            .font(.subheadline.weight(.bold))
                        Text("Does the package say Bioengineered food or Contains a bioengineered food ingredient? It is usually near the ingredient list. A yes takes a photo of the disclosure as proof.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach([
                                (String?.none, "Not checked"),
                                ("yes", "Shows disclosure"),
                                ("no", "No disclosure"),
                            ] as [(String?, String)], id: \.1) { value, label in
                                Button {
                                    bioChoice = value
                                    if value != "yes" {
                                        captured.removeValue(forKey: "bioengineered")
                                    }
                                    resultMessage = nil
                                } label: {
                                    Text(label)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(
                                            bioChoice == value
                                                ? Color.riskNone.opacity(0.18)
                                                : Color.simplyCard,
                                            in: Capsule())
                                        .overlay(Capsule().stroke(
                                            bioChoice == value ? Color.riskNone : .clear,
                                            lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if ocrRan {
                        Text(ocrText.isEmpty
                            ? "Couldn't read text from the ingredient photo. You can type the list manually."
                            : "Here's what the scan read from the label. Please check it against the package and fix any mistakes, then tap Save:")
                            .font(.subheadline)
                        TextEditor(text: $ocrText)
                            .frame(minHeight: 110)
                            .padding(6)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(.quaternary))
                        if !ocrFixes.isEmpty {
                            Text("Auto-corrected from the photo: "
                                + ocrFixes.map { "\($0.from) to \($0.to)" }
                                    .joined(separator: ", ")
                                + ". Double-check these against the label.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // The nutrition form only appears once a nutrition-label
                    // photo was taken and scanned — the same gate as the
                    // ingredient editor.
                    if effectiveKind == .food, nutritionOcrRan {
                        nutritionSection
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Product name (optional)")
                            .font(.subheadline)
                        TextField("As printed on the package", text: $productName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: productName) { _ in resultMessage = nil }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Brand / manufacturer (optional)")
                            .font(.subheadline)
                        TextField("e.g. Kirkland Signature", text: $brandName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: brandName) { _ in resultMessage = nil }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Store (optional)")
                            .font(.subheadline)
                        TextField("e.g. Costco, Walmart", text: $store)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: store) { _ in resultMessage = nil }
                    }
                }
                .padding()
            }
            .simplyScreenBackground()
            .navigationTitle("Improve this product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // The single save point — uploads photos + verified text
                    Button(saving ? "Saving…" : "Save") { requestSave() }
                        .bold()
                        .disabled(!hasWork || saving)
                }
            }
            .alert("Add the store?", isPresented: $storeAsk) {
                TextField("e.g. Costco, Walmart", text: $store)
                Button(store.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "Save without store" : "Save") {
                    storeAsked = true
                    saveAll()
                }
                Button("Back", role: .cancel) {}
            } message: {
                Text("You have location tagging on. Naming the store where "
                    + "you found this helps people in your area.")
            }
            .sheet(item: $pickingField) { field in
                CameraPicker { image in
                    captured[field] = image
                    if field == "ingredients" {
                        Task {
                            // Lexicon pass snaps common OCR misreads back to
                            // real label words before the user proofreads.
                            let (corrected, fixes) = OcrCorrector.shared.correctWithReport(
                                extractIngredients(from: await recognizeText(in: image)))
                            ocrText = corrected
                            ocrFixes = fixes
                            ocrRan = true
                        }
                    } else if field == "nutrition" {
                        Task {
                            // Prefill only fields the user hasn't typed into.
                            let parsed = parseNutritionFacts(
                                from: await recognizeText(in: image))
                            for (key, value) in parsed
                            where (nutrition[key] ?? "")
                                .trimmingCharacters(in: .whitespaces).isEmpty {
                                nutrition[key] = value
                            }
                            // Extended fields the label scan found join the form
                            for catalogField in nutrientFields
                            where !catalogField.core
                                && !(nutrition[catalogField.key] ?? "").isEmpty {
                                extraVisible.insert(catalogField.key)
                            }
                            nutritionOcrFound = !parsed.isEmpty
                            nutritionOcrRan = true
                        }
                    }
                }
            }
        }
    }

    // Core fields plus whichever extended fields are visible, two per row
    private var shownNutrientRows: [[NutrientField]] {
        let shown = nutrientFields.filter {
            $0.offKey != nil && ($0.core || extraVisible.contains($0.key))
        }
        return stride(from: 0, to: shown.count, by: 2).map {
            Array(shown[$0..<min($0 + 2, shown.count)])
        }
    }

    // Fields the score engine reads: with all of these present the product
    // gets a full nutrition rating instead of a partial one. Marked with *
    // in the form — encouraged, never required.
    private static let scoredNutrientKeys: Set<String> =
        ["serving", "calories", "satfat", "sugars", "sodium", "fiber", "protein"]

    @ViewBuilder private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nutrition facts (per serving)")
                .font(.subheadline.weight(.semibold))
            Text("* used to calculate the score; filling these in gives the product a full rating instead of a partial one.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(nutritionOcrFound
                ? "Here's what the scan read from the label. Please check it against the package and fix any mistakes, then tap Save:"
                : "Couldn't read values from the nutrition photo. You can enter them manually.")
                .font(.subheadline)
            // Serving size: a number plus the unit as printed on the
            // label. Pieces ("3 crackers", "1 bottle") also ask the
            // weight of that many, which drives the per-100g math.
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Serving size *")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: Binding(
                        get: { nutrition["serving"] ?? "" },
                        set: { nutrition["serving"] = $0; resultMessage = nil }
                    ))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                }
                Menu(servingUnit) {
                    ForEach(["g", "ml", "oz", "fl oz", "pieces"], id: \.self) { unit in
                        Button(unit) {
                            servingUnit = unit
                            resultMessage = nil
                        }
                    }
                }
            }
            if servingUnit == "pieces" {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weight of that many (g or ml) *")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("printed next to the serving, like (30 g)", text: Binding(
                        get: { servingWeight },
                        set: { servingWeight = $0; resultMessage = nil }
                    ))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                }
            }
            ForEach(shownNutrientRows, id: \.first!.key) { row in
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(row, id: \.key) { field in
                        nutritionField(field)
                    }
                }
            }
            // Rows for label lines that have no OFF nutriment key
            ForEach(others) { other in
                HStack(spacing: 8) {
                    TextField("Nutrient", text: otherBinding(other.id, \.name))
                        .textFieldStyle(.roundedBorder)
                    TextField("Amount", text: otherBinding(other.id, \.amount))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 110)
                    Menu(other.unit) {
                        ForEach(["g", "mg", "mcg"], id: \.self) { unit in
                            Button(unit) {
                                if let i = others.firstIndex(where: { $0.id == other.id }) {
                                    others[i].unit = unit
                                }
                            }
                        }
                    }
                    Button {
                        others.removeAll { $0.id == other.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.riskHigh)
                    }
                }
            }
            HStack(spacing: 12) {
                let addable = nutrientFields.filter {
                    !$0.core && !extraVisible.contains($0.key)
                }
                if !addable.isEmpty {
                    Menu("Add a nutrient") {
                        ForEach(addable, id: \.key) { field in
                            Button("\(field.label) (\(field.unit.rawValue))") {
                                extraVisible.insert(field.key)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Button("Other nutrient") { others.append(OtherNutrient()) }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func nutritionField(_ field: NutrientField) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(field.label) (\(field.unit.rawValue))"
                + (Self.scoredNutrientKeys.contains(field.key) ? " *" : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: Binding(
                get: { nutrition[field.key] ?? "" },
                set: { nutrition[field.key] = $0; resultMessage = nil }
            ))
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity)
    }

    private func otherBinding(
        _ id: UUID, _ keyPath: WritableKeyPath<OtherNutrient, String>
    ) -> Binding<String> {
        Binding(
            get: { others.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { value in
                if let i = others.firstIndex(where: { $0.id == id }) {
                    others[i][keyPath: keyPath] = value
                    resultMessage = nil
                }
            }
        )
    }

    private func slotCard(field: String, label: String) -> some View {
        HStack(spacing: 12) {
            if let image = captured[field] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "camera")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 56, height: 56)
            }
            Text(label)
            Spacer()
            if captured[field] != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.riskNone)
            }
            Button(captured[field] == nil ? "Take photo" : "Retake") {
                pickingField = field
            }
            .buttonStyle(.bordered)
            if captured[field] != nil {
                Button {
                    captured.removeValue(forKey: field)
                    if field == "ingredients" { ocrText = ""; ocrRan = false; ocrFixes = [] }
                    if field == "nutrition" {
                        nutrition = [:]
                        extraVisible = []
                        others = []
                        nutritionOcrRan = false
                        nutritionOcrFound = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.riskHigh)
                }
            }
        }
        .padding(12)
        .background(Color.simplyCard,
                    in: RoundedRectangle(cornerRadius: 12))
    }

    // One save entry point: when the user opted into location tagging but
    // didn't name a store, offer to add one first (their area only attaches
    // to store reports).
    private func requestSave() {
        if ProfileStore.shared.locationTagging,
           store.trimmingCharacters(in: .whitespaces).isEmpty,
           !storeAsked {
            storeAsk = true
        } else {
            saveAll()
        }
    }

    private func saveAll() {
        if bioChoice == "yes", captured["bioengineered"] == nil {
            resultMessage = "A shows-disclosure answer needs the photo of the disclosure. Take it and tap Save again."
            return
        }
        saving = true
        resultMessage = nil
        Task {
            var okPhotos = 0
            for (field, image) in captured {
                if await ProductRepository.shared.submitPhoto(
                    barcode: barcode, field: field, image: image) {
                    okPhotos += 1
                }
            }
            let ingredients = ocrText.trimmingCharacters(in: .whitespaces)
            let storeName = store.trimmingCharacters(in: .whitespaces)
            let productNameText = productName.trimmingCharacters(in: .whitespaces)
            let brandText = brandName.trimmingCharacters(in: .whitespaces)
            // Sent for brand-new products, and for existing ones as a
            // correction whenever the picker differs from the current kind.
            let suggestedCategory: String? = (unknownKind || chosenKind != kind) ? {
                switch chosenKind {
                case .food: return "Food"
                case .cosmetic: return "Cosmetics"
                case .petFood: return "Pet food"
                case .household: return "Household"
                }
            }() : nil
            // Nutrition values are entered per serving; convert to per 100 g
            // using the serving grams. Without serving grams they can't be
            // converted, so they're skipped and the message says so.
            func numField(_ key: String) -> Double? {
                nutrition[key].flatMap {
                    Double($0.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: ",", with: "."))
                }
            }
            // The serving is a number plus a unit from the dropdown. Mass
            // and volume convert straight to grams (1 ml counts as 1 g);
            // "pieces" ("3 crackers", "1 bottle") also needs the weight of
            // that many, or the math waits.
            let servingValue = numField("serving").flatMap { $0 > 0 ? $0 : nil }
            let servingWeightG = Double(servingWeight
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: "."))
                .flatMap { $0 > 0 ? $0 : nil }
            let servingG: Double?
            if servingValue == nil {
                servingG = nil
            } else if servingUnit == "g" || servingUnit == "ml" {
                servingG = servingValue
            } else if servingUnit == "oz" {
                servingG = servingValue.map { $0 * 28.3495 }
            } else if servingUnit == "fl oz" {
                servingG = servingValue.map { $0 * 29.5735 }
            } else {
                servingG = servingWeightG // pieces
            }
            let perServing: [(String, Double)] = nutrientFields.compactMap { field in
                // OFF stores nutrients in grams; the label prints the
                // field's unit (mg, mcg) — kcal stays kcal.
                guard let offKey = field.offKey, let value = numField(field.key)
                else { return nil }
                return (offKey, value / field.unit.perGram)
            }
            let nutritionSkipped = !perServing.isEmpty && servingG == nil
            // 3 decimals, but never fewer than 3 significant digits so
            // micronutrients entered in mcg survive the grams conversion.
            func roundPer100g(_ value: Double) -> Double {
                guard value > 0 else { return 0 }
                var scale = 1000.0
                while value * scale < 100 { scale *= 10 }
                return (value * scale).rounded() / scale
            }
            var nutriments: [String: Double]?
            if let servingG, !perServing.isEmpty {
                nutriments = Dictionary(uniqueKeysWithValues: perServing.map {
                    ($0.0, roundPer100g($0.1 / servingG * 100))
                })
            }
            // A serving entered as a count ("1" for one cookie) instead of
            // grams makes the per-100g math explode: nothing real holds
            // more than 100 g of a nutrient per 100 g, or 950 kcal.
            let servingLooksWrong = nutriments?.contains { key, value in
                key.hasPrefix("energy-kcal") ? value > 950 : value > 100
            } ?? false
            if servingLooksWrong {
                saving = false
                let grams = servingG.map {
                    $0 == $0.rounded(.down) ? "\(Int($0))" : "\($0)"
                } ?? "?"
                resultMessage = "Check the serving size: it reads as \(grams) g "
                    + "per serving, which makes these numbers more than is "
                    + "physically possible per 100 g. Use the weight from the "
                    + "label, usually printed in parentheses next to the "
                    + "household measure, like 3 crackers (30 g)."
                return
            }
            // Nutrients with no OFF key travel as one human-readable string
            let otherText = others.compactMap { other -> String? in
                let name = other.name.trimmingCharacters(in: .whitespaces)
                let amount = other.amount.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, !amount.isEmpty else { return nil }
                return "\(name): \(amount) \(other.unit) per serving"
            }.joined(separator: "; ")
            func fmt(_ v: Double) -> String {
                v == v.rounded(.down) ? "\(Int(v))" : "\(v)"
            }
            let servingSizeText: String?
            if let servingValue {
                if servingUnit == "pieces", let servingG {
                    servingSizeText = "\(fmt(servingValue)) pieces (\(fmt(servingG)) g)"
                } else if servingUnit == "pieces" {
                    servingSizeText = "\(fmt(servingValue)) pieces"
                } else {
                    servingSizeText = "\(fmt(servingValue)) \(servingUnit)"
                }
            } else {
                servingSizeText = nil
            }
            var factsOk: Bool?
            // A category correction on an existing product stands on its
            // own; brand-new products still need at least one photo so the
            // reviewer has something to verify against.
            if !ingredients.isEmpty || !storeName.isEmpty || servingG != nil
                || !otherText.isEmpty || !productNameText.isEmpty
                || !brandText.isEmpty || bioChoice != nil
                || (suggestedCategory != nil && (okPhotos > 0 || !unknownKind)) {
                // Coarse "City, State" tag, only when a store is being
                // reported and the user opted in.
                let region = (!storeName.isEmpty && ProfileStore.shared.locationTagging)
                    ? await LocationTagger.shared.region()
                    : nil
                factsOk = await ProductRepository.shared.submitFacts(
                    barcode: barcode,
                    ingredientsText: ingredients.isEmpty ? nil : ingredients,
                    stores: storeName.isEmpty ? nil : storeName,
                    storesRegion: region,
                    nutriments: nutriments,
                    nutritionOther: otherText.isEmpty ? nil : otherText,
                    servingSize: servingSizeText,
                    servingQuantity: servingG,
                    productName: productNameText.isEmpty ? nil : productNameText,
                    brands: brandText.isEmpty ? nil : brandText,
                    suggestedCategory: suggestedCategory,
                    bioengineered: bioChoice)
            }
            saving = false
            if !captured.isEmpty, okPhotos < captured.count {
                resultMessage = "Uploaded \(okPhotos) of \(captured.count) photos. Check your connection and tap Save again."
            } else if factsOk == false {
                resultMessage = "Photos uploaded, but the product details didn't save. Tap Save again."
            } else if okPhotos == 0, factsOk == nil, nutritionSkipped {
                resultMessage = "Nutrition facts need the serving size. For pieces, also add the weight of that many, printed on the label like (30 g). Then tap Save again."
            } else if okPhotos == 0, factsOk == nil {
                resultMessage = "Nothing to save yet. Take a photo first."
            } else {
                var parts: [String] = []
                if okPhotos > 0 { parts.append("\(okPhotos) photo\(okPhotos == 1 ? "" : "s")") }
                if factsOk == true {
                    if !productNameText.isEmpty { parts.append("the product name") }
                    if !brandText.isEmpty { parts.append("the brand") }
                    if !ingredients.isEmpty { parts.append("the ingredient list") }
                    if nutriments != nil || !otherText.isEmpty { parts.append("the nutrition facts") }
                    else if servingG != nil { parts.append("the serving size") }
                    if !storeName.isEmpty { parts.append("the store") }
                    if suggestedCategory != nil { parts.append("the category") }
                }
                resultMessage = "Saved \(parts.joined(separator: " + ")), thank you! Your submission will appear once it's reviewed."
                    + (nutritionSkipped
                        ? " Nutrition facts weren't saved. Add the serving size (for pieces, also their weight) and tap Save again."
                        : "")
            }
        }
    }
}

extension String: Identifiable {
    public var id: String { self }
}

/// Camera capture (falls back to the photo library in the simulator).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController
            .isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
