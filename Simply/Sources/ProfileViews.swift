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
            // Name edits stamp prefsEditedAt via setName so the sync merge
            // knows which device edited preferences last.
            TextField("Name (optional)", text: Binding(
                get: { profile.name },
                set: { profile.setName($0) }
            ))
            .textFieldStyle(.roundedBorder)

            Text("Preferences")
                .font(.headline)
                .padding(.top, 16)

            if locked {
                Label("Diet preferences, avoid lists, and allergen alerts are premium features. Unlock them from Support Simply Pure in the profile.",
                      systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    // Selecting preferences that premium would silently ignore reads as
    // the feature working when it is not; locked sections gray out and
    // say why instead.
    private var locked: Bool { Entitlements.shared.locked(.personalization) }

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
        lockableFlow {
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

    /// Grays out and disables the chip grid while premium is locked.
    private func lockableFlow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        FlowLayout(spacing: 8) { content() }
            .disabled(locked)
            .opacity(locked ? 0.45 : 1)
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
    // A short walkthrough of how the app works comes first; the profile
    // questions only appear once someone knows what they're setting up.
    @State private var walkthroughDone = false

    var body: some View {
        if !walkthroughDone {
            OnboardingWalkthrough(onFinished: { walkthroughDone = true })
        } else {
            onboardingForm
        }
    }

    private var onboardingForm: some View {
        // Just the name: preferences moved to the profile so a locked
        // premium wall never greets a brand-new user.
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome to Simply Pure")
                    .font(.largeTitle.bold())
                    .padding(.top, 40)
                Text("Everything stays on this phone: no account, no cloud, nothing shared.")
                    .font(.body)

                TextField("Name (optional)", text: Binding(
                    get: { profile.name },
                    set: { profile.setName($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .padding(.top, 8)

                Button {
                    profile.onboarded = true
                } label: {
                    Text("Start scanning")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 24)

                Text("Diet preferences, ingredients to avoid, and allergen alerts live in your profile. Tap the circle next to the greeting anytime to set them up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

// MARK: - Profile + donations

struct ProfileView: View {
    @EnvironmentObject var profile: ProfileStore
    // The gallery starts open when a theme is already the active
    // appearance, mirroring Android.
    @State private var themesExpanded =
        ProfileStore.shared.appearance.hasPrefix(appearanceThemePrefix)
    @State private var syncPaired = SyncEngine.shared.paired
    @State private var syncEnterCode = ""
    @State private var supporterUnlocked = Entitlements.shared.isSupporter
    @ObservedObject private var purchases = Purchases.shared
    @State private var purchasing = false
    @State private var tierIndex = 0.0
    @State private var celebrate = false
    @State private var confirmCancel = false
    @State private var cancelling = false
    @State private var cancelStatus: String?
    @State private var supporterCancelled = Entitlements.shared.isCancelled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your profile lives only on this phone. Nothing is uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Every approved submission fixed a product page for everyone,
                // so the tally gets a celebratory card rather than a stat row.
                // The count lives on this device (there are no accounts to tie
                // submissions to); it grows as the watcher learns of approvals.
                // Mirrors Android's helped-everyone card.
                let approvedFixes = SubmissionWatcher.approvedCount
                HStack(spacing: 14) {
                    Image("mascot_celebrating")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 76, height: 76)
                    VStack(alignment: .leading, spacing: 2) {
                        if approvedFixes > 0 {
                            HStack(alignment: .lastTextBaseline, spacing: 8) {
                                Text("\(approvedFixes)")
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundStyle(Color.simplyLink)
                                Text(approvedFixes == 1
                                    ? "time you've helped everyone"
                                    : "times you've helped everyone")
                                    .font(.subheadline.weight(.bold))
                            }
                            Text("Your fixes are out there right now, helping "
                                + "everyone who scans those products. Thank you!")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let impact = SubmissionWatcher.impactPoints
                            if impact > 0 {
                                Text("The community has scanned your products "
                                    + "\(impact) time\(impact == 1 ? "" : "s") "
                                    + "since your fixes went live.")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.simplyLink)
                                    .padding(.top, 2)
                            }
                        } else {
                            Text("Help everyone who scans")
                                .font(.headline)
                            Text("When a product fix you submit is approved, it "
                                + "goes live for every Simply Pure user, and "
                                + "your helped count grows right here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.simplyCard, in: RoundedRectangle(cornerRadius: 14))

                PreferenceEditor(collapsible: true)

                Text("Appearance")
                    .font(.headline)
                    .padding(.top, 24)
                // Themes sits in the row as a fourth mode; tapping it drops
                // the preset gallery down. Joins premium when the production
                // gates flip on, same as search.
                let themesAvailable = !Entitlements.shared.locked(.customThemes)
                appearanceSegments(themesAvailable: themesAvailable)
                if themesExpanded && !themesAvailable {
                    Label("Themes are a premium feature. Unlock them under Support Simply Pure below.",
                          systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                if themesAvailable && themesExpanded {
                    Text("Hand-tuned palettes that recolor the whole app. "
                        + "Scores keep their green, yellow and red.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    FlowLayout(spacing: 10) {
                        ForEach(themePresets) { preset in
                            let key = appearanceThemePrefix + preset.id
                            ThemeSwatch(
                                preset: preset,
                                selected: profile.appearance == key
                            ) {
                                profile.objectWillChange.send()
                                profile.appearance = key
                            }
                        }
                    }
                    .padding(.top, 10)
                }

                Text("Sync between devices")
                    .font(.headline)
                    .padding(.top, 24)
                syncSection

                Text("Alerts & location")
                    .font(.headline)
                    .padding(.top, 24)
                PermissionToggleRow(
                    title: "Alerts about products you scanned",
                    description: "Notifies you if a product you scanned is recalled "
                        + "(US FDA) or its score changes after a data or safety-rules "
                        + "update. Your scan list is sent to the Simply Pure server to "
                        + "check for recalls, nothing else.",
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
                    title: "Opt in for crowdsourcing",
                    description: "Everything community, one switch: after a scan "
                        + "you may get two quick questions (did you buy it, and does "
                        + "the label show a bioengineered disclosure), you'll see "
                        + "what other scanners chose once a product has enough "
                        + "answers, and store reports carry a coarse \"City, State\" "
                        + "so availability can roll out by region. Answers are "
                        + "anonymous counts, never tied to you.",
                    isOn: Binding(
                        get: { profile.crowdsourcing },
                        set: { on in
                            profile.crowdsourcing = on
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

                // Marketing version alone is ambiguous on iOS (many builds
                // share 1.9); the build number is what support needs.
                Text("Simply Pure v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0").\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0")")
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

    /// Light / Dark / System / Themes as one segmented row. Built from
    /// buttons rather than a segmented Picker because the Themes segment
    /// toggles the gallery open and closed on every tap, including taps
    /// while it is already selected, which a Picker cannot report.
    @ViewBuilder
    private var syncSection: some View {
        if !syncPaired {
            Text("Keep two devices in step with a pair code. Your data is "
                + "encrypted with the code before it leaves this phone, "
                + "and the code itself is never sent to us, so nobody "
                + "but your devices can read it. No account needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Create a pair code") {
                SyncEngine.shared.createCode()
                syncPaired = true
                Task { await SyncEngine.shared.syncNow(force: true) }
            }
            .buttonStyle(.borderedProminent)
            TextField("Have a code? Enter it", text: $syncEnterCode)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            if !syncEnterCode.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Join") {
                    if SyncEngine.shared.join(syncEnterCode) {
                        syncEnterCode = ""
                        syncPaired = true
                        Task { await SyncEngine.shared.syncNow(force: true) }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            if let code = SyncEngine.shared.currentCode {
                Text("Pair code: \(code)")
                    .font(.subheadline.weight(.bold))
            }
            Text("Syncing is on. Enter the code above on another device "
                + "and scans and preferences merge whenever either "
                + "device opens the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Sync now") {
                    Task { await SyncEngine.shared.syncNow(force: true) }
                }
                .buttonStyle(.borderedProminent)
                Button("Stop syncing") {
                    SyncEngine.shared.unpair()
                    syncPaired = false
                }
            }
        }
    }

    private func appearanceSegments(themesAvailable: Bool) -> some View {
        let themed = profile.appearance.hasPrefix(appearanceThemePrefix)
        return HStack(spacing: 2) {
            ForEach(Appearance.allCases) { option in
                segment(option.label,
                        selected: !themed && Appearance.from(profile.appearance) == option) {
                    themesExpanded = false
                    profile.objectWillChange.send()
                    profile.appearance = option.rawValue
                }
            }
            // Always visible so locked users learn it exists; the tap
            // shows the lock note instead of the gallery when locked.
            if true {
                segment(themesAvailable ? "Themes" : "Themes \u{1F512}".replacingOccurrences(of: " \u{1F512}", with: ""), selected: themed) {
                    themesExpanded.toggle()
                }
            }
        }
        .padding(2)
        .background(Color(UIColor.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 9))
    }

    private func segment(
        _ label: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(selected ? .medium : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selected ? Color.simplyCard : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    /// One price with a slider (the Yuka pattern): $11.99 by default, slide
    /// right for the voluntary higher tiers. Every amount unlocks the same
    /// features. Purchases go through StoreKit only: no external checkout
    /// links and no code entry in the iOS app (guideline 3.1.1).
    private func sliderTiers(prices: [String], buy: @escaping (Int) -> Void) -> some View {
        let idx = min(Int(tierIndex.rounded()), prices.count - 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(prices[idx])
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.simplyLink)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: idx)
                Text("per year")
                    .foregroundStyle(.secondary)
            }
            if prices.count > 1 {
                Slider(value: $tierIndex, in: 0...Double(prices.count - 1), step: 1)
                    .tint(Color.simplyLink)
                Text("Every amount unlocks the same features. Sliding higher is extra support for an independent app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                buy(idx)
            } label: {
                Text(purchasing ? "One moment" : "Become a supporter")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(purchasing)
            Text("Renews yearly until canceled in your App Store subscription settings. Cancel anytime; premium stays until the paid period ends.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var tierPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            if purchases.products.isEmpty {
                #if DEBUG
                // Debug-only static render for UI tests and review
                // screenshots; the simulator has no App Store to load real
                // products from. Compiled out of Release builds.
                if ProcessInfo.processInfo.arguments.contains("-previewTiers") {
                    sliderTiers(prices: ["$11.99", "$23.99", "$47.99"]) { _ in
                        celebrate = true
                    }
                } else {
                    loadingNote
                }
                #else
                loadingNote
                #endif
            } else {
                sliderTiers(prices: purchases.products.map(\.displayPrice)) { idx in
                    purchasing = true
                    Task {
                        if await purchases.purchase(purchases.products[idx]) {
                            celebrate = true
                        }
                        purchasing = false
                    }
                }
            }
            HStack(spacing: 16) {
                Button("Restore purchases") {
                    Task { await purchases.restore() }
                }
                Button("Terms") { openInBrowser("https://simplypure.studio86.dev/terms.html") }
                Button("Privacy") { openInBrowser("https://simplypure.studio86.dev/privacy.html") }
            }
            .font(.caption)
        }
    }

    private var loadingNote: some View {
        Text("Loading subscription options requires the App Store. Pull back in a moment if this doesn't fill in.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .task { await purchases.loadProducts() }
    }

    private var donationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Support Simply Pure", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(Color.simplyLink)
            Text("Simply Pure is independent: no ads, no data selling, no sponsored scores. Scanning and scores are free for everyone; supporters unlock the extras, like themes and diet filters, plus all future features.")
                .font(.subheadline)
            if purchases.hasActiveSubscription {
                if celebrate {
                    HStack {
                        Spacer()
                        Image("MascotCelebrate")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                            .transition(.scale.combined(with: .opacity))
                        Spacer()
                    }
                }
                Text(celebrate
                    ? "You're a supporter now. Thank you for keeping Simply Pure independent!"
                    : "Premium unlocked. Thank you for supporting Simply Pure!")
                    .font(.subheadline.weight(.bold))
                Button("Manage subscription") {
                    openInBrowser("https://apps.apple.com/account/subscriptions")
                }
                .font(.caption)
            } else if !supporterUnlocked {
                tierPicker
            } else {
                Text("Premium unlocked. Thank you for supporting Simply Pure!")
                    .font(.subheadline.weight(.bold))
                if let code = Entitlements.shared.supporterCode {
                    Text("Your code: \(code). It also works on devices paired with this one under Sync between devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if supporterCancelled {
                    let ends = Entitlements.shared.premiumEndsText
                    Text("Subscription canceled: it will not renew"
                        + (ends.isEmpty ? "" : ", and premium stays until \(ends)")
                        + ". Changed your mind? You can subscribe again below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    tierPicker
                } else if let cancelStatus {
                    Text(cancelStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if confirmCancel {
                        Text("Your subscription won't renew, and premium stays until the period you paid for ends.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(cancelling ? "Cancelling…"
                           : confirmCancel ? "Tap again to confirm cancellation"
                           : "Cancel subscription") {
                        if !confirmCancel {
                            confirmCancel = true
                        } else {
                            cancelling = true
                            Task {
                                if await Entitlements.shared.cancelSubscription() {
                                    supporterCancelled = true
                                } else {
                                    cancelStatus = "Couldn't cancel right now. Try again, or use the link in your Stripe receipt email."
                                }
                                cancelling = false
                                confirmCancel = false
                            }
                        }
                    }
                    .font(.caption)
                    .disabled(cancelling)
                }
            }
        }
        .padding()
        .background(Color.simplyYellow.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if celebrate {
                ConfettiView()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
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

/// One tappable theme tile: the preset's paper with its accent dot.
private struct ThemeSwatch: View {
    let preset: ThemePreset
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onTap) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(preset.paper)
                    .frame(width: 64, height: 64)
                    .overlay(Circle().fill(preset.accent).frame(width: 26, height: 26))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                        selected ? Color.simplyLink : Color.simplyHairline,
                        lineWidth: selected ? 3 : 1))
            }
            .buttonStyle(.plain)
            Text(preset.label)
                .font(.caption2)
        }
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

/// A one-shot confetti burst for the moment someone becomes a supporter.
/// Deterministic pseudo-random placement (no RNG, no timers): each piece
/// falls once and the whole layer fades out.
struct ConfettiView: View {
    @State private var fall = false

    private let colors: [Color] = [
        Color(red: 0.11, green: 0.56, blue: 0.24),
        Color(red: 1.00, green: 0.72, blue: 0.24),
        Color(red: 0.86, green: 0.27, blue: 0.45),
        Color(red: 0.31, green: 0.51, blue: 0.93),
        Color(red: 0.79, green: 0.61, blue: 0.95),
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<42, id: \.self) { i in
                let fx = CGFloat((i * 73) % 100) / 100
                let delay = Double((i * 37) % 100) / 220
                let size = CGFloat(6 + (i * 13) % 7)
                Rectangle()
                    .fill(colors[i % colors.count])
                    .frame(width: size, height: size * 0.62)
                    .rotationEffect(.degrees(Double((i * 61) % 360) + (fall ? 300 : 0)))
                    .position(x: fx * geo.size.width,
                              y: fall ? geo.size.height + 24 : -24)
                    .animation(.easeIn(duration: 1.7).delay(delay), value: fall)
            }
        }
        .allowsHitTesting(false)
        .opacity(fall ? 1 : 0.9)
        .onAppear { fall = true }
    }
}
