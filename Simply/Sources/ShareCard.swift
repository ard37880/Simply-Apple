import SwiftUI
import UIKit

/// Renders a shareable score card (1080x1350 PNG) for a scored product and
/// hands it to the system share sheet. Drawn with UIGraphicsImageRenderer at
/// a fixed pixel size so the output is identical regardless of screen size
/// or theme, and matches the Android card's layout.
enum ShareCard {

    private static let width: CGFloat = 1080
    private static let height: CGFloat = 1350

    /// A rendered card, Identifiable so the share sheet can present on it.
    struct Rendered: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    static func render(product: Product, score: ScoreResult) async -> Rendered {
        let photo = await loadPhoto(product.imageUrl)
        return Rendered(image: draw(product: product, score: score, photo: photo))
    }

    private static func draw(product: Product, score: ScoreResult, photo: UIImage?) -> UIImage {
        let total = score.displayTotal ?? 0
        let band = score.displayBand ?? .bad
        let bandColor: UIColor
        switch band {
        case .excellent: bandColor = UIColor(shareRGB: 0x1B8E3E)
        case .good: bandColor = UIColor(shareRGB: 0x7CB92C)
        case .poor: bandColor = UIColor(shareRGB: 0xF2A93B)
        case .bad: bandColor = UIColor(shareRGB: 0xE63E32)
        }
        let ink = UIColor(shareRGB: 0x1C1B1A)
        let gray = UIColor(shareRGB: 0x7A756E)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let ctx = context.cgContext

            // Pastel wash of the band color over warm cream.
            blend(base: UIColor(shareRGB: 0xFDF6EC), tint: bandColor, amount: 0.10).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // White card.
            let card = CGRect(x: 48, y: 48, width: width - 96, height: height - 96)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: card, cornerRadius: 48).fill()

            var y: CGFloat = 128

            // Product photo, when one loads in time.
            if let photo {
                let side: CGFloat = 360
                let dst = CGRect(x: (width - side) / 2, y: y, width: side, height: side)
                ctx.saveGState()
                UIBezierPath(roundedRect: dst, cornerRadius: 36).addClip()
                drawCenterCropped(photo, in: dst)
                ctx.restoreGState()
                y += side + 56
            } else {
                y += 40
            }

            // Name and brand, centered, name on up to two lines.
            let nameFont = UIFont.boldSystemFont(ofSize: 60)
            for line in wrap(product.name, font: nameFont, maxWidth: card.width - 120, maxLines: 2) {
                drawCentered(line, font: nameFont, color: ink, baselineY: y + 52)
                y += 74
            }
            if let brand = product.brand,
               !brand.trimmingCharacters(in: .whitespaces).isEmpty {
                let brandFont = UIFont.systemFont(ofSize: 42)
                drawCentered(ellipsize(brand, font: brandFont, maxWidth: card.width - 120),
                             font: brandFont, color: gray, baselineY: y + 40)
                y += 66
            }
            y += 30

            // Score ring with the mascot alongside.
            let ringSize: CGFloat = 430
            let mascotName = total >= 75 ? "mascot_celebrating"
                : total >= 50 ? "mascot_waving"
                : "mascot_surprised"
            let mascot = UIImage(named: mascotName)
            let mascotW: CGFloat = 230
            let groupW = ringSize + 40 + mascotW
            let ringLeft = (width - groupW) / 2
            let ringRect = CGRect(x: ringLeft, y: y, width: ringSize, height: ringSize)

            let arcRect = ringRect.insetBy(dx: 30, dy: 30)
            let arcCenter = CGPoint(x: arcRect.midX, y: arcRect.midY)
            func strokeArc(fraction: CGFloat, color: UIColor) {
                let path = UIBezierPath(
                    arcCenter: arcCenter, radius: arcRect.width / 2,
                    startAngle: -.pi / 2,
                    endAngle: -.pi / 2 + 2 * .pi * fraction,
                    clockwise: true)
                path.lineWidth = 46
                path.lineCapStyle = .round
                color.setStroke()
                path.stroke()
            }
            strokeArc(fraction: 1, color: bandColor.withAlphaComponent(0.16))
            if total > 0 { strokeArc(fraction: CGFloat(total) / 100, color: bandColor) }

