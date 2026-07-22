import SwiftUI

// MARK: - Onboarding walkthrough

/// One walkthrough page: its pastel backdrop, ink, and content.
private struct WalkPage {
    let top: Color
    let bottom: Color
    let ink: Color
    let accent: Color
    let headline: String
    let body: String
}

private let walkPages: [WalkPage] = [
    WalkPage(
        top: Color(rgb: 0xDFF3E4), bottom: Color(rgb: 0xF7F3E8),
        ink: Color(rgb: 0x12271C), accent: Color(rgb: 0x1B5E20),
        headline: "Scan it. Know it.",
        body: "Point at any barcode and get one honest score, 0 to 100, "
            + "in seconds. Food, personal care, pet food, household."),
    WalkPage(
        top: Color(rgb: 0xD9E9F6), bottom: Color(rgb: 0xF2F6F9),
        ink: Color(rgb: 0x14232D), accent: Color(rgb: 0x0E5A8A),
        headline: "Point at the barcode",
        body: "Tap Scan a product and hold your camera up to any "
            + "barcode. It reads instantly. No barcode in reach? Type the "
            + "number or search by name."),
    WalkPage(
        top: Color(rgb: 0xFCE4D6), bottom: Color(rgb: 0xFDF4EE),
        ink: Color(rgb: 0x2F1E12), accent: Color(rgb: 0xB84A21),
        headline: "Read the result",
        body: "The ring is the verdict and the rows are the reasons. "
            + "Tap any row to see the details, doses, and who restricts "
            + "what. Scan next keeps you moving down the aisle. When "
            + "something scores low, a cleaner same-aisle pick appears "
            + "underneath."),
    WalkPage(
        top: Color(rgb: 0xE7DEF6), bottom: Color(rgb: 0xF5F2FA),
        ink: Color(rgb: 0x221B33), accent: Color(rgb: 0x6247AA),
        headline: "Make it yours",
        body: "Diets, allergens, ingredients to avoid, and themes to "
            + "match your vibe. Pair another device with one code and "
            + "your scans follow you. Your data stays on your devices, "
            + "with no account and no ads. Change any of it later from "
            + "your profile."),
]

/// Swipeable how-it-works tour shown before the profile questions.
struct OnboardingWalkthrough: View {
    var onFinished: () -> Void
    @State private var page = 0

    var body: some View {
        let current = walkPages[page]
        ZStack {
            LinearGradient(colors: [current.top, current.bottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(walkPages.indices, id: \.self) { index in
                    pageContent(walkPages[index], index: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Dots, skip, and the pager button pinned to the bottom.
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(walkPages.indices, id: \.self) { i in
                        Circle()
                            .fill(i == page ? current.accent : current.ink.opacity(0.2))
                            .frame(width: i == page ? 10 : 8,
                                   height: i == page ? 10 : 8)
                    }
                }
                let last = page == walkPages.count - 1
                Button {
                    if last { onFinished() } else { withAnimation { page += 1 } }
                } label: {
                    Text(last ? "Set me up" : "Next")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(current.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                Button(action: onFinished) {
                    Text(last ? " " : "Skip the tour")
                        .foregroundStyle(current.ink.opacity(0.55))
                }
                .buttonStyle(.plain)
                .frame(height: 40)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .animation(.easeInOut(duration: 0.25), value: page)
    }

    private func pageContent(_ p: WalkPage, index: Int) -> some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ZStack {
                    switch index {
                    case 0: ScoreRingArt()
                    case 1: ScannerArt()
                    case 2: ResultArt(page: p)
                    default: PersonalizeArt(page: p)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: geo.size.height * 0.55)
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.headline)
                        .font(.largeTitle.bold())
                        .foregroundStyle(p.ink)
                    Text(p.body)
                        .font(.body)
                        .foregroundStyle(p.ink.opacity(0.75))
                        .padding(.top, 12)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 28)
        }
    }
}

/// Page 1: the score ring, the app's signature moment.
private struct ScoreRingArt: View {
    var body: some View {
        VStack(spacing: 12) {
            Image("mascot_waving")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
            ring
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color(rgb: 0x1B5E20).opacity(Double(0x22) / 255),
                        style: StrokeStyle(lineWidth: 22, lineCap: .round))
            Circle()
                .trim(from: 0, to: 313.0 / 360.0)
                .stroke(Color.riskNone,
                        style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("87")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Color(rgb: 0x12271C))
                Text("No concerns")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.riskNone)
            }
        }
        .frame(width: 190, height: 190)
    }
}

