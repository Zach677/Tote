import UIKit

final class CopyToastView: UIView {
    private let effectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let iconImageView = UIImageView()
    private let messageLabel = UILabel()
    private var hideTask: Task<Void, Never>?

    private(set) var currentValue: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        hideTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        effectView.layer.cornerRadius = bounds.height * 0.5
    }

    func show(copiedValue: String, holdDuration: TimeInterval = 1.5) {
        hideTask?.cancel()
        currentValue = copiedValue
        messageLabel.text = String(localized: "Copied \(copiedValue)")
        isHidden = false

        UIView.animate(
            withDuration: 0.15,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut]
        ) {
            self.alpha = 1
        }

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(holdDuration))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        hideTask?.cancel()
        hideTask = nil

        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseIn],
            animations: {
                self.alpha = 0
            },
            completion: { [weak self] finished in
                guard let self, finished, alpha == 0 else { return }
                isHidden = true
                currentValue = nil
            }
        )
    }
}

private extension CopyToastView {
    func configureLayout() {
        isUserInteractionEnabled = false
        alpha = 0
        isHidden = true

        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.clipsToBounds = true
        effectView.layer.cornerCurve = .continuous

        let symbolConfig = UIImage.SymbolConfiguration(textStyle: .subheadline, scale: .medium)
        iconImageView.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: symbolConfig)
        iconImageView.tintColor = .systemGreen
        iconImageView.adjustsImageSizeForAccessibilityContentSizeCategory = true
        iconImageView.setContentHuggingPriority(.required, for: .horizontal)
        iconImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

        messageLabel.font = ParcelTypography.toastFont
        messageLabel.textColor = .label
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 1
        messageLabel.lineBreakMode = .byTruncatingMiddle

        let stackView = UIStackView(arrangedSubviews: [iconImageView, messageLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8

        addSubview(effectView)
        effectView.contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            stackView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor, constant: -12),
            stackView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor, constant: 18),
            stackView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor, constant: -18),
        ])
    }
}
