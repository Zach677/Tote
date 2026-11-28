import UIKit

enum ParcelTypography {
    static var pendingPickupCodeFont: UIFont {
        UIFontMetrics(forTextStyle: .title1).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: 28, weight: .bold),
            maximumPointSize: 56
        )
    }

    static var pickedUpCodeFont: UIFont {
        UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: 22, weight: .semibold),
            maximumPointSize: 44
        )
    }

    static var previewCodeFont: UIFont {
        UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: 22, weight: .bold),
            maximumPointSize: 44
        )
    }

    static var handoffCodeFont: UIFont {
        UIFontMetrics(forTextStyle: .title1).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: 28, weight: .bold),
            maximumPointSize: 56
        )
    }

    static var trackingNumberFont: UIFont {
        UIFontMetrics(forTextStyle: .callout).scaledFont(
            for: .monospacedSystemFont(ofSize: 16, weight: .semibold)
        )
    }

    static var toastFont: UIFont {
        UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        )
    }

    static var accentForegroundColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? .black : .white
        }
    }
}
