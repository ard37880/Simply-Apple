import SwiftUI
import UserNotifications

/// iOS drops local notifications posted while the app is in the foreground
/// unless a delegate opts in to presenting them; our approval, recall, and
/// score-change checks all run right at launch, in the foreground.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

@main
struct SimplyApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    @StateObject private var profile = ProfileStore.shared
    @StateObject private var history = HistoryStore.shared

    var body: some Scene {
        WindowGroup {
            Group {
                // The beta-wide force-update lever: when the server says
                // this build is below the required minimum, the app is a
                // single update screen. The value lands with the once-per-
                // launch config refresh below (which still runs while
                // blocked, so lowering the requirement un-blocks too), and
                // a block takes effect on the launch after the flip.
                if Entitlements.shared.requiredBuild > Entitlements.currentBuildNumber {
                    UpdateRequiredView()
                } else {
                    RootView()
                }
            }
                .environmentObject(profile)
                .environmentObject(history)
                .task {
                    // Decide grandfathering BEFORE the first config
                    // refresh can ever flip the gates flag on this device.
                    Entitlements.shared.grandfatherExistingInstall(
                        alreadyOnboarded: ProfileStore.shared.onboarded)
                    // Server-driven feature flags and any regulatory update
                    // to the risk databases (applies next launch), then one
                    // recall check per app open (a no-op unless opted in, and
                    // a premium feature once the production gates flip).
                    await Entitlements.shared.refresh()
                    await RulesUpdater.refresh()
                    // Did anything this device submitted get approved?
                    await SubmissionWatcher.checkAndNotify()
                    if !Entitlements.shared.locked(.recallAlerts) {
                        await RecallChecker.checkAndNotify()
                        // Same opt-in covers score-change alerts; the
                        // checker throttles itself.
                        await ScoreChangeChecker.checkAndNotify()
                    }
                }
        }
    }
}

/// Full-screen stop shown when the server's required minimum build is
/// newer than this one. Beta builds always come from TestFlight, so the
/// button leads there.
struct UpdateRequiredView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image("mascot_waving")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
            Text("Time for an update")
                .font(.title2.bold())
                .padding(.top, 20)
            Text("This version of Simply Pure is too old to keep going. "
                + "Grab the newest one in TestFlight and pick up right where "
                + "you left off; your history and profile stay on this phone.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            Button("Open TestFlight") {
                if let url = URL(string: "https://testflight.apple.com/join/hwQFC2Gh") {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 22)
        }
        .padding(32)
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
            // A theme preset recolors the global tint along with the
            // surfaces; scores and risk dots keep their own colors.
            .tint(presetFor(profile.appearance)?.accent ?? .riskNone)
            .preferredColorScheme(Appearance.colorScheme(for: profile.appearance))
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
