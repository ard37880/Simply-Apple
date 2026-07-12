import SwiftUI

/// Text search against Open Food Facts, for finding products without
/// scanning. Mirrors Android's SearchScreen: debounced query, result rows
/// with a score badge, tap opens the product page.
struct SearchView: View {
    let onProduct: (String) -> Void

    private enum Phase {
        case idle
        case loading
        case results([ProductRepository.SearchResult])
        case empty
        case error
    }

    @State private var query = ""
    @State private var phase: Phase = .idle
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            switch phase {
            case .idle:
                placeholder(icon: "magnifyingglass",
                            text: "Search products by name.")
            case .loading:
                ProgressView()
            case .empty:
                placeholder(icon: "questionmark.circle",
                            text: "No matches. Try the barcode.")
            case .error:
                placeholder(icon: "wifi.exclamationmark",
                            text: "Couldn't search. Check your connection and try again.")
            case .results(let items):
                List(items) { item in
                    Button {
                        onProduct(item.barcode)
                    } label: {
                        row(item)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.simplyPaper)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .simplyScreenBackground()
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Product name")
        .autoFocusedSearch($searchFocused)
        .onAppear { searchFocused = true }
        .task(id: query) {
            let terms = query.trimmingCharacters(in: .whitespaces)
            guard terms.count >= 2 else {
                phase = .idle
                return
            }
            // Debounce: cancelled and restarted whenever the query changes.
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            phase = .loading
            let results = await ProductRepository.shared.searchProducts(query: terms)
            guard !Task.isCancelled else { return }
            switch results {
            case .none: phase = .error
            case .some(let items) where items.isEmpty: phase = .empty
            case .some(let items): phase = .results(items)
            }
        }
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
    }

    private func row(_ item: ProductRepository.SearchResult) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.imageUrl) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                if let brand = item.brand {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()

            Text(item.score.map(String.init) ?? "–")
                .font(.callout.bold())
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(item.band?.color ?? Color.gray, in: Circle())
        }
        .padding(.vertical, 2)
    }
}

private extension View {
    /// Focus the search field automatically where the API exists
    /// (iOS 18+); older versions fall back to a tap on the field.
    @ViewBuilder
    func autoFocusedSearch(_ focus: FocusState<Bool>.Binding) -> some View {
        if #available(iOS 18.0, *) {
            searchFocused(focus)
        } else {
            self
        }
    }
}
