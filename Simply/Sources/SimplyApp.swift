import SwiftUI

@main
struct SimplyApp: App {
    @StateObject private var profile = ProfileStore.shared
    @StateObject private var history = HistoryStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(profile)
                .environmentObject(history)
                .task {
                    // One recall check per app open; no-op unless opted in.
                    await RecallChecker.checkAndNotify()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var profile: ProfileStore
    @State private var path = NavigationPath()

    /// `--selftest` launch argument: verify the full pipeline (databases
    /// loaded, lookup, scoring) and print the result — used by automated
    /// simulator checks so a broken bundle can never ship silently again.
    private static let selftest: Void = {
        guard CommandLine.arguments.contains("--selftest") else { return }
        Task {
            switch await ProductRepository.shared.lookup(barcode: "048564071012") {
            case .found(let product, let score):
                let rated = product.additives.count
                let unrated = product.unratedAdditives.count
                print("SELFTEST: \(product.name) score=\(score.total.map(String.init) ?? "?") rated=\(rated) unrated=\(unrated) flagged=\(product.flaggedIngredients.count)")
                print(rated >= 5 ? "SELFTEST: PASS" : "SELFTEST: FAIL (databases not loading)")
            case .notFound: print("SELFTEST: FAIL not found")
            case .error(let message): print("SELFTEST: FAIL \(message)")
            }
        }
    }()

    init() {
        _ = Self.selftest
        // `--open-product <barcode>`: jump straight to a product page
        // (used for automated screenshots)
        if let index = CommandLine.arguments.firstIndex(of: "--open-product"),
           CommandLine.arguments.indices.contains(index + 1) {
            ProfileStore.shared.onboarded = true
            self._openBarcode = State(initialValue: CommandLine.arguments[index + 1])
        }
    }

    @State private var openBarcode: String?

    enum Route: Hashable {
        case scanner
        case product(String)
        case search
        case history
        case profile
    }

    var body: some View {
        content
            .tint(.riskNone)
            .preferredColorScheme(Appearance.from(profile.appearance).colorScheme)
    }

    @ViewBuilder
    private var content: some View {
        if !profile.onboarded {
            OnboardingView()
                .simplyScreenBackground()
        } else {
            NavigationStack(path: $path) {
                HomeView(
                    onScan: { path.append(Route.scanner) },
                    onSearch: { path.append(Route.search) },
                    onHistory: { path.append(Route.history) },
                    onProfile: { path.append(Route.profile) },
                    onProduct: { code in path.append(Route.product(code)) }
                )
                .onAppear {
                    if let barcode = openBarcode {
                        path.append(Route.product(barcode))
                        openBarcode = nil
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .scanner:
                        ScannerView(
                            onBarcode: { code in path.append(Route.product(code)) },
                            onSearch: { path.append(Route.search) }
                        )
                        .navigationTitle("Scan a product")
                        .navigationBarTitleDisplayMode(.inline)
                    case .product(let barcode):
                        ProductView(barcode: barcode) { code in
                            path.append(Route.product(code))
                        }
                    case .search:
                        SearchView { code in
                            path.append(Route.product(code))
                        }
                    case .history:
                        HistoryView { code in
                            path.append(Route.product(code))
                        }
                    case .profile:
                        ProfileView()
                    }
                }
            }
        }
    }
}
