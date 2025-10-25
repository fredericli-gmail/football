import UIKit
import CoreImage

final class ScoreboardRenderer {
    private let state: ScoreboardState
    private let fontCache = FontCache()
    
    init(state: ScoreboardState) {
        self.state = state
    }
    
    func makeOverlay(for size: CGSize) -> CIImage? {
        let overlayWidth = min(size.width * 0.08, 210)
        let overlayHeight = overlayWidth * 0.38
        let overlaySize = CGSize(width: overlayWidth, height: overlayHeight)
        let marginX = max(size.width * 0.02, 32)
        let topMargin = max(size.height * 0.09, 60)
        let originY = size.height - overlayHeight - topMargin
        let origin = CGPoint(x: marginX, y: originY)
        guard let cgImage = renderScoreboard(size: overlaySize) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        return ciImage.transformed(by: .init(translationX: origin.x, y: origin.y))
    }
    
    private func renderScoreboard(size: CGSize) -> CGImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            drawBackground(in: ctx.cgContext, size: size)
            drawContent(in: ctx.cgContext, size: size)
        }
        return image.cgImage
    }
    
    private func drawBackground(in context: CGContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: size.height * 0.2)
        context.setFillColor(UIColor.black.withAlphaComponent(0.65).cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
    }
    
    private func drawContent(in context: CGContext, size: CGSize) {
        let padding = size.height * 0.08
        let columnWidth = (size.width - padding * 4.5) / 3
        let blockHeight = size.height - padding * 2
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: fontCache.font(ofSize: blockHeight * 0.22, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        let scoreFont = fontCache.monospaced(ofSize: blockHeight * 0.55)
        let setFont = fontCache.monospaced(ofSize: blockHeight * 0.45)
        
        let homeRect = CGRect(x: padding, y: padding, width: columnWidth, height: blockHeight)
        let setRect = CGRect(x: padding * 2.5 + columnWidth, y: padding, width: columnWidth * 0.8, height: blockHeight)
        let awayRect = CGRect(x: padding * 4 + columnWidth * 2, y: padding, width: columnWidth, height: blockHeight)
        
        drawTeamBlock(context: context, rect: homeRect, name: state.homeTeamName, score: state.homeScore, color: UIColor.systemBlue, nameAttributes: nameAttributes, scoreFont: scoreFont)
        drawSetBlock(context: context, rect: setRect, font: setFont)
        drawTeamBlock(context: context, rect: awayRect, name: state.awayTeamName, score: state.awayScore, color: UIColor.systemGreen, nameAttributes: nameAttributes, scoreFont: scoreFont)
    }
    
    private func drawTeamBlock(context: CGContext, rect: CGRect, name: String, score: Int, color: UIColor, nameAttributes: [NSAttributedString.Key: Any], scoreFont: UIFont) {
        let nameRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.3)
        NSAttributedString(string: name, attributes: nameAttributes).draw(in: nameRect)
        let scoreRect = CGRect(x: rect.minX, y: nameRect.maxY + rect.height * 0.05, width: rect.width, height: rect.height * 0.65)
        let scorePath = UIBezierPath(roundedRect: scoreRect, cornerRadius: rect.height * 0.15)
        context.setFillColor(color.cgColor)
        context.addPath(scorePath.cgPath)
        context.fillPath()
        let scoreString = NSAttributedString(string: String(format: "%02d", score), attributes: [
            .font: scoreFont,
            .foregroundColor: UIColor.white
        ])
        let scoreSize = scoreString.size()
        let point = CGPoint(x: scoreRect.midX - scoreSize.width / 2, y: scoreRect.midY - scoreSize.height / 2)
        scoreString.draw(at: point)
    }
    
    private func drawSetBlock(context: CGContext, rect: CGRect, font: UIFont) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height * 0.2)
        context.setFillColor(UIColor.darkGray.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        let setString = NSAttributedString(string: String(state.currentSet), attributes: [
            .font: font,
            .foregroundColor: UIColor.white
        ])
        let setSize = setString.size()
        let setPoint = CGPoint(x: rect.midX - setSize.width / 2, y: rect.midY - setSize.height / 2 - rect.height * 0.1)
        setString.draw(at: setPoint)
        let label = NSAttributedString(string: "Set", attributes: [
            .font: fontCache.font(ofSize: rect.height * 0.18, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.8)
        ])
        let labelSize = label.size()
        let labelPoint = CGPoint(x: rect.midX - labelSize.width / 2, y: rect.maxY - labelSize.height - rect.height * 0.08)
        label.draw(at: labelPoint)
    }
}

private final class FontCache {
    private var cache: [String: UIFont] = [:]
    
    func font(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let key = "system-\(size)-\(weight.rawValue)"
        if let font = cache[key] { return font }
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        cache[key] = font
        return font
    }
    
    func monospaced(ofSize size: CGFloat) -> UIFont {
        let key = "mono-\(size)"
        if let font = cache[key] { return font }
        let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
        cache[key] = font
        return font
    }
}
