import Core
import Foundation
import UIKit

nonisolated enum SettingsSection: Hashable {
    case yixiaoji
    case shortcuts
}

nonisolated enum SettingsItem: Hashable {
    case yixiaojiSignIn
    case yixiaojiAccount
    case yixiaojiSyncNow
    case yixiaojiOpenSafari
    case yixiaojiSignOut
    case shortcut(PresetShortcut)
}

final class SettingsViewController: UIViewController {
    let dependencies: AppDependencies
    var onParcelsChanged: () -> Void = {}
    private(set) var isSyncingYixiaoji = false
    private(set) var lastSyncSummary: String?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SettingsSection, SettingsItem>!
    private var syncTask: Task<Void, Never>?

    var isYixiaojiSignedIn: Bool {
        dependencies.yixiaoji.currentSession != nil
    }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
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

    func openShortcut(_ preset: PresetShortcut) {
        dependencies.launcher.open(preset.iCloudURL) { [weak self] success in
            guard let self, !success else { return }
            presentShortcutOpenFailureAlert()
        }
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
    }

    func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            config.headerMode = .supplementary
            config.footerMode = .supplementary
            return NSCollectionLayoutSection.list(using: config, layoutEnvironment: layoutEnvironment)
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
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
            case .shortcuts:
                config.text = String(localized: "Shortcuts")
            }
            headerCell.contentConfiguration = config
        }

        let yixiaojiFooterRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] footerCell, _, _ in
            guard let self else { return }
            configureYixiaojiFooter(footerCell)
        }

        let shortcutsFooterRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { footerCell, _, _ in
            var config = UIListContentConfiguration.footer()
            config.textProperties.font = .preferredFont(forTextStyle: .footnote)
            config.textProperties.color = .secondaryLabel
            config.text = String(
                localized: "Tap to add in Apple Shortcuts. For automatic SMS capture, create a Message automation in Shortcuts using “Add Parcels from Text”."
            )
            footerCell.contentConfiguration = config
        }

        dataSource = UICollectionViewDiffableDataSource<SettingsSection, SettingsItem>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: itemRegistration, for: indexPath, item: item)
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
                if section == .shortcuts {
                    return collectionView.dequeueConfiguredReusableSupplementary(using: shortcutsFooterRegistration, for: indexPath)
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

        case let .shortcut(preset):
            var content = UIListContentConfiguration.subtitleCell()
            content.image = UIImage(systemName: preset.symbolName)
            content.imageProperties.tintColor = .tintColor
            content.text = preset.title
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.textProperties.adjustsFontForContentSizeCategory = true
            content.secondaryText = preset.subtitle
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
            content.secondaryTextProperties.color = .secondaryLabel
            content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
            content.secondaryTextProperties.numberOfLines = 0
            cell.contentConfiguration = content
            let symbol = UIImageView(image: UIImage(systemName: "arrow.up.forward.app"))
            symbol.tintColor = .tertiaryLabel
            cell.accessories = [.customView(configuration: .init(customView: symbol, placement: .trailing()))]
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
        snapshot.appendSections([.yixiaoji, .shortcuts])

        let yixiaojiItems: [SettingsItem] = if isYixiaojiSignedIn {
            [.yixiaojiAccount, .yixiaojiSyncNow, .yixiaojiOpenSafari, .yixiaojiSignOut]
        } else {
            [.yixiaojiSignIn, .yixiaojiOpenSafari]
        }
        snapshot.appendItems(yixiaojiItems, toSection: .yixiaoji)
        snapshot.appendItems(PresetShortcut.allCases.map(SettingsItem.shortcut), toSection: .shortcuts)

        let reconfigureItems = snapshot.itemIdentifiers.filter { existingItems.contains($0) }
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

    func presentShortcutOpenFailureAlert() {
        let alert = UIAlertController(
            title: String(localized: "Can’t Open Shortcuts"),
            message: String(localized: "Check your connection and make sure Apple Shortcuts is installed."),
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
        case let .shortcut(preset):
            openShortcut(preset)
        case .yixiaojiAccount:
            break
        }
    }

    private func isActionEnabled(_ item: SettingsItem) -> Bool {
        switch item {
        case .yixiaojiAccount:
            false
        case .yixiaojiSignIn, .yixiaojiOpenSafari, .yixiaojiSignOut, .shortcut:
            true
        case .yixiaojiSyncNow:
            !isSyncingYixiaoji
        }
    }
}
