import SwiftUI
import VisionKit

/// Live text capture, like the system camera's text mode: the recognized
/// text refreshes continuously while the camera hovers over the label, and
/// the user grabs it the moment it reads right — no photo, no retakes.
/// Mirrors the Android LiveTextCapture.
struct LiveTextCapture: View {
    let title: String
    let onText: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var liveText = ""

    private var available: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if available {
                    LiveTextRepresentable(onText: { liveText = $0 })
                } else {
                    Color.black
                    Text("Live text isn't available on this device — use the photo scan instead.")
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold))
                ScrollView {
                    Text(liveText.isEmpty ? "Point the camera at the text…" : liveText)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)
                    Button("Use this text") {
                        onText(liveText)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(liveText.isEmpty)
                }
            }
            .padding()
            .background(Color.simplyCard)
        }
    }
}

private struct LiveTextRepresentable: UIViewControllerRepresentable {
    let onText: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onText: (String) -> Void
        init(onText: @escaping (String) -> Void) { self.onText = onText }

        // Keep the last non-empty reading so the text survives the moment
        // the user lowers the phone to tap "Use this text".
        private func refresh(_ allItems: [RecognizedItem]) {
            let text = allItems.compactMap { item -> String? in
                if case .text(let recognized) = item { return recognized.transcript }
                return nil
            }.joined(separator: "\n")
            if !text.isEmpty { onText(text) }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]
        ) { refresh(allItems) }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]
        ) { refresh(allItems) }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]
        ) { refresh(allItems) }
    }
}
