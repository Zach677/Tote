import UIKit

extension UIBarButtonItem {
    static func prominentIconItem(
        systemName: String,
        accessibilityLabel: String,
        isEnabled: Bool = true,
        primaryAction: UIAction
    ) -> UIBarButtonItem {
        let item = UIBarButtonItem(primaryAction: primaryAction)
        item.style = .prominent
        item.image = prominentSymbolImage(systemName: systemName, isEnabled: isEnabled)
        item.accessibilityLabel = accessibilityLabel
        item.isEnabled = isEnabled
        return item
    }

    static func prominentSymbolImage(systemName: String, isEnabled: Bool) -> UIImage? {
        let color: UIColor = isEnabled ? ParcelTypography.accentForegroundColor : .tertiaryLabel
        return UIImage(systemName: systemName)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
    }

    func applyProminentTitleContrast() {
        let enabledColor = ParcelTypography.accentForegroundColor
        setTitleTextAttributes([.foregroundColor: enabledColor], for: .normal)
        setTitleTextAttributes([.foregroundColor: enabledColor], for: .highlighted)
        setTitleTextAttributes([.foregroundColor: UIColor.tertiaryLabel], for: .disabled)
    }

    func updateProminentIconEnabled(_ isEnabled: Bool, systemName: String) {
        self.isEnabled = isEnabled
        image = Self.prominentSymbolImage(systemName: systemName, isEnabled: isEnabled)
    }
}
