import Core
import Foundation
import UIKit

nonisolated enum QuickAddSection: Hashable {
    case input
    case manualEntry
    case results
    case unparsed
}

nonisolated enum QuickAddItem: Hashable {
    case input
    case manualEntry
    case draft(UUID)
    case unparsed
}

final class QuickAddViewController: UIViewController {
    let dependencies: AppDependencies
    let existingParcels: [Parcel]
    let onComplete: (AddParcelsResult) -> Void

    private(set) var inputText = ""
    private(set) var drafts: [ParsedParcelDraft] = []
    private(set) var classifiedDrafts: [ClassifiedDraft] = []

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<QuickAddSection, QuickAddItem>!
    private var addButton: UIBarButtonItem!
    private weak var inputCell: QuickAddInputCell?

    var addableDrafts: [ParsedParcelDraft] {
        classifiedDrafts.compactMap { item in
            switch item.kind {
            case .new, .upgradeTrackingOnly:
                item.draft
            case .duplicate:
                nil
            }
        }
    }

    var duplicateCount: Int {
        classifiedDrafts.count(where: {
            if case .duplicate = $0.kind {
                return true
            }
            return false
        })
    }

    var hasUnsavedDrafts: Bool {
        !addableDrafts.isEmpty
    }

    init(
        dependencies: AppDependencies,
        existingParcels: [Parcel],
        onComplete: @escaping (AddParcelsResult) -> Void
    ) {
        self.dependencies = dependencies
        self.existingParcels = existingParcels
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        pasteConfiguration = UIPasteConfiguration(forAccepting: String.self)
        configureNavigationBar()
        configureCollectionView()
        configureDataSource()
        applySnapshot(animatingDifferences: false)
        updateActionState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.presentationController?.delegate = self
        syncModalPresentationLock()
    }

    override func paste(itemProviders: [NSItemProvider]) {
        guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return
        }

        provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
            guard let pasted = object as? String else { return }
            Task { @MainActor [weak self] in
                self?.updateInputText(pasted, syncInputCell: true)
            }
        }
    }

    func updateInputText(_ text: String, syncInputCell: Bool = true) {
        inputText = text
        drafts = dependencies.parser.parse(text)
        classifiedDrafts = dependencies.deduplicator.classify(drafts, against: existingParcels)
        if syncInputCell {
            inputCell?.setText(text)
        }
        updateActionState()
        applySnapshot(animatingDifferences: false)
        collectionView.performBatchUpdates(nil)
    }

    func updateDraft(_ updatedDraft: ParsedParcelDraft) {
        guard let index = drafts.firstIndex(where: { $0.id == updatedDraft.id }) else { return }
        drafts[index] = updatedDraft
        classifiedDrafts = dependencies.deduplicator.classify(drafts, against: existingParcels)
        updateActionState()
        applySnapshot(animatingDifferences: false)
    }

    @discardableResult
    func commitParsedDrafts() -> AddParcelsResult? {
        let toAdd = addableDrafts
        guard !toAdd.isEmpty else { return nil }

        do {
            let result = try dependencies.parcelStore.add(toAdd, source: .pasted)
            onComplete(result)
            dismiss(animated: true)
            return result
        } catch {
            presentStoreErrorAlert()
            return nil
        }
    }

    @discardableResult
    func commitManualDraft(_ draft: ParsedParcelDraft) -> AddParcelsResult? {
        guard draft.isValid else { return nil }

        do {
            let result = try dependencies.parcelStore.add([draft], source: .manual)
            if result.added.isEmpty, result.updated.isEmpty, result.skippedDuplicateCount > 0 {
                presentManualDuplicateAlert()
                return result
            }
            onComplete(result)
            dismiss(animated: true)
            return result
        } catch {
            presentStoreErrorAlert()
            return nil
        }
    }

    func pushManualEntry() {
        let editor = EditParcelViewController(mode: .new) { [weak self] draft in
            self?.commitManualDraft(draft)
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    func pushEditDraft(_ draft: ParsedParcelDraft) {
        let editor = EditParcelViewController(mode: .edit(draft)) { [weak self] updated in
            self?.updateDraft(updated)
            self?.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    func currentSections() -> [QuickAddSection] {
        dataSource.snapshot().sectionIdentifiers
    }

    func currentItems(in section: QuickAddSection) -> [QuickAddItem] {
        dataSource.snapshot().itemIdentifiers(inSection: section)
    }
}

private extension QuickAddViewController {
    func configureNavigationBar() {
        title = String(localized: "Add Parcels")
        navigationItem.largeTitleDisplayMode = .never

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.handleCloseTapped()
            }
        )

        addButton = UIBarButtonItem(
            title: String(localized: "Add"),
            style: .prominent,
            target: self,
            action: #selector(handleAddTapped)
        )
        addButton.isEnabled = false
        navigationItem.rightBarButtonItem = addButton
    }

    func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            let section = self?.dataSource?.sectionIdentifier(for: sectionIndex)
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            switch section {
            case .input:
                config.headerMode = .none
                config.footerMode = .supplementary
            case .results:
                config.headerMode = .supplementary
                config.footerMode = .supplementary
            case .manualEntry, .unparsed, .none:
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
        let inputRegistration = UICollectionView.CellRegistration<QuickAddInputCell, Void> { [weak self] cell, _, _ in
            guard let self else { return }
            inputCell = cell
            cell.configure(
                text: inputText,
                pasteTarget: self,
                onTextChange: { [weak self] text in
                    self?.updateInputText(text, syncInputCell: false)
                },
                onClear: { [weak self] in
                    self?.updateInputText("", syncInputCell: true)
                }
            )
        }

        let manualRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Void> { cell, _, _ in
            var content = UIListContentConfiguration.cell()
            content.image = UIImage(systemName: "square.and.pencil")
            content.imageProperties.tintColor = .tintColor
            content.text = String(localized: "Enter Manually")
            content.textProperties.color = .tintColor
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.textProperties.adjustsFontForContentSizeCategory = true
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        }

        let draftRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, UUID> { [weak self] cell, _, draftID in
            guard let self,
                  let item = classifiedDrafts.first(where: { $0.id == draftID })
            else { return }
            configureDraftCell(cell, with: item)
        }

        let unparsedRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Void> { [weak self] cell, _, _ in
            var config = UIContentUnavailableConfiguration.empty()
            config.image = UIImage(systemName: "doc.text.magnifyingglass")
            config.text = String(localized: "No Pickup Code Found")
            config.secondaryText = String(localized: "Check the message, or enter the parcel yourself.")
            var buttonConfig = UIButton.Configuration.tinted()
            buttonConfig.cornerStyle = .capsule
            buttonConfig.title = String(localized: "Enter Manually")
            config.button = buttonConfig
            config.buttonProperties.primaryAction = UIAction { [weak self] _ in
                self?.pushManualEntry()
            }
            cell.contentConfiguration = config
            cell.backgroundConfiguration = .clear()
            cell.accessories = []
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<QuickAddResultsHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] headerView, _, _ in
            guard let self else { return }
            headerView.configure(
                totalCount: classifiedDrafts.count,
                duplicateCount: duplicateCount
            )
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] footerCell, _, indexPath in
            guard let self,
                  let section = dataSource.sectionIdentifier(for: indexPath.section)
            else { return }
            var config = UIListContentConfiguration.footer()
            config.textProperties.font = .preferredFont(forTextStyle: .footnote)
            config.textProperties.color = .secondaryLabel
            switch section {
            case .input:
                config.text = String(localized: "Tote reads the text only when you tap Paste. Nothing leaves your iPhone.")
            case .results:
                if duplicateCount > 0 {
                    config.text = String(localized: "Parcels already in your list are not added again.")
                } else {
                    config.text = String(localized: "Tap a parcel to change its details.")
                }
            case .manualEntry, .unparsed:
                config.text = nil
            }
            footerCell.contentConfiguration = config
        }

        dataSource = UICollectionViewDiffableDataSource<QuickAddSection, QuickAddItem>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            switch item {
            case .input:
                collectionView.dequeueConfiguredReusableCell(using: inputRegistration, for: indexPath, item: ())
            case .manualEntry:
                collectionView.dequeueConfiguredReusableCell(using: manualRegistration, for: indexPath, item: ())
            case let .draft(id):
                collectionView.dequeueConfiguredReusableCell(using: draftRegistration, for: indexPath, item: id)
            case .unparsed:
                collectionView.dequeueConfiguredReusableCell(using: unparsedRegistration, for: indexPath, item: ())
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

    func configureDraftCell(_ cell: UICollectionViewListCell, with item: ClassifiedDraft) {
        let draft = item.draft
        let isDuplicate = if case .duplicate = item.kind {
            true
        } else {
            false
        }

        cell.configurationUpdateHandler = { cell, state in
            guard let listCell = cell as? UICollectionViewListCell else { return }
            var content = UIListContentConfiguration.subtitleCell()
            content.image = draft.channel.iconTileImage(
                baseSize: 30,
                maxSize: 40,
                compatibleWith: state.traitCollection
            )
            content.imageToTextPadding = 12
            if draft.hasPickupCode {
                content.text = draft.pickupCode
                content.textProperties.font = ParcelTypography.previewCodeFont
            } else {
                content.text = draft.trackingNumber
                content.textProperties.font = ParcelTypography.trackingNumberFont
            }
            content.textProperties.color = .label
            content.textProperties.numberOfLines = 0
            content.textProperties.lineBreakMode = .byCharWrapping
            content.textProperties.adjustsFontForContentSizeCategory = true

            if isDuplicate {
                content.secondaryText = String(localized: "Already in your list")
            } else {
                let parts = [draft.channel.localizedName, draft.stationLabel, draft.note]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                content.secondaryText = parts.joined(separator: " · ")
            }
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
            content.secondaryTextProperties.color = .secondaryLabel
            content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
            content.secondaryTextProperties.numberOfLines = 2
            listCell.contentConfiguration = content
            listCell.contentView.alpha = isDuplicate ? 0.45 : 1.0
        }

        cell.accessories = isDuplicate ? [] : [.disclosureIndicator()]
    }

    func applySnapshot(animatingDifferences: Bool) {
        let existingItems = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<QuickAddSection, QuickAddItem>()

        snapshot.appendSections([.input])
        snapshot.appendItems([.input], toSection: .input)

        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !classifiedDrafts.isEmpty {
            snapshot.appendSections([.results])
            snapshot.appendItems(classifiedDrafts.map { .draft($0.id) }, toSection: .results)
        } else if trimmedInput.isEmpty {
            snapshot.appendSections([.manualEntry])
            snapshot.appendItems([.manualEntry], toSection: .manualEntry)
        } else {
            snapshot.appendSections([.unparsed])
            snapshot.appendItems([.unparsed], toSection: .unparsed)
        }

        let draftsToReconfigure = snapshot.itemIdentifiers.filter { item in
            if case .draft = item {
                return existingItems.contains(item)
            }
            return false
        }
        if !draftsToReconfigure.isEmpty {
            snapshot.reconfigureItems(draftsToReconfigure)
        }

        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
        refreshResultsSupplementaryViews()
    }

    func refreshResultsSupplementaryViews() {
        guard let resultsSectionIndex = dataSource.snapshot().indexOfSection(.results) else { return }
        let indexPath = IndexPath(item: 0, section: resultsSectionIndex)
        if let header = collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: indexPath
        ) as? QuickAddResultsHeaderView {
            header.configure(totalCount: classifiedDrafts.count, duplicateCount: duplicateCount)
        }
        if let footer = collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionFooter,
            at: indexPath
        ) as? UICollectionViewListCell {
            var config = UIListContentConfiguration.footer()
            config.textProperties.font = .preferredFont(forTextStyle: .footnote)
            config.textProperties.color = .secondaryLabel
            if duplicateCount > 0 {
                config.text = String(localized: "Parcels already in your list are not added again.")
            } else {
                config.text = String(localized: "Tap a parcel to change its details.")
            }
            footer.contentConfiguration = config
        }
    }

    func updateActionState() {
        let count = addableDrafts.count
        addButton.isEnabled = count > 0
        if count > 1 {
            addButton.title = String(localized: "Add \(count)")
        } else {
            addButton.title = String(localized: "Add")
        }
        syncModalPresentationLock()
    }

    func syncModalPresentationLock() {
        let locked = hasUnsavedDrafts
        isModalInPresentation = locked
        navigationController?.isModalInPresentation = locked
    }

    @objc func handleAddTapped() {
        commitParsedDrafts()
    }

    func handleCloseTapped() {
        if hasUnsavedDrafts {
            presentDiscardConfirmation()
        } else {
            dismiss(animated: true)
        }
    }

    func presentDiscardConfirmation() {
        let alert = UIAlertController(
            title: String(localized: "Discard These Parcels?"),
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(
            UIAlertAction(title: String(localized: "Discard"), style: .destructive) { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
        alert.addAction(UIAlertAction(title: String(localized: "Keep Editing"), style: .cancel))
        alert.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        present(alert, animated: true)
    }

    func presentManualDuplicateAlert() {
        let alert = UIAlertController(
            title: String(localized: "Already in your list"),
            message: String(localized: "Parcels already in your list are not added again."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        let host = navigationController?.topViewController ?? self
        guard host.presentedViewController == nil, host.viewIfLoaded?.window != nil else { return }
        host.present(alert, animated: true)
    }

    func presentStoreErrorAlert() {
        let alert = UIAlertController(
            title: String(localized: "Couldn’t Save Parcels"),
            message: String(localized: "Please try again."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        guard presentedViewController == nil, viewIfLoaded?.window != nil else { return }
        present(alert, animated: true)
    }
}

extension QuickAddViewController: UICollectionViewDelegate {
    func collectionView(_: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        return isSelectable(item)
    }

    func collectionView(_: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        return isSelectable(item)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case .manualEntry:
            pushManualEntry()
        case let .draft(draftID):
            guard let classified = classifiedDrafts.first(where: { $0.id == draftID }) else { return }
            if case .duplicate = classified.kind {
                return
            }
            pushEditDraft(classified.draft)
        case .input, .unparsed:
            break
        }
    }

    private func isSelectable(_ item: QuickAddItem) -> Bool {
        switch item {
        case .manualEntry:
            return true
        case let .draft(draftID):
            guard let classified = classifiedDrafts.first(where: { $0.id == draftID }) else { return false }
            if case .duplicate = classified.kind {
                return false
            }
            return true
        case .input, .unparsed:
            return false
        }
    }
}

extension QuickAddViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidAttemptToDismiss(_: UIPresentationController) {
        presentDiscardConfirmation()
    }
}
