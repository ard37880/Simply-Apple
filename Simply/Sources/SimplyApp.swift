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
        }
    }
}

struct RootView: View {
    @EnvironmentObject var profile: ProfileStore
    @State private var path = NavigationPath()

    enum Route: Hashable {
        case product(String)
        case history
        case profile
    }

    var body: some View {
        if !profile.onboarded {
            OnboardingView()
        } else {
            NavigationStack(path: $path) {
                ScannerView { code in
                    path.append(Route.product(code))
                }
                .navigationTitle("Simply")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { path.append(Route.history) } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button { path.append(Route.profile) } label: {
                            Image(systemName: "person.circle")
                        }
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .product(let barcode):
                        ProductView(barcode: barcode) { code in
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
