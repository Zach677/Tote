import UIKit

final class QuickAddInputCell: UICollectionViewListCell {
    private let pasteControl: UIPasteControl
    private let clearButton = UIButton(type: .system)
    private let separatorView = UIView()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()

    private var onTextChange: (String) -> Void = { _ in }
    private var onClear: () -> Void = {}

    override init(frame: CGRect) {
        let pasteConfig = UIPasteControl.Configuration()
        pasteConfig.displayMode = .iconAndLabel
        pasteConfig.cornerStyle = .capsule
        pasteConfig.baseBackgroundColor = .tintColor
        pasteConfig.baseForegroundColor = ParcelTypography.accentForegroundColor
        pasteControl = UIPasteControl(configuration: pasteConfig)

        super.init(frame: frame)
        configureLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        text: String,
        pasteTarget: (any UIPasteConfigurationSupporting)?,
        onTextChange: @escaping (String) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.onTextChange = onTextChange
        self.onClear = onClear
        pasteControl.target = pasteTarget
        setText(text)
    }

    func setText(_ text: String) {
        if textView.text != text {
            textView.text = text
        }
        updateEmptyUIState(isEmpty: text.isEmpty)
    }
}

private extension QuickAddInputCell {
    func configureLayout() {
        pasteControl.translatesAutoresizingMaskIntoConstraints = false
        pasteControl.setContentHuggingPriority(.required, for: .horizontal)

        var clearConfig = UIButton.Configuration.plain()
        clearConfig.title = String(localized: "Clear")
        clearConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 4)
        clearButton.configuration = clearConfig
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isHidden = true
        clearButton.addAction(
            UIAction { [weak self] _ in
                self?.onClear()
            },
            for: .touchUpInside
        )

        let topBar = UIStackView(arrangedSubviews: [pasteControl, UIView(), clearButton])
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.axis = .horizontal
        topBar.alignment = .center
        topBar.spacing = 8

        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = .separator

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = String(localized: "Paste or type a pickup message")
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isUserInteractionEnabled = false

        contentView.addSubview(topBar)
        contentView.addSubview(separatorView)
        contentView.addSubview(textView)
        contentView.addSubview(placeholderLabel)

        let minTextHeight = textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 96)
        minTextHeight.priority = .defaultHigh

        let separatorHeight = separatorView.heightAnchor.constraint(
            equalToConstant: 1.0 / max(traitCollection.displayScale, 2.0)
        )
        registerForTraitChanges([UITraitDisplayScale.self]) { (cell: Self, _) in
            separatorHeight.constant = 1.0 / max(cell.traitCollection.displayScale, 2.0)
        }

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            topBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            topBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            separatorView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            separatorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            separatorHeight,

            textView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 4),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            minTextHeight,

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
        ])
    }

    func updateEmptyUIState(isEmpty: Bool) {
        placeholderLabel.isHidden = !isEmpty
        clearButton.isHidden = isEmpty
    }
}

extension QuickAddInputCell: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        let updatedText = textView.text ?? ""
        updateEmptyUIState(isEmpty: updatedText.isEmpty)
        onTextChange(updatedText)
    }
}
