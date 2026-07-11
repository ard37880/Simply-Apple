import SwiftUI
import UIKit
import UserNotifications

// MARK: - Shared preference editor

struct PreferenceEditor: View {
    @EnvironmentObject var profile: ProfileStore
    var collapsible = false
    @State private var dietsExpanded = false
    @State private var avoidsExpanded = false
    @State private var allergensExpanded = false

    var body: some View {
        // Diets and avoid-ingredients share the same stored set; they're
        // separate sections purely so actual diets don't drown in flags.
        let dietKeys = Set(ProfileStore.dietOptions.map(\.key))
        let avoidKeys = Set(ProfileStore.avoidOptions.map(\.key))
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name (optional)", text: $profile.name)
                .textFieldStyle(.roundedBorder)

            section(title: "Diet preferences",
                    count: profile.diets.intersection(dietKeys).count,
                    expanded: $dietsExpanded) {
                chipGrid(ProfileStore.dietOptions.map { ($0.key, $0.label) },
                         selected: profile.diets) { profile.toggleDiet($0) }
            }
            section(title: "Ingredients to avoid",
                    count: profile.diets.intersection(avoidKeys).count,
                    expanded: $avoidsExpanded) {
                chipGrid(ProfileStore.avoidOptions.map { ($0.key, $0.label) },
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
                                : Color.simplyCard,
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
    // Beta-build welcome, shown once before the profile setup on first
    // launch. Remove when the app leaves beta.
    @State private var betaWelcomeSeen = false

    var body: some View {
        if !betaWelcomeSeen {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("You're in the beta 🎉")
                        .font(.largeTitle.bold())
                        .padding(.top, 64)
                    Text("Thank you for joining the Simply Pure beta! You're helping shape the app before it goes public.")
                        .font(.body)
                    Text("Please send any and all feedback — bugs, ideas, confusing screens, anything — to hello@studio86.dev.")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.riskNone)
                    Button {
                        betaWelcomeSeen = true
                    } label: {
                        Text("Let's set things up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 24)
                }
                .padding(24)
            }
        } else {
            onboardingForm
        }
    }

    private var onboardingForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome to Simply Pure")
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your profile lives only on this phone — nothing is uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PreferenceEditor(collapsible: true)

                Text("Appearance")
                    .font(.headline)
                    .padding(.top, 24)
                Picker("Appearance", selection: Binding(
                    get: { Appearance.from(profile.appearance) },
                    set: { newValue in
                        profile.objectWillChange.send()
                        profile.appearance = newValue.rawValue
                    }
                )) {
                    ForEach(Appearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text("Alerts & location")
                    .font(.headline)
                    .padding(.top, 24)
                PermissionToggleRow(
                    title: "Recall alerts",
                    description: "Notifies you if a product you scanned is recalled "
                        + "(US FDA). Your scan list is sent to the Simply Pure server to "
                        + "check — nothing else.",
                    isOn: Binding(
                        get: { profile.recallAlerts },
                        set: { on in
                            profile.recallAlerts = on
                            if on {
                                UNUserNotificationCenter.current().requestAuthorization(
                                    options: [.alert, .sound]) { _, _ in }
                            }
                        }
                    )
                )
                PermissionToggleRow(
                    title: "Tag store reports with your area",
                    description: "Adds a coarse \"City, State\" to store submissions "
                        + "so availability can roll out by region. Used only when you "
                        + "submit, never stored otherwise.",
                    isOn: Binding(
                        get: { profile.locationTagging },
                        set: { on in
                            profile.locationTagging = on
                            if on { LocationTagger.shared.requestPermission() }
                        }
                    )
                )

                donationCard
                    .padding(.top, 24)

                Button("Suggest a feature", action: suggestFeature)
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.simplyLink)
                    .padding(.top, 16)

                HStack(spacing: 16) {
                    Button("Privacy policy") {
                        openInBrowser("https://simplypure.studio86.dev/privacy.html")
                    }
                    Button("Terms of use") {
                        openInBrowser("https://simplypure.studio86.dev/terms.html")
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.simplyLink)
                .padding(.top, 8)

                Text("Simply Pure v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (Beta)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding()
        }
        .simplyScreenBackground()
        .navigationTitle(profile.name.isEmpty ? "Your profile" : profile.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var donationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Support Simply Pure", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(Color.simplyLink)
            Text("Simply Pure is independent — no ads, no data selling, no sponsored scores. If it saves you from a bad label, consider chipping in. Every feature stays free either way.")
                .font(.subheadline)
            Button {
                openInBrowser("https://simplypure.studio86.dev/donate")
            } label: {
                Text("Support Simply Pure on our website")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Text("Donations happen on our website, with secure checkout by Stripe; cancel anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.simplyYellow.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Store rules: purchases can't happen in-app, so donations (and the
    /// legal pages) open on the website in the external browser.
    private func openInBrowser(_ url: String) {
        guard let url = URL(string: url) else { return }
        UIApplication.shared.open(url)
    }

    /// Opens the user's email app with a pre-filled feature-request draft.
    private func suggestFeature() {
        let subject = "Simply Pure Feature Request"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "mailto:hello@studio86.dev?subject=\(subject)") else { return }
        UIApplication.shared.open(url)
    }
}

struct PermissionToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
