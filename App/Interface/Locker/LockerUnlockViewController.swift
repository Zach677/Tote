import Core
import UIKit

final class LockerUnlockViewController: UIViewController {
    enum UnlockState: Equatable {
        case ready
        case unlocking
        case opened(compartment: String, message: String)
        case paymentRequired(message: String, amount: String, overdueDays: String)
        case failed(message: String, isSessionExpired: Bool)
    }

    let dependencies: AppDependencies
    private(set) var parcel: Parcel
    var onParcelUpdated: (Parcel) -> Void = { _ in }
    var onMarkPickedUp: (Parcel.ID) -> Void = { _ in }

    private(set) var unlockState: UnlockState = .ready
    private(set) var selectedCabinetName: String
    private(set) var selectedCabinetMAC: String
    private(set) var selectedSiteID: String
    private(set) var availableCabinets: [YixiaojiCabinet] = []
    private(set) var isLoadingCabinets = false
    private(set) var didAutoMatchCabinet = false

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let codeCard = UIView()
    private let codeEyebrowLabel = UILabel()
    private let codeLabel = UILabel()
    private let copyButton = UIButton(type: .system)

    private let cabinetCard = UIView()
    private let cabinetTitleLabel = UILabel()
    private let cabinetValueLabel = UILabel()
    private let cabinetStatusLabel = UILabel()
    private let cabinetPickerButton = UIButton(type: .system)
    private let cabinetSpinner = UIActivityIndicatorView(style: .medium)

    private let resultCard = UIView()
    private let resultTitleLabel = UILabel()
    private let resultBigValueLabel = UILabel()
    private let resultMessageLabel = UILabel()

