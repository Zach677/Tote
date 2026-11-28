import Core
import Foundation
import UIKit

nonisolated enum SettingsSection: Hashable {
    case yixiaoji
    case duoduoLink
    case actions
}

nonisolated enum SettingsItem: Hashable {
    case yixiaojiSignIn
    case yixiaojiAccount
    case yixiaojiSyncNow
    case yixiaojiOpenSafari
    case yixiaojiSignOut
    case urlEditor
    case testLink
    case resetLink
}

final class SettingsViewController: UIViewController {
    let dependencies: AppDependencies
    var onParcelsChanged: () -> Void = {}
    private(set) var urlText: String
    private(set) var isSyncingYixiaoji = false
    private(set) var lastSyncSummary: String?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SettingsSection, SettingsItem>!
    private var doneButton: UIBarButtonItem!
    private weak var editorCell: SettingsURLEditorCell?
    private var syncTask: Task<Void, Never>?

    var validatedURL: URL? {
        DuoduoLinkValidator.validatedURL(from: urlText)
    }

    var isLinkValid: Bool {
        validatedURL != nil
    }

    var canResetToDefault: Bool {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines) != DuoduoLinkValidator.defaultURLString
    }

    var isDoneEnabled: Bool {
        doneButton?.isEnabled ?? isLinkValid
    }

    var isYixiaojiSignedIn: Bool {
        dependencies.yixiaoji.currentSession != nil
    }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        urlText = dependencies.settings.duoduoURLString
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        syncTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        configureNavigationBar()
        configureCollectionView()
        configureDataSource()
        applySnapshot(animatingDifferences: false)
        updateValidationUI()
    }

    func updateURLText(_ newText: String, syncEditorCell: Bool = true) {
        urlText = newText
        if syncEditorCell {
            editorCell?.setText(newText)
        }
        updateValidationUI()
    }

    func testCurrentLink() {
        guard let url = validatedURL else { return }
        dependencies.launcher.open(url) { [weak self] success in
            guard let self, !success else { return }
            presentTestFailureAlert()
        }
    }

    func resetToDefault() {
        guard canResetToDefault else { return }
        updateURLText(DuoduoLinkValidator.defaultURLString, syncEditorCell: true)
    }

    func pushYixiaojiLogin() {
        let existingUsername = dependencies.yixiaoji.currentSession?.username ?? ""
        let loginController = YixiaojiLoginViewController(
            dependencies: dependencies,
            initialUsername: existingUsername
        ) { [weak self] _ in
            guard let self else { return }
            lastSyncSummary = nil
            navigationController?.popViewController(animated: true)
            applySnapshot(animatingDifferences: true)
        }
        navigationController?.pushViewController(loginController, animated: true)
    }

    func signOutYixiaoji() {
        dependencies.yixiaoji.logout()
        lastSyncSummary = nil
        applySnapshot(animatingDifferences: true)
    }

    func openYixiaojiInSafari() {
        dependencies.launcher.open(AppDependencies.yixiaojiWebFallbackURL) { _ in }
    }

    @discardableResult
    func syncYixiaojiNow() async -> AddParcelsResult? {
        guard isYixiaojiSignedIn, !isSyncingYixiaoji else { return nil }
        isSyncingYixiaoji = true
        applySnapshot(animatingDifferences: false)

        defer {
            isSyncingYixiaoji = false
            applySnapshot(animatingDifferences: false)
        }

        do {
            let batch = try await dependencies.yixiaoji.fetchPendingParcels()
            let result = try dependencies.parcelStore.syncSyncedParcels(
                batch.parcels.map { $0.makeDraft() },
                markMissingSyncedLockerParcelsPickedUp: !batch.isTruncated
            )
            let totalChanged = result.added.count + result.updated.count + result.markedPickedUpCount
            if totalChanged > 0 {
                onParcelsChanged()
                lastSyncSummary = String(localized: "Synced \(totalChanged) locker parcels.")
            } else {
                lastSyncSummary = String(localized: "Locker parcels are up to date.")
            }
            return result
        } catch is CancellationError {
            return nil
        } catch let apiError as YixiaojiAPIError {
            switch apiError {
            case .sessionExpired, .notSignedIn:
                lastSyncSummary = String(localized: "Yixiaoji session expired. Please sign in again.")
            case let .serverError(message), let .invalidCredentials(message), let .storageError(message):
                lastSyncSummary = message.isEmpty ? String(localized: "Couldn’t sync Yixiaoji parcels.") : message
            case .missingCabinetSelection, .unlockUnconfirmed, .invalidResponse, .networkError:
                lastSyncSummary = String(localized: "Couldn’t reach Yixiaoji. Check your connection.")
            }
            return nil
        } catch {
            lastSyncSummary = String(localized: "Couldn’t sync Yixiaoji parcels.")
            return nil
        }
    }

    @discardableResult
    func saveAndDismiss() -> Bool {
        guard validatedURL != nil else { return false }
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == DuoduoLinkValidator.defaultURLString {
            dependencies.settings.resetDuoduoURL()
        } else {
            dependencies.settings.duoduoURLString = trimmed
        }
        dismiss(animated: true)
        return true
    }
}

