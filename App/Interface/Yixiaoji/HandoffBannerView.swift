import UIKit

final class HandoffBannerView: UIView {
    private let effectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let headerLabel = UILabel()
    private let codeLabel = UILabel()
    private let helperLabel = UILabel()
    private let textStack = UIStackView()
    private let closeButton = UIButton(type: .system)

    private(set) var code: String
    var onTapCopy: (String) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    init(code: String) {
        self.code = code
        super.init(frame: .zero)
        configureLayout()
        update(code: code)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(code: String) {
        self.code = code
        codeLabel.text = code
        textStack.accessibilityLabel = [
            headerLabel.text,
            code,
            helperLabel.text,
        ]
        .compactMap(\.self)
        .joined(separator: ", ")
    }

    func triggerCopyTap() {
        onTapCopy(code)
    }

    func triggerDismiss() {
        onDismiss()
    }
}

private extension HandoffBannerView {
    func configureLayout() {
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.clipsToBounds = true
        effectView.layer.cornerRadius = 26
        effectView.layer.cornerCurve = .continuous

        headerLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .systemFont(ofSize: 13, weight: .semibold)
        )
        headerLabel.adjustsFontForContentSizeCategory = true
        headerLabel.textColor = .secondaryLabel
        headerLabel.text = String(localized: "Pickup Code Copied")

        codeLabel.font = ParcelTypography.handoffCodeFont
        codeLabel.adjustsFontForContentSizeCategory = true
        codeLabel.textColor = .label
        codeLabel.numberOfLines = 0
        codeLabel.lineBreakMode = .byCharWrapping

        helperLabel.font = .preferredFont(forTextStyle: .footnote)
        helperLabel.adjustsFontForContentSizeCategory = true
        helperLabel.textColor = .secondaryLabel
        helperLabel.numberOfLines = 0
        helperLabel.text = String(localized: "Paste it on the page to open the locker.")

        textStack.addArrangedSubview(headerLabel)
        textStack.addArrangedSubview(codeLabel)
        textStack.addArrangedSubview(helperLabel)
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.isAccessibilityElement = true
        textStack.accessibilityTraits = .button
        textStack.accessibilityHint = String(localized: "Copy again")

        var closeConfig = UIButton.Configuration.filled()
        closeConfig.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        closeConfig.baseBackgroundColor = .tertiarySystemFill
        closeConfig.baseForegroundColor = .secondaryLabel
        closeConfig.cornerStyle = .capsule
        closeButton.configuration = closeConfig
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.accessibilityLabel = String(localized: "Dismiss")
        closeButton.addAction(
            UIAction { [weak self] _ in
                self?.triggerDismiss()
            },
            for: .touchUpInside
        )

        let rowStack = UIStackView(arrangedSubviews: [textStack, closeButton])
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.axis = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 12

        addSubview(effectView)
        effectView.contentView.addSubview(rowStack)

        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),

            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            rowStack.topAnchor.constraint(equalTo: effectView.contentView.topAnchor, constant: 14),
            rowStack.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor, constant: -14),
            rowStack.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor, constant: 16),
            rowStack.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor, constant: -14),
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleCardTap))
        tapGesture.delegate = self
        effectView.contentView.addGestureRecognizer(tapGesture)
    }

    @objc func handleCardTap() {
        triggerCopyTap()
    }
}

extension HandoffBannerView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let touchedView = touch.view, touchedView.isDescendant(of: closeButton) {
            return false
        }
        return true
    }
}