    private let primaryButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)

    private var lookupTask: Task<Void, Never>?
    private var unlockTask: Task<Void, Never>?
    private var copyResetTask: Task<Void, Never>?

    init(parcel: Parcel, dependencies: AppDependencies) {
        self.parcel = parcel
        self.dependencies = dependencies
        selectedCabinetName = parcel.stationLabel
        selectedCabinetMAC = parcel.lockerMAC
        selectedSiteID = parcel.lockerSiteID
        didAutoMatchCabinet = !parcel.lockerMAC.isEmpty
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        lookupTask?.cancel()
        unlockTask?.cancel()
        copyResetTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        configureNavigationBar()
        configureLayout()
        render()

        if dependencies.yixiaoji.currentSession != nil {
            lookupTask = Task { [weak self] in
                await self?.performInitialLookup()
            }
        }
    }

    func performInitialLookup() async {
        guard dependencies.yixiaoji.currentSession != nil else { return }

        isLoadingCabinets = true
        render()

        defer {
            isLoadingCabinets = false
            render()
        }

        // If this parcel has no exact cabinet binding yet (e.g. pasted manually),
        // check Yixiaoji keyword search first, then fall back to pending parcels list.
        if selectedCabinetMAC.isEmpty, parcel.hasPickupCode {
            let searchMatches = await (try? dependencies.yixiaoji.searchParcels(keyword: parcel.pickupCode)) ?? []
            if let bestMatch = findBestRemoteMatch(in: searchMatches, allowSingleFallback: true) {
                applyMatchedRemoteParcel(bestMatch)
            } else if let pendingMatches = try? await dependencies.yixiaoji.fetchPendingParcels(),
                      let bestMatch = findBestRemoteMatch(in: pendingMatches, allowSingleFallback: false)
            {
                applyMatchedRemoteParcel(bestMatch)
            }
        }

        if let cabinets = try? await dependencies.yixiaoji.fetchCabinets(keyword: "") {
            availableCabinets = cabinets
            if selectedCabinetName.isEmpty, !selectedSiteID.isEmpty,
               let matched = cabinets.first(where: { $0.id == selectedSiteID })
            {
                selectedCabinetName = matched.name
            }
            if selectedCabinetMAC.isEmpty, selectedSiteID.isEmpty {
                if let last = dependencies.yixiaoji.lastSelectedCabinet {
                    selectedCabinetName = last.name
                    selectedCabinetMAC = last.mac
                    selectedSiteID = last.id
                }
            }
        }
    }

    func selectCabinet(_ cabinet: YixiaojiCabinet) {
        selectedCabinetName = cabinet.name
        selectedCabinetMAC = cabinet.mac
        selectedSiteID = cabinet.id
        didAutoMatchCabinet = false
        dependencies.yixiaoji.lastSelectedCabinet = cabinet

        var updated = parcel
        updated.stationLabel = cabinet.name
        updated.lockerMAC = cabinet.mac
        updated.lockerSiteID = cabinet.id
        persistUpdatedParcel(updated)

        if case .failed = unlockState {
            unlockState = .ready
        }
        render()
    }

    func performUnlock() async {
        guard dependencies.yixiaoji.currentSession != nil else {
            pushLogin()
            return
        }
        guard unlockState != .unlocking else { return }

        unlockState = .unlocking
        render()

        do {
            let result = try await dependencies.yixiaoji.unlockParcel(
                code: parcel.pickupCode,
                cabinetMAC: selectedCabinetMAC.isEmpty ? nil : selectedCabinetMAC,
                siteID: selectedSiteID.isEmpty ? nil : selectedSiteID
            )
            switch result {
            case let .opened(compartment, message, _):
                unlockState = .opened(compartment: compartment, message: message)
                UINotificationFeedbackGenerator(view: view).notificationOccurred(.success)
            case let .paymentRequired(message, amount, overdueDays):
                unlockState = .paymentRequired(message: message, amount: amount, overdueDays: overdueDays)
                UINotificationFeedbackGenerator(view: view).notificationOccurred(.warning)
            }
        } catch let apiError as YixiaojiAPIError {
            switch apiError {
            case .notSignedIn:
                unlockState = .failed(
                    message: String(localized: "Sign in to Yixiaoji to open lockers."),
                    isSessionExpired: true
                )
            case let .sessionExpired(message):
                let text = message.isEmpty ? String(localized: "Your Yixiaoji session expired. Please sign in again.") : message
                unlockState = .failed(message: text, isSessionExpired: true)
            case let .serverError(message), let .invalidCredentials(message):
                let text = message.isEmpty ? String(localized: "Couldn’t open the locker. Check the selected locker and try again.") : message
                unlockState = .failed(message: text, isSessionExpired: false)
            case .invalidResponse, .networkError:
                unlockState = .failed(
                    message: String(localized: "Couldn’t reach Yixiaoji. Check your connection and try again."),
                    isSessionExpired: false
                )
            }
            UINotificationFeedbackGenerator(view: view).notificationOccurred(.error)
        } catch {
            unlockState = .failed(
                message: String(localized: "Couldn’t reach Yixiaoji. Check your connection and try again."),
                isSessionExpired: false
            )
            UINotificationFeedbackGenerator(view: view).notificationOccurred(.error)
        }

        render()
    }

    func copyCode() {
        guard parcel.hasPickupCode else { return }
        dependencies.clipboard.copy(parcel.pickupCode)
        UINotificationFeedbackGenerator(view: copyButton).notificationOccurred(.success)
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "Copied \(parcel.pickupCode)")
        )

        var config = copyButton.configuration ?? .tinted()
        config.title = String(localized: "Copied")
        config.image = UIImage(systemName: "checkmark")
        copyButton.configuration = config

        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            configureCopyButtonDefault()
        }
    }

    func openInSafari() {
        dependencies.launcher.open(AppDependencies.yixiaojiWebFallbackURL) { _ in }
    }

    func markAsPickedUp() {
        onMarkPickedUp(parcel.id)
        dismiss(animated: true)
    }

    func pushLogin() {
        let existingUsername = dependencies.yixiaoji.currentSession?.username ?? ""
        let loginController = YixiaojiLoginViewController(
            dependencies: dependencies,
            initialUsername: existingUsername
        ) { [weak self] _ in
            guard let self else { return }
            unlockState = .ready
            navigationController?.popViewController(animated: true)
            render()
            lookupTask?.cancel()
            lookupTask = Task { [weak self] in
                await self?.performInitialLookup()
            }
        }
        navigationController?.pushViewController(loginController, animated: true)
    }
}

