import Core
import UIKit

extension PickupChannel {
    var localizedName: String {
        switch self {
        case .duoduo:
            String(localized: "Duoduo Station")
        case .yixiaoji:
            String(localized: "Yixiaoji")
        case .cainiao:
            String(localized: "Cainiao")
        case .sfExpress:
            String(localized: "SF Express")
        case .jd:
            String(localized: "JD")
        case .other:
            String(localized: "Other")
        }
    }

    var symbolName: String {
        switch self {
        case .duoduo:
            "storefront"
        case .yixiaoji:
            "cabinet"
        case .cainiao:
            "bird"
        case .sfExpress:
            "airplane"
        case .jd:
            "cart"
        case .other:
            "shippingbox"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .duoduo:
            .systemRed
        case .yixiaoji:
            .systemIndigo
        case .cainiao:
            .systemTeal
        case .sfExpress:
            .systemPurple
        case .jd:
            .systemPink
        case .other:
            .systemGray
        }
    }

    func symbolImage(pointSize: CGFloat = 15, weight: UIImage.SymbolWeight = .semibold) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return UIImage(systemName: symbolName, withConfiguration: configuration)
    }

    func iconTileImage(
        baseSize: CGFloat = 34,
        maxSize: CGFloat = 44,
        compatibleWith traitCollection: UITraitCollection
    ) -> UIImage {
        let scaledSize = min(
            maxSize,
            UIFontMetrics(forTextStyle: .body).scaledValue(for: baseSize, compatibleWith: traitCollection)
        )
        let roundedSize = scaledSize.rounded(.toNearestOrAwayFromZero)
        let tileSize = CGSize(width: roundedSize, height: roundedSize)
        let cornerRadius = (roundedSize * 0.24).rounded(.toNearestOrAwayFromZero)
        let backgroundColor = tintColor.resolvedColor(with: traitCollection)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: roundedSize * 0.48, weight: .semibold)
        let symbol = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)

        let format = UIGraphicsImageRendererFormat(for: traitCollection)
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: tileSize, format: format)

        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: tileSize)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            backgroundColor.setFill()
            path.fill()

            if let symbol {
                let symbolSize = symbol.size
                let origin = CGPoint(
                    x: (tileSize.width - symbolSize.width) * 0.5,
                    y: (tileSize.height - symbolSize.height) * 0.5
                )
                symbol.draw(in: CGRect(origin: origin, size: symbolSize))
            }
        }
    }
}
