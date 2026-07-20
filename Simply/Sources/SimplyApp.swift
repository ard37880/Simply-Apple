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
                    // Server-driven feature flags and any regulatory update
                    // to the risk databases (applies next launch), then one
                    // recall check per app open (a no-op unless opted in, and
                    // a premium feature once the production gates flip).
                    await Entitlements.shared.refresh()
                    await RulesUpdater.refresh()
                    if !Entitlements.shared.locked(.recallAlerts) {
                        await RecallChecker.checkAndNotify()
                    }
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

    /// `--open-product <barcode>`: jump straight to a product page
    /// (used for automated screenshots). Parsed once, statically — RootView.init
    /// runs on every SimplyApp.body evaluation, so it must never write to
    /// ProfileStore there: the write publishes objectWillChange, which
    /// invalidates SimplyApp.body, which re-runs init, forever.
    private static let deepLinkBarcode: String? = {
        guard let index = CommandLine.arguments.firstIndex(of: "--open-product"),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return CommandLine.arguments[index + 1]
    }()

    init() {
        _ = Self.selftest
        _openBarcode = State(initialValue: Self.deepLinkBarcode)
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
        // A deep-link launch skips onboarding without persisting anything
        // during body evaluation; `onboarded` is written after the first
        // frame, in onAppear below.
        if !profile.onboarded && openBarcode == nil {
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
                .simplyToolbarBackground()
                .onAppear {
                    if let barcode = openBarcode {
                        if !profile.onboarded { profile.onboarded = true }
                        path.append(Route.product(barcode))
                        openBarcode = nil
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    // The scanner keeps the translucent system bar so the
                    // camera stays visible behind it.
                    if case .scanner = route {
                        destination(for: route)
                    } else {
                        destination(for: route)
                            .simplyToolbarBackground()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .scanner:
            ScannerView(
                onBarcode: { code in path.append(Route.product(code)) },
                onSearch: { path.append(Route.search) }
            )
            .navigationTitle("Scan a product")
            .navigationBarTitleDisplayMode(.inline)
        case .product(let barcode):
            ProductView(
                barcode: barcode,
                onProduct: { code in path.append(Route.product(code)) },
                // Rebuild the stack as home > scanner so repeated
                // scan-next loops never grow the path.
                onScanNext: { path = NavigationPath([Route.scanner]) }
            )
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
