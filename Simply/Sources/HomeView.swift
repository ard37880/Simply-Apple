import SwiftUI

/// Friendly landing screen — the app opens here, with scanning one tap away.
/// Mirrors the Android HomeScreen exactly (same copy, same structure).
struct HomeView: View {
    let onScan: () -> Void
    let onSearch: () -> Void
    let onHistory: () -> Void
    let onProfile: () -> Void
    let onProduct: (String) -> Void

    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var history: HistoryStore

    private var recent: [ScanRecord] { Array(history.records.prefix(5)) }

    // A fresh greeting each visit keeps the screen from going stale.
    @State private var greeting = [
        "Hi", "Hello", "Hey", "What's up", "Welcome back", "Good to see you",
    ].randomElement()!

    var body: some View {
        // Fixed header; only the recent-scans list scrolls. Profile lives
        // as an avatar button beside the greeting — nothing overlays the
        // list. Mirrors Android.
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                let name = profile.name.trimmingCharacters(in: .whitespaces)
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name.isEmpty ? "Welcome" : "\(greeting), \(name)")
                            .font(.largeTitle.bold())
                        Text("What are you checking today?")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    Spacer()
                    Button(action: onProfile) {
                        Group {
                            if name.isEmpty {
                                Image(systemName: "person.fill")
                            } else {
                                Text(name.prefix(1).uppercased())
                                    .font(.title3.bold())
                            }
                        }
                        .foregroundStyle(Color.riskNone)
                        .frame(width: 48, height: 48)
                        .background(Color.simplyCard, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Your profile")
                }

                Button(action: onScan) {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22))
                        Text("Scan a product")
                            .font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.top, 24)

                Button(action: onSearch) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                        Text("Search by name")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.bordered)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.top, 12)

                HStack {
                    Text("Recent scans")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if !recent.isEmpty {
                        Button("See all", action: onHistory)
                    }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 20)

            // The only scrollable region: the recent-scans list fills the
            // space below the fixed header, with nothing overlaid on it.
            ScrollView {
                Group {
                    if recent.isEmpty {
                        Text("Scan your first product to get started.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .background(Color.simplyCard,
                                        in: RoundedRectangle(cornerRadius: 16))
                            .padding(.top, 8)
                            .padding(.horizontal, 20)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(recent) { record in
                                Button {
                                    onProduct(record.barcode)
                                } label: {
                                    recentCard(record)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .simplyScreenBackground()
        .navigationTitle("Simply Pure")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func recentCard(_ record: ScanRecord) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: record.imageUrl.flatMap(URL.init(string:))) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.name).font(.body.weight(.medium)).lineLimit(1)
                    if record.hasEuBanned {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.riskHigh)
                    }
                }
                Text([record.brand, record.scannedAt.formatted(.relative(presentation: .named))]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()

            Text(record.score < 0 ? "–" : "\(record.score)")
                .font(.callout.bold())
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    record.score < 0 ? Color.gray
                        : ScoreBand.forScore(record.score).color,
                    in: Circle())
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.simplyCard,
                    in: RoundedRectangle(cornerRadius: 16))
    }
}