private extension LockerUnlockViewController {
    func findBestRemoteMatch(
        in candidates: [YixiaojiRemoteParcel],
        allowSingleFallback: Bool
    ) -> YixiaojiRemoteParcel? {
        let normalizedTarget = parcel.normalizedPickupCode
        let trimmedTarget = String(normalizedTarget.drop(while: { $0 == "0" }))

        let match = candidates.first { candidate in
            let code = candidate.makeDraft().normalizedPickupCode
            if code == normalizedTarget {
                return true
            }
            let trimmedCode = String(code.drop(while: { $0 == "0" }))
            return !trimmedTarget.isEmpty && trimmedCode == trimmedTarget
        } ?? (allowSingleFallback && candidates.count == 1 ? candidates.first : nil)

        guard let match,
              !match.cabinetMAC.isEmpty || !match.siteID.isEmpty || !match.cabinetName.isEmpty
        else {
            return nil
        }
        return match
    }

    func applyMatchedRemoteParcel(_ remote: YixiaojiRemoteParcel) {
        if !remote.cabinetName.isEmpty {
            selectedCabinetName = remote.cabinetName
        }
        if !remote.cabinetMAC.isEmpty {
            selectedCabinetMAC = remote.cabinetMAC
            didAutoMatchCabinet = true
        }
        if !remote.siteID.isEmpty {
            selectedSiteID = remote.siteID
        }

        var updated = parcel
        if !remote.cabinetName.isEmpty {
            updated.stationLabel = remote.cabinetName
        }
        if !remote.cabinetMAC.isEmpty {
            updated.lockerMAC = remote.cabinetMAC
        }
        if !remote.siteID.isEmpty {
            updated.lockerSiteID = remote.siteID
        }
        if updated.trackingNumber.isEmpty, !remote.trackingNumber.isEmpty {
            updated.trackingNumber = remote.trackingNumber
        }
        persistUpdatedParcel(updated)
    }

    func persistUpdatedParcel(_ updated: Parcel) {
        parcel = updated
        if (try? dependencies.parcelStore.update(updated)) != nil {
            onParcelUpdated(updated)
        }
    }

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

