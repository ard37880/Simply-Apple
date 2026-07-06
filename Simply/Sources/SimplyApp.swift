import SwiftUI

@main
struct SimplyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Placeholder root while the full UI is built out — proves the core
/// (models, scoring engine, repositories) compiles and runs.
struct RootView: View {
    @State private var barcode = ""
    @State private var status = "Enter a barcode to test the pipeline"

    var body: some View {
        VStack(spacing: 16) {
            Text("Simply")
                .font(.largeTitle.bold())
            TextField("Barcode", text: $barcode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            Button("Look up") {
                Task {
                    status = "Loading…"
                    switch await ProductRepository.shared.lookup(barcode: barcode) {
                    case .found(let product, let score):
                        status = "\(product.name): \(score.total.map(String.init) ?? "?")/100 \(score.band?.rawValue ?? "")"
                    case .notFound:
                        status = "Not found"
                    case .error(let message):
                        status = message
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            Text(status)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        .padding(.top, 60)
    }
}
