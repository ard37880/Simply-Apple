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
    // "Serving size 2/3 cup (55g)" — grams in parentheses first, then bare
    grab("serving", #"serving size[^(]{0,40}\((\d+(?:\.\d+)?)\s*g\)"#)
    grab("serving", #"serving size\D{0,20}(\d+(?:\.\d+)?)\s*g"#)
    grab("calories", #"calories\D{0,10}(\d+(?:\.\d+)?)"#)
    grab("sugars", #"(?:total )?sugars\D{0,10}(\d+(?:\.\d+)?)\s*g"#)
    grab("satfat", #"saturated fat\D{0,10}(\d+(?:\.\d+)?)\s*g"#)
    grab("sodium", #"sodium\D{0,10}(\d+(?:\.\d+)?)\s*mg"#)
    grab("fiber", #"(?:dietary )?fiber\D{0,10}(\d+(?:\.\d+)?)\s*g"#)
    grab("protein", #"protein\D{0,10}(\d+(?:\.\d+)?)\s*g"#)
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
    @Environment(\.dismiss) private var dismiss

    private static let slots: [(String, String)] = [
        ("front", "Front of package"),
        ("ingredients", "Ingredient list"),
        ("nutrition", "Nutrition facts label"),
    ]

    // Per-serving nutrition entry (food products only). Field key ->
    // (label, OFF per-100g nutriment key; nil = the serving-size field).
    private static let nutritionFields: [(String, String, String?)] = [
        ("serving", "Serving size (g)", nil),
        ("calories", "Calories (kcal)", "energy-kcal_100g"),
        ("sugars", "Total sugars (g)", "sugars_100g"),
        ("satfat", "Saturated fat (g)", "saturated-fat_100g"),
        ("sodium", "Sodium (mg)", "sodium_100g"),
        ("fiber", "Fiber (g)", "fiber_100g"),
        ("protein", "Protein (g)", "proteins_100g"),
    ]

    // Nutrition facts only apply to food; other kinds skip the section
    // and the nutrition-label photo slot.
    private var slots: [(String, String)] {
        kind == .food ? Self.slots : Self.slots.filter { $0.0 != "nutrition" }
    }

    @State private var captured: [String: UIImage] = [:]
    @State private var pickingField: String?
    @State private var ocrText = ""
    @State private var ocrRan = false
    @State private var store = ""
    @State private var nutrition: [String: String] = [:]
    @State private var saving = false
    @State private var resultMessage: String?

    private var hasWork: Bool {
        !captured.isEmpty
            || !ocrText.trimmingCharacters(in: .whitespaces).isEmpty
            || !store.trimmingCharacters(in: .whitespaces).isEmpty
            || nutrition.values.contains {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Photograph the package, check the scanned ingredient list, then tap Save. Your contribution improves this product for every Simply user.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let message = resultMessage {
                        Text(message)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(message.hasPrefix("Saved")
                                ? Color.riskNone : Color.riskHigh)
                    }

                    ForEach(slots, id: \.0) { field, label in
                        slotCard(field: field, label: label)
                    }

                    if ocrRan {
                        Text(ocrText.isEmpty
                            ? "Couldn't read text from the ingredient photo — you can type the list manually."
                            : "Here's what the scan read from the label. Please check it against the package and fix any mistakes, then tap Save:")
                            .font(.subheadline)
                        TextEditor(text: $ocrText)
                            .frame(minHeight: 110)
                            .padding(6)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(.quaternary))
                    }

                    if kind == .food {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nutrition facts (per serving)")
                                .font(.subheadline.weight(.semibold))
                            Text("Optional — enter the values as printed on the label.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            nutritionField(Self.nutritionFields[0].0,
                                           Self.nutritionFields[0].1)
                            ForEach(pairedNutritionFields, id: \.0.0) { left, right in
                                HStack(alignment: .bottom, spacing: 12) {
                                    nutritionField(left.0, left.1)
                                    nutritionField(right.0, right.1)
                                }
                            }
                        }
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
            .navigationTitle("Improve this product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // The single save point — uploads photos + verified text
                    Button(saving ? "Saving…" : "Save") { saveAll() }
                        .bold()
                        .disabled(!hasWork || saving)
                }
            }
            .sheet(item: $pickingField) { field in
                CameraPicker { image in
                    captured[field] = image
                    if field == "ingredients" {
                        Task {
                            ocrText = extractIngredients(from: await recognizeText(in: image))
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
                        }
                    }
                }
            }
        }
    }

    private var pairedNutritionFields: [((String, String, String?), (String, String, String?))] {
        let rest = Array(Self.nutritionFields.dropFirst())
        return stride(from: 0, to: rest.count - 1, by: 2).map { (rest[$0], rest[$0 + 1]) }
    }

    private func nutritionField(_ key: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: Binding(
                get: { nutrition[key] ?? "" },
                set: { nutrition[key] = $0; resultMessage = nil }
            ))
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
        }
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
                    if field == "ingredients" { ocrText = ""; ocrRan = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.riskHigh)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func saveAll() {
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
            // Nutrition values are entered per serving; convert to per 100 g
            // using the serving grams. Without serving grams they can't be
            // converted, so they're skipped and the message says so.
            func numField(_ key: String) -> Double? {
                nutrition[key].flatMap {
                    Double($0.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: ",", with: "."))
                }
            }
            let servingG = numField("serving").flatMap { $0 > 0 ? $0 : nil }
            let perServing: [(String, Double)] = Self.nutritionFields.compactMap { key, _, offKey in
                guard let offKey, let value = numField(key) else { return nil }
                // OFF stores sodium in grams; the label prints mg
                return (offKey, key == "sodium" ? value / 1000 : value)
            }
            let nutritionSkipped = !perServing.isEmpty && servingG == nil
            var nutriments: [String: Double]?
            if let servingG, !perServing.isEmpty {
                nutriments = Dictionary(uniqueKeysWithValues: perServing.map {
                    ($0.0, ($0.1 / servingG * 100 * 1000).rounded() / 1000)
                })
            }
            let servingSizeText = servingG.map {
                $0 == $0.rounded(.down) ? "\(Int($0)) g" : "\($0) g"
            }
            var factsOk: Bool?
            if !ingredients.isEmpty || !storeName.isEmpty || servingG != nil {
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
                    servingSize: servingSizeText,
                    servingQuantity: servingG)
            }
            saving = false
            if !captured.isEmpty, okPhotos < captured.count {
                resultMessage = "Uploaded \(okPhotos) of \(captured.count) photos — check your connection and tap Save again."
            } else if factsOk == false {
                resultMessage = "Photos uploaded, but the product details didn't save — tap Save again."
            } else if okPhotos == 0, factsOk == nil, nutritionSkipped {
                resultMessage = "Nutrition facts need the serving size in grams — add it and tap Save again."
            } else if okPhotos == 0, factsOk == nil {
                resultMessage = "Nothing to save yet — take a photo first."
            } else {
                var parts: [String] = []
                if okPhotos > 0 { parts.append("\(okPhotos) photo\(okPhotos == 1 ? "" : "s")") }
                if factsOk == true {
                    if !ingredients.isEmpty { parts.append("the ingredient list") }
                    if nutriments != nil { parts.append("the nutrition facts") }
                    else if servingG != nil { parts.append("the serving size") }
                    if !storeName.isEmpty { parts.append("the store") }
                }
                resultMessage = "Saved \(parts.joined(separator: " + ")) — thank you! Your submission will appear once it's reviewed."
                    + (nutritionSkipped
                        ? " Nutrition facts weren't saved — add the serving size in grams and tap Save again."
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