    func configureCopyButtonDefault() {
        var config = UIButton.Configuration.tinted()
        config.cornerStyle = .capsule
        config.title = String(localized: "Copy")
        config.image = UIImage(systemName: "doc.on.doc")
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        copyButton.configuration = config
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

    func styleCard(_ view: UIView) {
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
    }

    func render() {
        renderCabinetCard()
        renderStateAndButtons()
    }

    func renderCabinetCard() {
        let isSignedIn = dependencies.yixiaoji.currentSession != nil

        if !isSignedIn {
            cabinetValueLabel.text = selectedCabinetName.isEmpty
                ? String(localized: "Not Signed In")
                : selectedCabinetName
            cabinetStatusLabel.text = String(localized: "Sign in to Yixiaoji to select a locker and open the door directly.")
            cabinetStatusLabel.textColor = .secondaryLabel
            cabinetStatusLabel.isHidden = false
            cabinetPickerButton.isHidden = true
            cabinetSpinner.stopAnimating()
            return
        }

        cabinetValueLabel.text = selectedCabinetName.isEmpty
            ? String(localized: "Choose Locker")
            : selectedCabinetName

        if isLoadingCabinets {
            cabinetSpinner.startAnimating()
        } else {
            cabinetSpinner.stopAnimating()
        }

        if didAutoMatchCabinet, !selectedCabinetMAC.isEmpty {
            cabinetStatusLabel.text = String(localized: "Matched to this parcel’s locker")
            cabinetStatusLabel.textColor = .systemGreen
            cabinetStatusLabel.isHidden = false
        } else if !selectedSiteID.isEmpty || !selectedCabinetMAC.isEmpty {
            cabinetStatusLabel.text = String(localized: "Selected locker for opening")
            cabinetStatusLabel.textColor = .secondaryLabel
            cabinetStatusLabel.isHidden = false
        } else {
            cabinetStatusLabel.text = String(localized: "Choose the locker in front of you before opening.")
            cabinetStatusLabel.textColor = .secondaryLabel
            cabinetStatusLabel.isHidden = false
        }

        if !availableCabinets.isEmpty {
            var pickerConfig = UIButton.Configuration.tinted()
            pickerConfig.cornerStyle = .capsule
            pickerConfig.title = String(localized: "Change")
            pickerConfig.image = UIImage(systemName: "chevron.up.chevron.down")
            pickerConfig.imagePlacement = .trailing
            pickerConfig.imagePadding = 4
            pickerConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            cabinetPickerButton.configuration = pickerConfig
            cabinetPickerButton.menu = makeCabinetMenu()
            cabinetPickerButton.isHidden = false
        } else {
            cabinetPickerButton.isHidden = true
        }
    }

    func makeCabinetMenu() -> UIMenu {
        let actions = availableCabinets.map { cabinet in
            let isSelected = (!selectedSiteID.isEmpty && cabinet.id == selectedSiteID)
                || (!selectedCabinetName.isEmpty && cabinet.name == selectedCabinetName)
            return UIAction(
                title: cabinet.name,
                subtitle: cabinet.displayDetail.isEmpty ? nil : cabinet.displayDetail,
                state: isSelected ? .on : .off
            ) { [weak self] _ in
                self?.selectCabinet(cabinet)
            }
        }
        return UIMenu(title: String(localized: "Choose Locker"), options: .singleSelection, children: actions)
    }

    func renderStateAndButtons() {
        let isSignedIn = dependencies.yixiaoji.currentSession != nil
        let accentColor = UIColor(named: "AccentColor") ?? view.tintColor ?? .systemOrange

        switch unlockState {
        case .ready:
            resultCard.isHidden = true
            if isSignedIn {
                applyFilledButton(
                    primaryButton,
                    title: String(localized: "Open Locker"),
                    symbolName: "lock.open.fill",
                    backgroundColor: accentColor,
                    foregroundColor: ParcelTypography.accentForegroundColor,
                    isLoading: false
                )
            } else {
                applyFilledButton(
                    primaryButton,
                    title: String(localized: "Sign In to Yixiaoji"),
                    symbolName: "person.crop.circle",
                    backgroundColor: accentColor,
                    foregroundColor: ParcelTypography.accentForegroundColor,
                    isLoading: false
                )
            }
            applyPlainSecondaryButton(title: String(localized: "Open Yixiaoji in Safari"))

        case .unlocking:
            resultCard.isHidden = true
            applyFilledButton(
                primaryButton,
                title: String(localized: "Opening Locker…"),
                symbolName: nil,
                backgroundColor: accentColor,
                foregroundColor: ParcelTypography.accentForegroundColor,
                isLoading: true
            )
            applyPlainSecondaryButton(title: String(localized: "Open Yixiaoji in Safari"))

        case let .opened(compartment, message):
            resultCard.isHidden = false
            resultCard.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.14)
            resultTitleLabel.text = compartment.isEmpty
                ? String(localized: "Locker Opened")
                : String(localized: "Compartment")
            resultTitleLabel.textColor = .systemGreen
            resultBigValueLabel.isHidden = compartment.isEmpty
            resultBigValueLabel.text = compartment
            resultBigValueLabel.textColor = .systemGreen
            resultMessageLabel.text = message.isEmpty
                ? String(localized: "Collect your parcel and close the door.")
                : message
            resultMessageLabel.textColor = .label

            applyFilledButton(
                primaryButton,
                title: String(localized: "Mark as Picked Up"),
                symbolName: "checkmark.circle.fill",
                backgroundColor: .systemGreen,
                foregroundColor: .white,
                isLoading: false
            )
            applyPlainSecondaryButton(title: String(localized: "Open Again"))

        case let .paymentRequired(message, amount, overdueDays):
            resultCard.isHidden = false
            resultCard.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.16)
            resultTitleLabel.text = String(localized: "Overdue Fee Required")
            resultTitleLabel.textColor = .systemOrange
            resultBigValueLabel.isHidden = amount.isEmpty
            resultBigValueLabel.text = amount.isEmpty ? "" : "¥\(amount)"
            resultBigValueLabel.textColor = .systemOrange

            var detailParts: [String] = []
            if !message.isEmpty {
                detailParts.append(message)
            } else if !overdueDays.isEmpty {
                detailParts.append(String(localized: "Overdue by \(overdueDays) days."))
            }
            detailParts.append(String(localized: "Complete payment in Yixiaoji on WeChat, then open again."))
            resultMessageLabel.text = detailParts.joined(separator: "\n")
            resultMessageLabel.textColor = .label

            applyFilledButton(
                primaryButton,
                title: String(localized: "Copy Pickup Code"),
                symbolName: "doc.on.doc",
                backgroundColor: accentColor,
                foregroundColor: ParcelTypography.accentForegroundColor,
                isLoading: false
            )
            applyPlainSecondaryButton(title: String(localized: "Open Yixiaoji in Safari"))

        case let .failed(message, isSessionExpired):
            resultCard.isHidden = false
            resultCard.backgroundColor = UIColor.systemRed.withAlphaComponent(0.14)
            resultTitleLabel.text = isSessionExpired
                ? String(localized: "Session Expired")
                : String(localized: "Couldn’t Open Locker")
            resultTitleLabel.textColor = .systemRed
            resultBigValueLabel.isHidden = true
            resultMessageLabel.text = message
            resultMessageLabel.textColor = .label

            applyFilledButton(
                primaryButton,
                title: isSessionExpired
                    ? String(localized: "Sign In Again")
                    : String(localized: "Try Again"),
                symbolName: isSessionExpired ? "person.crop.circle" : "arrow.clockwise",
                backgroundColor: accentColor,
                foregroundColor: ParcelTypography.accentForegroundColor,
                isLoading: false
            )
            applyPlainSecondaryButton(title: String(localized: "Open Yixiaoji in Safari"))
        }
    }

    func applyFilledButton(
        _ button: UIButton,
        title: String,
        symbolName: String?,
        backgroundColor: UIColor,
        foregroundColor: UIColor,
        isLoading: Bool
    ) {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = backgroundColor
        config.baseForegroundColor = foregroundColor
        config.cornerStyle = .large
        config.title = title
        config.showsActivityIndicator = isLoading
        config.imagePadding = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        if let symbolName, !isLoading {
            config.image = UIImage(systemName: symbolName)
        }
        button.configuration = config
        button.isEnabled = !isLoading
    }

    func applyPlainSecondaryButton(title: String) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        secondaryButton.configuration = config
    }

    func handlePrimaryActionTapped() {
        switch unlockState {
        case .ready:
            if dependencies.yixiaoji.currentSession == nil {
                pushLogin()
            } else {
                startUnlockTask()
            }
        case .unlocking:
            break
        case .opened:
            markAsPickedUp()
        case .paymentRequired:
            copyCode()
        case let .failed(_, isSessionExpired):
            if isSessionExpired {
                pushLogin()
            } else {
                startUnlockTask()
            }
        }
    }

    func handleSecondaryActionTapped() {
        switch unlockState {
        case .opened:
            startUnlockTask()
        case .ready, .unlocking, .paymentRequired, .failed:
            openInSafari()
        }
    }

    func startUnlockTask() {
        unlockTask?.cancel()
        unlockTask = Task { [weak self] in
            await self?.performUnlock()
        }
    }
}