            drawCentered("\(total)", font: .boldSystemFont(ofSize: 150), color: ink,
                         baselineY: ringRect.midY + 32, centerX: ringRect.midX)
            drawCentered("out of 100", font: .systemFont(ofSize: 40), color: gray,
                         baselineY: ringRect.midY + 92, centerX: ringRect.midX)

            // Mascot to the right of the ring, feet on the ring's baseline.
            if let mascot, mascot.size.width > 0 {
                let mh = mascotW * mascot.size.height / mascot.size.width
                mascot.draw(in: CGRect(x: ringRect.maxX + 40, y: ringRect.maxY - mh,
                                       width: mascotW, height: mh))
            }
            y += ringSize + 74

            // Band label under the ring, in the band color.
            drawCentered(score.displayLabel, font: .boldSystemFont(ofSize: 58),
                         color: bandColor, baselineY: y)
            y += 54

            // Honest note when the shown score is personalized.
            if let personalized = score.personalized, let standard = score.total,
               personalized != standard {
                drawCentered("Personalized score. Standard: \(standard)",
                             font: .systemFont(ofSize: 36), color: gray, baselineY: y + 8)
            }

            // Footer pinned to the card bottom.
            drawCentered("Scanned with Simply Pure", font: .boldSystemFont(ofSize: 40),
                         color: ink, baselineY: card.maxY - 130)
            drawCentered("simplypure.studio86.dev", font: .systemFont(ofSize: 38),
                         color: UIColor(shareRGB: 0x1B8E3E), baselineY: card.maxY - 76)
        }
    }

    private static func loadPhoto(_ url: URL?) async -> UIImage? {
        guard let url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
        else { return nil }
        return UIImage(data: data)
    }

    /// Draws the image center-cropped into the destination rectangle.
    private static func drawCenterCropped(_ image: UIImage, in dst: CGRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(dst.width / image.size.width, dst.height / image.size.height)
        let w = image.size.width * scale
        let h = image.size.height * scale
        image.draw(in: CGRect(x: dst.midX - w / 2, y: dst.midY - h / 2, width: w, height: h))
    }

    /// Draws text centered on `centerX` with its baseline at `baselineY`,
    /// matching the Android canvas text placement.
    private static func drawCentered(
        _ text: String, font: UIFont, color: UIColor,
        baselineY: CGFloat, centerX: CGFloat = width / 2
    ) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let textWidth = (text as NSString).size(withAttributes: attributes).width
        (text as NSString).draw(
            at: CGPoint(x: centerX - textWidth / 2, y: baselineY - font.ascender),
            withAttributes: attributes)
    }

    private static func measure(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func wrap(
        _ text: String, font: UIFont, maxWidth: CGFloat, maxLines: Int
    ) -> [String] {
        let words = text.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if measure(candidate, font: font) <= maxWidth {
                current = candidate
            } else {
                if !current.isEmpty { lines.append(current) }
                current = word
                if lines.count == maxLines - 1 { break }
            }
        }
        if !current.isEmpty && lines.count < maxLines { lines.append(current) }
        if lines.count == maxLines && words.joined(separator: " ") != lines.joined(separator: " ") {
            lines[maxLines - 1] = ellipsize(lines[maxLines - 1], font: font, maxWidth: maxWidth)
        }
        return lines
    }

    private static func ellipsize(_ text: String, font: UIFont, maxWidth: CGFloat) -> String {
        if measure(text, font: font) <= maxWidth { return text }
        var t = text
        while !t.isEmpty && measure(t + "…", font: font) > maxWidth {
            t.removeLast()
        }
        return t + "…"
    }

    private static func blend(base: UIColor, tint: UIColor, amount: CGFloat) -> UIColor {
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        tint.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        func ch(_ b: CGFloat, _ t: CGFloat) -> CGFloat { b + (t - b) * amount }
        return UIColor(red: ch(br, tr), green: ch(bg, tg), blue: ch(bb, tb), alpha: 1)
    }
}

private extension UIColor {
    convenience init(shareRGB rgb: Int) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}

/// System share sheet for the rendered card image.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
