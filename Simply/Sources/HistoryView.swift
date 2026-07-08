import SwiftUI

struct HistoryView: View {
    let onProduct: (String) -> Void
    @EnvironmentObject var history: HistoryStore

    var body: some View {
        Group {
            if history.records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Nothing scanned yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                List {
                    ForEach(history.records) { record in
                        Button {
                            onProduct(record.barcode)
                        } label: {
                            row(record)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.simplyPaper)
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            history.delete(barcode: history.records[offset].barcode)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .simplyScreenBackground()
        .navigationTitle("Scan history")
        .toolbar {
            if !history.records.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { history.clear() }
                }
            }
        }
    }

    private func row(_ record: ScanRecord) -> some View {
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
        .padding(.vertical, 2)
    }
}