/// Page 2: the scanner viewport with a barcode in the frame.
private struct ScannerArt: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color(rgb: 0x17251B))
                    .frame(width: 240, height: 280)
                barcodeLabel
                cornerBrackets
                    .frame(width: 190, height: 136)
            }
            Text("Groceries, shampoo, dog food, dish soap")
                .font(.caption)
                .foregroundStyle(Color(rgb: 0x14232D))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                .offset(y: 16)
        }
    }

    private var barcodeLabel: some View {
        Canvas { context, size in
            // Scale the bar pattern to span the whole label.
            let pattern: [CGFloat] = [3, 6, 3, 9, 4, 3, 7, 3, 5, 8, 3, 6, 4, 3, 8, 5]
            let gap: CGFloat = 4
            let units = pattern.reduce(0, +) + gap * CGFloat(pattern.count - 1)
            let scale = size.width / units
            var x: CGFloat = 0
            for barWidth in pattern {
                context.fill(
                    Path(CGRect(x: x, y: 0, width: barWidth * scale, height: size.height)),
                    with: .color(Color(rgb: 0x17251B)))
                x += (barWidth + gap) * scale
            }
        }
        .frame(width: 108, height: 44)
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
    }

    private var cornerBrackets: some View {
        Canvas { context, size in
            let corner: CGFloat = 26
            let w = size.width
            let h = size.height
            var path = Path()
            path.move(to: CGPoint(x: 0, y: corner))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: corner, y: 0))
            path.move(to: CGPoint(x: w - corner, y: 0))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w, y: corner))
            path.move(to: CGPoint(x: w, y: h - corner))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: w - corner, y: h))
            path.move(to: CGPoint(x: corner, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: 0, y: h - corner))
            context.stroke(path, with: .color(.white),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct BreakdownRow: View {
    let dot: Color
    let title: String
    let detail: String
    let ink: Color

    var body: some View {
        HStack(spacing: 0) {
            Circle().fill(dot).frame(width: 12, height: 12)
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(ink)
                .padding(.leading, 12)
            Spacer()
            Text(detail)
                .foregroundStyle(ink.opacity(0.6))
        }
    }
}

/// Page 3: a miniature product page with the parts labeled.
private struct ResultArt: View {
    let page: WalkPage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(rgb: 0xF3E4D8))
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(page.ink.opacity(0.25))
                        .frame(width: 110, height: 10)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(page.ink.opacity(0.15))
                        .frame(width: 70, height: 8)
                }
                .padding(.leading, 10)
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.riskModerate.opacity(Double(0x33) / 255),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    Circle()
                        .trim(from: 0, to: 176.0 / 360.0)
                        .stroke(Color.riskModerate,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("49")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(rgb: 0x9D620A))
                }
                .frame(width: 46, height: 46)
            }
            Spacer().frame(height: 16)
            BreakdownRow(dot: .riskLimited, title: "Additives", detail: "6 to watch", ink: page.ink)
            Spacer().frame(height: 12)
            BreakdownRow(dot: .riskHigh, title: "Sodium", detail: "Very salty", ink: page.ink)
            Spacer().frame(height: 12)
            BreakdownRow(dot: .riskNone, title: "Sugar", detail: "Low sugar", ink: page.ink)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .topTrailing) {
            CalloutChip(label: "The verdict", page: page)
                .offset(x: 6, y: -14)
        }
        .overlay(alignment: .bottomLeading) {
            CalloutChip(label: "Tap a row for details", page: page)
                .offset(x: 10, y: 14)
        }
    }
}

private struct CalloutChip: View {
    let label: String
    let page: WalkPage

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(page.accent, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }
}

/// Page 4: theme dots and preference chips.
private struct PersonalizeArt: View {
    let page: WalkPage

    var body: some View {
        VStack(spacing: 0) {
            Image("mascot_celebrating")
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
                .padding(.bottom, 16)
            HStack(spacing: 14) {
                ForEach([0x0E5A8A, 0xB2124F, 0x6247AA, 0x63A4FF, 0x3FCF8C], id: \.self) { rgb in
                    Circle()
                        .fill(Color(rgb: UInt32(rgb)))
                        .frame(width: 34, height: 34)
                }
            }
            Spacer().frame(height: 20)
            HStack(spacing: 10) {
                PrefChip(label: "Vegan", page: page)
                PrefChip(label: "No gluten", page: page)
                PrefChip(label: "No GMOs", page: page)
            }
            Spacer().frame(height: 10)
            HStack(spacing: 10) {
                PrefChip(label: "Low sodium", page: page)
                PrefChip(label: "No dyes", page: page)
            }
        }
    }
}

private struct PrefChip: View {
    let label: String
    let page: WalkPage

    var body: some View {
        Text(label)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(page.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.85), in: Capsule())
    }
}
