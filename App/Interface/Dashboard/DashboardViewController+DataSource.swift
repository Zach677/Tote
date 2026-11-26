import Core
import Foundation
import UIKit

nonisolated enum DashboardSection: Hashable {
    case duoduoAction
    case channel(PickupChannel)
    case awaitingCode
    case empty
    case pickedUp
}

nonisolated enum DashboardItem: Hashable {
    case duoduoAction
    case parcel(Parcel.ID)
    case empty(isPending: Bool)
}

extension DashboardViewController {
    func configureDataSource() {
        let duoduoRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Void> { cell, _, _ in
            cell.configurationUpdateHandler = { cell, state in
                guard let listCell = cell as? UICollectionViewListCell else { return }
                var content = UIListContentConfiguration.subtitleCell()
                content.image = PickupChannel.duoduo.iconTileImage(
                    baseSize: 36,
                    maxSize: 44,
                    compatibleWith: state.traitCollection
                )
                content.text = String(localized: "Open Duoduo Station")
                content.textProperties.font = .preferredFont(forTextStyle: .headline)
                content.textProperties.color = .label
                content.textProperties.adjustsFontForContentSizeCategory = true
                content.secondaryText = String(localized: "Pickup list and identity code")
                content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
                content.secondaryTextProperties.color = .secondaryLabel
                content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
                content.secondaryTextProperties.numberOfLines = 2
                content.imageToTextPadding = 12
                listCell.contentConfiguration = content
            }
            cell.accessories = [Self.makeSymbolAccessory(named: "arrow.up.forward.app", tintColor: .tintColor)]
            cell.accessibilityHint = String(localized: "Opens Pinduoduo")
        }

        let parcelRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Parcel.ID> { [weak self] cell, _, parcelID in
            guard let self, let parcel = parcelsByID[parcelID] else { return }
            configureParcelCell(cell, with: parcel)
        }

        let emptyRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Bool> { [weak self] cell, _, isPending in
            var config = UIContentUnavailableConfiguration.empty()
            config.image = UIImage(systemName: "shippingbox")
            if isPending {
                config.text = String(localized: "No Parcels to Pick Up")
                config.secondaryText = String(localized: "Add a pickup message to see its code here.")
                var buttonConfig = UIButton.Configuration.tinted()
                buttonConfig.cornerStyle = .capsule
                buttonConfig.title = String(localized: "Add Parcel")
                config.button = buttonConfig
                config.buttonProperties.primaryAction = UIAction { [weak self] _ in
                    self?.presentQuickAdd()
                }
            } else {
                config.text = String(localized: "No Picked-Up Parcels")
                config.secondaryText = String(localized: "Parcels you pick up appear here.")
            }
            cell.contentConfiguration = config
            cell.backgroundConfiguration = .clear()
            cell.accessories = []
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<DashboardSectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] headerView, _, indexPath in
            guard let self, let section = dataSource.sectionIdentifier(for: indexPath.section) else { return }
            configureSectionHeader(headerView, for: section)
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { footerCell, _, _ in
            var config = UIListContentConfiguration.footer()
            config.text = String(localized: "Swipe left on a parcel to restore it.")
            config.textProperties.font = .preferredFont(forTextStyle: .footnote)
            config.textProperties.color = .secondaryLabel
            footerCell.contentConfiguration = config
        }

        dataSource = UICollectionViewDiffableDataSource<DashboardSection, DashboardItem>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            switch item {
            case .duoduoAction:
                collectionView.dequeueConfiguredReusableCell(using: duoduoRegistration, for: indexPath, item: ())
            case let .parcel(parcelID):
                collectionView.dequeueConfiguredReusableCell(using: parcelRegistration, for: indexPath, item: parcelID)
            case let .empty(isPending):
                collectionView.dequeueConfiguredReusableCell(using: emptyRegistration, for: indexPath, item: isPending)
            }
        }

        dataSource.supplementaryViewProvider = { collectionView, elementKind, indexPath in
            if elementKind == UICollectionView.elementKindSectionHeader {
                return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
            }
            if elementKind == UICollectionView.elementKindSectionFooter {
                return collectionView.dequeueConfiguredReusableSupplementary(using: footerRegistration, for: indexPath)
            }
            return nil
        }
    }

    func applySnapshot(
        animatingDifferences: Bool,
        scrollToParcelID: Parcel.ID? = nil
    ) {
        let existingItems = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<DashboardSection, DashboardItem>()

        switch selectedSegment {
        case .pending:
            snapshot.appendSections([.duoduoAction])
            snapshot.appendItems([.duoduoAction], toSection: .duoduoAction)

            if groups.hasPendingParcels {
                for section in groups.channelSections {
                    let sectionID = DashboardSection.channel(section.channel)
                    snapshot.appendSections([sectionID])
                    snapshot.appendItems(section.parcels.map { .parcel($0.id) }, toSection: sectionID)
                }

                if !groups.awaitingCode.isEmpty {
                    snapshot.appendSections([.awaitingCode])
                    snapshot.appendItems(groups.awaitingCode.map { .parcel($0.id) }, toSection: .awaitingCode)
                }
            } else {
                snapshot.appendSections([.empty])
                snapshot.appendItems([.empty(isPending: true)], toSection: .empty)
            }

        case .pickedUp:
            if groups.hasPickedUpParcels {
                snapshot.appendSections([.pickedUp])
                snapshot.appendItems(groups.pickedUp.map { .parcel($0.id) }, toSection: .pickedUp)
            } else {
                snapshot.appendSections([.empty])
                snapshot.appendItems([.empty(isPending: false)], toSection: .empty)
            }
        }

        let itemsToReconfigure = snapshot.itemIdentifiers.filter { item in
            if case .parcel = item {
                return existingItems.contains(item)
            }
            return false
        }
        if !itemsToReconfigure.isEmpty {
            snapshot.reconfigureItems(itemsToReconfigure)
        }

        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
        refreshVisibleSectionHeaders()

        if let scrollToParcelID,
           let indexPath = dataSource.indexPath(for: .parcel(scrollToParcelID))
        {
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animatingDifferences)
        }
    }
}