private extension SettingsViewController {
    func configureNavigationBar() {
        title = String(localized: "Settings")
        navigationItem.largeTitleDisplayMode = .never

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )

        doneButton = UIBarButtonItem.prominentIconItem(
            systemName: "checkmark",
            accessibilityLabel: String(localized: "Done"),
            isEnabled: isLinkValid,
            primaryAction: UIAction { [weak self] _ in
                self?.saveAndDismiss()
            }
        )
        navigationItem.rightBarButtonItem = doneButton
    }

    func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            let section = self?.dataSource?.sectionIdentifier(for: sectionIndex)
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            switch section {
            case .yixiaoji, .duoduoLink:
                config.headerMode = .supplementary
                config.footerMode = .supplementary
            case .actions, .none:
                config.headerMode = .none
                config.footerMode = .none
            }
            return NSCollectionLayoutSection.list(using: config, layoutEnvironment: layoutEnvironment)
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.keyboardDismissMode = .interactive
        collectionView.delegate = self

        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func configureDataSource() {
        let editorRegistration = UICollectionView.CellRegistration<SettingsURLEditorCell, Void> { [weak self] cell, _, _ in
            guard let self else { return }
            editorCell = cell
            cell.configure(text: urlText) { [weak self] updatedText in
                self?.updateURLText(updatedText, syncEditorCell: false)
            }
        }

        let itemRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, SettingsItem> { [weak self] cell, _, item in
            guard let self else { return }
            configureRowCell(cell, for: item)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] headerCell, _, indexPath in
            guard let self, let section = dataSource.sectionIdentifier(for: indexPath.section) else { return }
            var config = UIListContentConfiguration.header()
            switch section {
            case .yixiaoji:
                config.text = String(localized: "Yixiaoji Locker")
            case .duoduoLink:
                config.text = String(localized: "Duoduo Station Link")
            case .actions:
                config.text = nil
            }
            headerCell.contentConfiguration = config
        }

        let yixiaojiFooterRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] footerCell, _, _ in
            guard let self else { return }
            configureYixiaojiFooter(footerCell)
        }

        let duoduoFooterRegistration = UICollectionView.SupplementaryRegistration<SettingsLinkFooterView>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] footerView, _, _ in
            guard let self else { return }
            footerView.configure(isValid: isLinkValid)
        }

        dataSource = UICollectionViewDiffableDataSource<SettingsSection, SettingsItem>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            switch item {
            case .urlEditor:
                collectionView.dequeueConfiguredReusableCell(using: editorRegistration, for: indexPath, item: ())
            default:
                collectionView.dequeueConfiguredReusableCell(using: itemRegistration, for: indexPath, item: item)
            }
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, elementKind, indexPath in
            if elementKind == UICollectionView.elementKindSectionHeader {
                return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
            }
            if elementKind == UICollectionView.elementKindSectionFooter {
                let section = self?.dataSource.sectionIdentifier(for: indexPath.section)
                if section == .yixiaoji {
                    return collectionView.dequeueConfiguredReusableSupplementary(using: yixiaojiFooterRegistration, for: indexPath)
                }
                if section == .duoduoLink {
                    return collectionView.dequeueConfiguredReusableSupplementary(using: duoduoFooterRegistration, for: indexPath)
                }
            }
            return nil
        }
    }

    func configureRowCell(_ cell: UICollectionViewListCell, for item: SettingsItem) {
        switch item {
        case .yixiaojiAccount:
            var content = UIListContentConfiguration.subtitleCell()
            content.image = PickupChannel.locker.symbolImage()
            content.imageProperties.tintColor = PickupChannel.locker.tintColor
            let session = dependencies.yixiaoji.currentSession
            content.text = session?.displayAccountName ?? String(localized: "Yixiaoji Account")
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.textProperties.adjustsFontForContentSizeCategory = true
            let siteName = session?.defaultSiteName ?? ""
            content.secondaryText = siteName.isEmpty ? String(localized: "Signed In") : siteName
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
            content.secondaryTextProperties.color = .secondaryLabel
            content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
            cell.contentConfiguration = content
            cell.accessories = []

        case .yixiaojiSignIn:
            var content = UIListContentConfiguration.cell()
            content.image = UIImage(systemName: "person.crop.circle")
            content.imageProperties.tintColor = .tintColor
            content.text = String(localized: "Sign In to Yixiaoji")
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.textProperties.color = .tintColor
            content.textProperties.adjustsFontForContentSizeCategory = true
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]

        case .yixiaojiSyncNow:
            var content = UIListContentConfiguration.cell()
            content.text = isSyncingYixiaoji
                ? String(localized: "Syncing…")
                : String(localized: "Sync Locker Parcels")
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.textProperties.color = isSyncingYixiaoji ? .secondaryLabel : .tintColor
            content.textProperties.adjustsFontForContentSizeCategory = true
            cell.contentConfiguration = content
            if isSyncingYixiaoji {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                cell.accessories = [.customView(configuration: .init(customView: spinner, placement: .trailing()))]
            } else {
                cell.accessories = []
            }

        case .yixiaojiOpenSafari:
            var content = UIListContentConfiguration.cell()
            content.text = String(localized: "Open Yixiaoji in Safari")
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.textProperties.color = .tintColor
            content.textProperties.adjustsFontForContentSizeCategory = true
            cell.contentConfiguration = content
            let symbol = UIImageView(image: UIImage(systemName: "arrow.up.forward.app"))
            symbol.tintColor = .tertiaryLabel
            cell.accessories = [.customView(configuration: .init(customView: symbol, placement: .trailing()))]

        case .yixiaojiSignOut:
            var content = UIListContentConfiguration.cell()
            content.text = String(localized: "Sign Out")
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.textProperties.color = .systemRed
            content.textProperties.adjustsFontForContentSizeCategory = true
            cell.contentConfiguration = content
            cell.accessories = []

        case .testLink:
            var content = UIListContentConfiguration.cell()
            content.text = String(localized: "Test Link")
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.textProperties.color = isLinkValid ? .tintColor : .tertiaryLabel
            content.textProperties.adjustsFontForContentSizeCategory = true
            cell.contentConfiguration = content
            cell.accessories = []

        case .resetLink:
            var content = UIListContentConfiguration.cell()
            content.text = String(localized: "Reset to Default Link")
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.textProperties.color = canResetToDefault ? .tintColor : .tertiaryLabel
            content.textProperties.adjustsFontForContentSizeCategory = true
            cell.contentConfiguration = content
            cell.accessories = []

        case .urlEditor:
            break
        }
    }

    func configureYixiaojiFooter(_ footerCell: UICollectionViewListCell) {
        var config = UIListContentConfiguration.footer()
        config.textProperties.font = .preferredFont(forTextStyle: .footnote)
        config.textProperties.color = .secondaryLabel
        if let lastSyncSummary, !lastSyncSummary.isEmpty {
            config.text = lastSyncSummary
        } else if isYixiaojiSignedIn {
            config.text = String(localized: "Pull down on the Pending list to sync Yixiaoji locker parcels.")
        } else {
            config.text = String(localized: "Sign in to sync locker parcels and open doors directly without a browser.")
        }
        footerCell.contentConfiguration = config
    }

    func applySnapshot(animatingDifferences: Bool) {
        let existingItems = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<SettingsSection, SettingsItem>()
        snapshot.appendSections([.yixiaoji, .duoduoLink, .actions])

        let yixiaojiItems: [SettingsItem] = if isYixiaojiSignedIn {
            [.yixiaojiAccount, .yixiaojiSyncNow, .yixiaojiOpenSafari, .yixiaojiSignOut]
        } else {
            [.yixiaojiSignIn, .yixiaojiOpenSafari]
        }
        snapshot.appendItems(yixiaojiItems, toSection: .yixiaoji)
        snapshot.appendItems([.urlEditor], toSection: .duoduoLink)
        snapshot.appendItems([.testLink, .resetLink], toSection: .actions)

        let reconfigureItems = snapshot.itemIdentifiers.filter { $0 != .urlEditor && existingItems.contains($0) }
        if !reconfigureItems.isEmpty {
            snapshot.reconfigureItems(reconfigureItems)
        }

        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)

        if let yixiaojiSectionIndex = dataSource.snapshot().indexOfSection(.yixiaoji),
           let footer = collectionView.supplementaryView(
               forElementKind: UICollectionView.elementKindSectionFooter,
               at: IndexPath(item: 0, section: yixiaojiSectionIndex)
           ) as? UICollectionViewListCell
        {
            configureYixiaojiFooter(footer)
            collectionView.performBatchUpdates(nil)
        }
    }

    func updateValidationUI() {
        doneButton.updateProminentIconEnabled(isLinkValid, systemName: "checkmark")

        var snapshot = dataSource.snapshot()
        let actionItems = [SettingsItem.testLink, .resetLink].filter { snapshot.indexOfItem($0) != nil }
        if !actionItems.isEmpty {
            snapshot.reconfigureItems(actionItems)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        if let duoduoSectionIndex = dataSource.snapshot().indexOfSection(.duoduoLink),
           let footer = collectionView.supplementaryView(
               forElementKind: UICollectionView.elementKindSectionFooter,
               at: IndexPath(item: 0, section: duoduoSectionIndex)
           ) as? SettingsLinkFooterView
        {
            footer.configure(isValid: isLinkValid)
        }
        collectionView.performBatchUpdates(nil)
    }

    func presentTestFailureAlert() {
        let alert = UIAlertController(
            title: String(localized: "Can’t Open Duoduo"),
            message: String(localized: "Check that Pinduoduo is installed, or change the link in Settings."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        guard presentedViewController == nil, viewIfLoaded?.window != nil else { return }
        present(alert, animated: true)
    }
}

extension SettingsViewController: UICollectionViewDelegate {
    func collectionView(_: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        return isActionEnabled(item)
    }

    func collectionView(_: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        return isActionEnabled(item)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .yixiaojiSignIn:
            pushYixiaojiLogin()
        case .yixiaojiSyncNow:
            syncTask?.cancel()
            syncTask = Task { [weak self] in
                _ = await self?.syncYixiaojiNow()
            }
        case .yixiaojiOpenSafari:
            openYixiaojiInSafari()
        case .yixiaojiSignOut:
            signOutYixiaoji()
        case .testLink:
            testCurrentLink()
        case .resetLink:
            resetToDefault()
        case .yixiaojiAccount, .urlEditor:
            break
        }
    }

    private func isActionEnabled(_ item: SettingsItem) -> Bool {
        switch item {
        case .urlEditor, .yixiaojiAccount:
            false
        case .yixiaojiSignIn, .yixiaojiOpenSafari, .yixiaojiSignOut:
            true
        case .yixiaojiSyncNow:
            !isSyncingYixiaoji
        case .testLink:
            isLinkValid
        case .resetLink:
            canResetToDefault
        }
    }
}

private final class SettingsURLEditorCell: UICollectionViewListCell, UITextViewDelegate {
    private let textView = UITextView()
    private var onTextChange: (String) -> Void = { _ in }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, onTextChange: @escaping (String) -> Void) {
        self.onTextChange = onTextChange
        setText(text)
    }

    func setText(_ text: String) {
        if textView.text != text {
            textView.text = text
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        onTextChange(textView.text ?? "")
    }

    private func configureLayout() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.font = ParcelTypography.settingsURLFont
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.keyboardType = .URL
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self

        contentView.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }
}

private final class SettingsLinkFooterView: UICollectionReusableView {
    private let iconImageView = UIImageView()
    private let messageLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(isValid: Bool) {
        if isValid {
            iconImageView.isHidden = true
            messageLabel.text = String(
                localized: "The Open Duoduo Station button opens this link. Change it if you find a link that opens the identity code directly."
            )
            messageLabel.textColor = .secondaryLabel
        } else {
            iconImageView.isHidden = false
            messageLabel.text = String(
                localized: "Enter a link that starts with an app scheme, such as pinduoduo://"
            )
            messageLabel.textColor = .label
        }
    }

    private func configureLayout() {
        let symbolConfig = UIImage.SymbolConfiguration(textStyle: .footnote, scale: .medium)
        iconImageView.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: symbolConfig)
        iconImageView.tintColor = .systemRed
        iconImageView.adjustsImageSizeForAccessibilityContentSizeCategory = true
        iconImageView.setContentHuggingPriority(.required, for: .horizontal)
        iconImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        iconImageView.isHidden = true

        messageLabel.font = .preferredFont(forTextStyle: .footnote)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0

        let stackView = UIStackView(arrangedSubviews: [iconImageView, messageLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.spacing = 6

        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }
}
