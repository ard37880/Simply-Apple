import SwiftUI
import SafariServices

// MARK: - Shared preference editor

struct PreferenceEditor: View {
    @EnvironmentObject var profile: ProfileStore
    var collapsible = false
    @State private var dietsExpanded = false
    @State private var allergensExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name (optional)", text: $profile.name)
                .textFieldStyle(.roundedBorder)

            section(title: "Diet preferences", count: profile.diets.count,
                    expanded: $dietsExpanded) {
                chipGrid(ProfileStore.dietOptions.map { ($0.key, $0.label) },
                         selected: profile.diets) { profile.toggleDiet($0) }
            }
            section(title: "Allergens to flag", count: profile.allergens.count,
                    expanded: $allergensExpanded) {
                chipGrid(ProfileStore.allergenOptions.map { ($0.key, $0.label) },
                         selected: profile.allergens) { profile.toggleAllergen($0) }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String, count: Int, expanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let label = title + (count > 0 ? "  (\(count) selected)" : "")
        if collapsible {
            DisclosureGroup(isExpanded: expanded) {
                content().padding(.top, 8)
            } label: {
                Text(label).font(.headline).foregroundStyle(.primary)
            }
            .padding(.top, 8)
        } else {
            Text(label).font(.headline).padding(.top, 8)
            content()
        }
    }

    private func chipGrid(
        _ options: [(String, String)], selected: Set<String>,
        toggle: @escaping (String) -> Void
    ) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.0) { key, label in
                Button {
                    toggle(key)
                } label: {
                    Text(label)
                        .font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            selected.contains(key)
                                ? Color.riskNone.opacity(0.18)
                                : Color(.secondarySystemBackground),
                            in: Capsule())
                        .overlay(Capsule().stroke(
                            selected.contains(key) ? Color.riskNone : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal wrapping layout for the preference chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews)
        -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var profile: ProfileStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome to Simply")
                    .font(.largeTitle.bold())
                    .padding(.top, 40)
                Text("Set up your profile so scans can flag what matters to you. Everything stays on this phone — no account, no cloud, nothing shared.")
                    .font(.body)

                PreferenceEditor()

                Button {
                    profile.onboarded = true
                } label: {
                    Text("Start scanning")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 24)

                Text("You can change all of this anytime from your profile.")
                    .font(.caption)
            }
            .padding(24)
        }
    }
}

// MARK: - Profile + donations

struct ProfileView: View {
    @EnvironmentObject var profile: ProfileStore
    @State private var donationAmount: Double = 12
    @State private var donationBusy = false
    @State private var donationError: String?
    @State private var checkoutUrl: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your profile lives only on this phone — nothing is uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PreferenceEditor(collapsible: true)

                donationCard
                    .padding(.top, 24)

                Text("Simply v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
            }
            .padding()
        }
        .navigationTitle(profile.name.isEmpty ? "Your profile" : profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $checkoutUrl) { url in
            SafariView(url: url)
        }
    }

    private var donationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Support Simply", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(Color.riskNone)
            Text("Simply is independent — no ads, no data selling, no sponsored scores. If it saves you from a bad label, consider chipping in. Every feature stays free either way.")
                .font(.subheadline)
            Text("$\(Int(donationAmount)) / year")
                .font(.title2.bold())
            Slider(value: $donationAmount, in: 12...108, step: 12)
            Button {
                startCheckout()
            } label: {
                if donationBusy {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Become a supporter — $\(Int(donationAmount))/year")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(donationBusy)
            if let error = donationError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("Secure checkout by Stripe; cancel anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.simplyYellow.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private func startCheckout() {
        donationBusy = true
        donationError = nil
        Task {
            defer { donationBusy = false }
            var request = URLRequest(
                url: ProductRepository.serverBase
                    .appendingPathComponent("api/v2/donate/checkout"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(
                withJSONObject: ["amount": Int(donationAmount)])
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urlString = json["url"] as? String,
                  let url = URL(string: urlString)
            else {
                donationError = "Couldn't start checkout — try again in a moment."
                return
            }
            checkoutUrl = url
        }
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}

/// In-app Stripe Checkout — card data stays with Stripe.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