private extension DashboardViewController {
    func refreshVisibleSectionHeaders() {
        let visiblePaths = collectionView.indexPathsForVisibleSupplementaryElements(
            ofKind: UICollectionView.elementKindSectionHeader
        )
        for indexPath in visiblePaths {
            guard let headerView = collectionView.supplementaryView(
                forElementKind: UICollectionView.elementKindSectionHeader,
                at: indexPath
            ) as? DashboardSectionHeaderView,
                let section = dataSource.sectionIdentifier(for: indexPath.section)
            else { continue }

            configureSectionHeader(headerView, for: section)
        }
    }

    func configureSectionHeader(_ headerView: DashboardSectionHeaderView, for section: DashboardSection) {
        switch section {
        case let .channel(channel):
            let count = groups.channelSections.first { $0.channel == channel }?.parcels.count ?? 0
            headerView.configure(
                symbolName: channel.symbolName,
                symbolTintColor: channel.tintColor,
                title: channel.localizedName,
                titleColor: .label,
                count: count
            )
        case .awaitingCode:
            headerView.configure(
                symbolName: "clock",
                symbolTintColor: .secondaryLabel,
                title: String(localized: "Waiting for Pickup Code"),
                titleColor: .secondaryLabel,
                count: groups.awaitingCode.count
            )
        case .duoduoAction, .empty, .pickedUp:
            break
        }
    }

    func configureParcelCell(_ cell: UICollectionViewListCell, with parcel: Parcel) {
        var content = UIListContentConfiguration.subtitleCell()
        content.textProperties.numberOfLines = 0
        content.textProperties.lineBreakMode = .byCharWrapping
        content.textProperties.adjustsFontForContentSizeCategory = true
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        content.secondaryTextProperties.numberOfLines = 3
        content.textToSecondaryTextVerticalPadding = 4

        if parcel.isPickedUp {
            if parcel.hasPickupCode {
                content.text = parcel.pickupCode
                content.textProperties.font = ParcelTypography.pickedUpCodeFont
            } else {
                content.text = parcel.trackingNumber
                content.textProperties.font = ParcelTypography.trackingNumberFont
            }
            content.textProperties.color = .secondaryLabel
            content.secondaryText = joinedDetailParts([
                parcel.channel.localizedName,
                parcel.stationLabel,
                relativePickedUpDate(for: parcel.pickedUpAt),
            ])
            cell.accessories = []
            cell.accessibilityHint = parcel.hasPickupCode
                ? String(localized: "Copy pickup code")
                : String(localized: "Copy tracking number")
        } else if parcel.isTrackingOnly {
            content.text = parcel.trackingNumber
            content.textProperties.font = ParcelTypography.trackingNumberFont
            content.textProperties.color = .label
            content.secondaryText = joinedDetailParts([
                parcel.channel == .other ? "" : parcel.channel.localizedName,
                parcel.note,
                String(localized: "No pickup code yet"),
            ])
            cell.accessories = [Self.makeSymbolAccessory(named: "arrow.up.forward.app", tintColor: .tintColor)]
            cell.accessibilityHint = String(localized: "Copy tracking number and open Duoduo")
        } else if parcel.channel == .yixiaoji {
            content.text = parcel.pickupCode
            content.textProperties.font = ParcelTypography.pendingPickupCodeFont
            content.textProperties.color = .label
            let baseDetails = joinedDetailParts([parcel.stationLabel, parcel.note])
            content.secondaryText = baseDetails ?? (parcel.trackingNumber.isEmpty ? nil : parcel.trackingNumber)
            cell.accessories = [Self.makeSymbolAccessory(named: "arrow.right", tintColor: .tintColor)]
            cell.accessibilityHint = String(localized: "Copy pickup code and open Yixiaoji")
        } else {
            content.text = parcel.pickupCode
            content.textProperties.font = ParcelTypography.pendingPickupCodeFont
            content.textProperties.color = .label
            content.secondaryText = joinedDetailParts([
                parcel.stationLabel,
                parcel.note,
                parcel.trackingNumber,
            ])
            cell.accessories = [Self.makeSymbolAccessory(named: "doc.on.doc", tintColor: .tertiaryLabel)]
            cell.accessibilityHint = String(localized: "Copy pickup code")
        }

        cell.contentConfiguration = content
        cell.backgroundConfiguration = nil
    }

    func joinedDetailParts(_ parts: [String]) -> String? {
        let joined = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    func relativePickedUpDate(for date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(.relative(presentation: .named))
    }

    static func makeSymbolAccessory(named symbolName: String, tintColor: UIColor) -> UICellAccessory {
        let config = UIImage.SymbolConfiguration(textStyle: .body, scale: .medium)
        let imageView = UIImageView(image: UIImage(systemName: symbolName, withConfiguration: config))
        imageView.tintColor = tintColor
        imageView.adjustsImageSizeForAccessibilityContentSizeCategory = true
        imageView.contentMode = .scaleAspectFit
        return .customView(configuration: .init(customView: imageView, placement: .trailing(displayed: .always)))
    }
}

extension DashboardViewController: UICollectionViewDelegate {
    func collectionView(_: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        if case .empty = item {
            return false
        }
        return true
    }

    func collectionView(_: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        if case .empty = item {
            return false
        }
        return true
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        let sourceView = collectionView.cellForItem(at: indexPath) ?? collectionView
        handleSelection(of: item, sourceView: sourceView)
    }
}
