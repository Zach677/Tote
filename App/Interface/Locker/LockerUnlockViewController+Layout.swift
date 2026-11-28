import Core
import UIKit

extension LockerUnlockViewController {
    func configureNavigationBar() {
        title = String(localized: "Open Locker")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
    }

    func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
        ])

        configureCodeCard()
        configureCabinetCard()
        configureResultCard()
        configureActionButtons()

        contentStack.addArrangedSubview(codeCard)
        contentStack.addArrangedSubview(cabinetCard)
        contentStack.addArrangedSubview(resultCard)
        contentStack.addArrangedSubview(primaryButton)
        contentStack.addArrangedSubview(secondaryButton)
    }

    func configureCopyButtonDefault() {
        var config = UIButton.Configuration.tinted()
        config.cornerStyle = .capsule
        config.title = String(localized: "Copy")
        config.image = UIImage(systemName: "doc.on.doc")
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        copyButton.configuration = config
    }
}

private extension LockerUnlockViewController {
    func configureCodeCard() {
        styleCard(codeCard)

        codeEyebrowLabel.font = .preferredFont(forTextStyle: .footnote)
        codeEyebrowLabel.adjustsFontForContentSizeCategory = true
        codeEyebrowLabel.textColor = .secondaryLabel
        codeEyebrowLabel.text = String(localized: "Pickup Code")

        codeLabel.font = ParcelTypography.handoffCodeFont
        codeLabel.adjustsFontForContentSizeCategory = true
        codeLabel.textColor = .label
        codeLabel.numberOfLines = 0
        codeLabel.lineBreakMode = .byCharWrapping
        codeLabel.text = parcel.pickupCode

        configureCopyButtonDefault()
        copyButton.addAction(
            UIAction { [weak self] _ in
                self?.copyCode()
            },
            for: .touchUpInside
        )
        copyButton.setContentHuggingPriority(.required, for: .horizontal)
        copyButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let leftStack = UIStackView(arrangedSubviews: [codeEyebrowLabel, codeLabel])
        leftStack.axis = .vertical
        leftStack.spacing = 4

        let rowStack = UIStackView(arrangedSubviews: [leftStack, copyButton])
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 12

        codeCard.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: codeCard.topAnchor, constant: 16),
            rowStack.bottomAnchor.constraint(equalTo: codeCard.bottomAnchor, constant: -16),
            rowStack.leadingAnchor.constraint(equalTo: codeCard.leadingAnchor, constant: 16),
            rowStack.trailingAnchor.constraint(equalTo: codeCard.trailingAnchor, constant: -16),
        ])
    }

    func configureCabinetCard() {
        styleCard(cabinetCard)

        cabinetTitleLabel.font = .preferredFont(forTextStyle: .footnote)
        cabinetTitleLabel.adjustsFontForContentSizeCategory = true
        cabinetTitleLabel.textColor = .secondaryLabel
        cabinetTitleLabel.text = String(localized: "Locker")

        cabinetValueLabel.font = .preferredFont(forTextStyle: .headline)
        cabinetValueLabel.adjustsFontForContentSizeCategory = true
        cabinetValueLabel.textColor = .label
        cabinetValueLabel.numberOfLines = 2

        cabinetStatusLabel.font = .preferredFont(forTextStyle: .footnote)
        cabinetStatusLabel.adjustsFontForContentSizeCategory = true
        cabinetStatusLabel.numberOfLines = 0

        cabinetPickerButton.showsMenuAsPrimaryAction = true
        cabinetPickerButton.setContentHuggingPriority(.required, for: .horizontal)
        cabinetPickerButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        cabinetSpinner.hidesWhenStopped = true

        let leftStack = UIStackView(arrangedSubviews: [cabinetTitleLabel, cabinetValueLabel, cabinetStatusLabel])
        leftStack.axis = .vertical
        leftStack.spacing = 4

        let trailingStack = UIStackView(arrangedSubviews: [cabinetSpinner, cabinetPickerButton])
        trailingStack.axis = .horizontal
        trailingStack.alignment = .center
        trailingStack.spacing = 8

        let rowStack = UIStackView(arrangedSubviews: [leftStack, trailingStack])
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 12

        cabinetCard.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: cabinetCard.topAnchor, constant: 16),
            rowStack.bottomAnchor.constraint(equalTo: cabinetCard.bottomAnchor, constant: -16),
            rowStack.leadingAnchor.constraint(equalTo: cabinetCard.leadingAnchor, constant: 16),
            rowStack.trailingAnchor.constraint(equalTo: cabinetCard.trailingAnchor, constant: -16),
        ])
    }

    func configureResultCard() {
        styleCard(resultCard)
        resultCard.isHidden = true

        resultTitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        resultTitleLabel.adjustsFontForContentSizeCategory = true
        resultTitleLabel.textAlignment = .center

        let baseBigFont = UIFont.monospacedDigitSystemFont(ofSize: 44, weight: .bold)
        resultBigValueLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: baseBigFont)
        resultBigValueLabel.adjustsFontForContentSizeCategory = true
        resultBigValueLabel.textAlignment = .center
        resultBigValueLabel.numberOfLines = 1

        resultMessageLabel.font = .preferredFont(forTextStyle: .subheadline)
        resultMessageLabel.adjustsFontForContentSizeCategory = true
        resultMessageLabel.textAlignment = .center
        resultMessageLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [resultTitleLabel, resultBigValueLabel, resultMessageLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6

        resultCard.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: resultCard.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: resultCard.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: resultCard.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: resultCard.trailingAnchor, constant: -16),
        ])
    }

    func configureActionButtons() {
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        primaryButton.addAction(
            UIAction { [weak self] _ in
                self?.handlePrimaryActionTapped()
            },
            for: .touchUpInside
        )

        secondaryButton.translatesAutoresizingMaskIntoConstraints = false
        secondaryButton.addAction(
            UIAction { [weak self] _ in
                self?.handleSecondaryActionTapped()
            },
            for: .touchUpInside
        )
    }

    func styleCard(_ cardView: UIView) {
        cardView.backgroundColor = .secondarySystemGroupedBackground
        cardView.layer.cornerRadius = 16
        cardView.layer.cornerCurve = .continuous
    }
}
