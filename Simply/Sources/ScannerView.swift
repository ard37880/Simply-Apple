import SwiftUI
import VisionKit

/// Live barcode scanner built on Apple's DataScanner (iOS 16+).
/// Falls back to manual entry on the simulator or unsupported devices.
struct ScannerView: View {
    let onBarcode: (String) -> Void
    let onSearch: () -> Void
    @State private var manualEntry = false
    @State private var manualCode = ""
    @State private var scannerAvailable =
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    // Returning from a product page, the same package is usually still in
    // frame; mute that barcode briefly so back means "scan the next item"
    // instead of bouncing straight back to the page just left. Holding the
    // same product in frame past the pause deliberately rescans it.
    @State private var appearedAt = Date.distantPast
    @State private var lastViewedCode: String?

    var body: some View {
        ZStack {
            if scannerAvailable {
                BarcodeScannerRepresentable { code in
                    if code == lastViewedCode,
                       Date().timeIntervalSince(appearedAt) < 4 { return }
                    lastViewedCode = code
                    onBarcode(code)
                }
                .ignoresSafeArea()

                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.9), lineWidth: 3)
                    .frame(maxWidth: 300, maxHeight: 190)

                VStack {
                    Spacer()
                    Text("Point at a product barcode")
                        .foregroundStyle(.white)
                        .padding(.bottom, 90)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("Camera scanning isn't available here.\nEnter a barcode instead.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Enter barcode") { manualEntry = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Search joins premium when the production gates flip on.
                if !Entitlements.shared.locked(.search) {
                    Button {
                        onSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    manualEntry = true
                } label: {
                    Image(systemName: "keyboard")
                }
            }
        }
        .onAppear { appearedAt = Date() }
        .alert("Enter barcode", isPresented: $manualEntry) {
            TextField("UPC / EAN number", text: $manualCode)
                .keyboardType(.numberPad)
            Button("Look up") {
                let code = manualCode.filter(\.isNumber)
                if (8...14).contains(code.count) { onBarcode(code) }
                manualCode = ""
            }
            Button("Cancel", role: .cancel) { manualCode = "" }
        }
    }
}

private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onBarcode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .fast,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onBarcode: onBarcode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onBarcode: (String) -> Void
        private var lastCode: String?
        private var lastTime = Date.distantPast

        init(onBarcode: @escaping (String) -> Void) { self.onBarcode = onBarcode }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let value = barcode.payloadStringValue,
                   (8...14).contains(value.count),
                   value.allSatisfy(\.isNumber) {
                    // Debounce repeat reads of the same code
                    if value == lastCode, Date().timeIntervalSince(lastTime) < 3 { continue }
                    lastCode = value
                    lastTime = Date()
                    onBarcode(value)
                    return
                }
            }
        }
    }
}
