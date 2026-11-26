import Core
import UIKit

nonisolated enum EditParcelSection: Hashable {
    case primary
    case details
}

nonisolated enum EditParcelField: Hashable {
    case channel
    case pickupCode
    case station
    case trackingNumber
    case note
}

final class EditParcelViewController: UIViewController {
    enum Mode {
        case new
        case edit(ParsedParcelDraft)
    }

    private let mode: Mode
    private let onSave: (ParsedParcelDraft) -> Void
    private(set) var draft: ParsedParcelDraft

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<EditParcelSection, EditParcelField>!
    private var saveButton: UIBarButtonItem!

    init(mode: Mode, onSave: @escaping (ParsedParcelDraft) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .new:
            draft = ParsedParcelDraft(channel: .other)
        case let .edit(existing):
            draft = existing
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        configureNavigationBar()
        configureCollectionView()
        configureDataSource()
        applySnapshot()
        updateSaveButtonState()
    }

    func selectChannel(_ channel: PickupChannel) {
        draft.channel = channel
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([.channel])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func updateField(_ field: EditParcelField, value: String) {
        switch field {
        case .pickupCode:
            draft.pickupCode = value
        case .station:
            draft.stationLabel = value
        case .trackingNumber:
            draft.trackingNumber = value
        case .note:
            draft.note = value
        case .channel:
            break
        }
        updateSaveButtonState()
    }

    func commitSave() {
        guard draft.isValid else { return }
        onSave(draft)
    }

    var isSaveEnabled: Bool {
        saveButton?.isEnabled ?? draft.isValid
    }
}

private extension EditParcelViewController {
    func configureNavigationBar() {
        switch mode {
        case .new:
            title = String(localized: "New Parcel")
        case .edit:
            title = String(localized: "Edit Parcel")
        }
        navigationItem.largeTitleDisplayMode = .never

        saveButton = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in
                self?.commitSave()
            }
        )
        saveButton.style = .prominent
        navigationItem.rightBarButtonItem = saveButton
    }

    func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            let section = self?.dataSource?.sectionIdentifier(for: sectionIndex)
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            config.headerMode = .none
            config.footerMode = section == .details ? .supplementary : .none
            return NSCollectionLayoutSection.list(using: config, layoutEnvironment: layoutEnvironment)
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.keyboardDismissMode = .interactive
        collectionView.allowsSelection = false

        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func configureDataSource() {
        let channelRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Void> { [weak self] cell, _, _ in
            guard let self else { return }
            var content = UIListContentConfiguration.cell()
            content.image = draft.channel.symbolImage()
            content.imageProperties.tintColor = draft.channel.tintColor
            content.text = String(localized: "Channel")
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.textProperties.adjustsFontForContentSizeCategory = true
            cell.contentConfiguration = content
            cell.accessories = [.popUpMenu(makeChannelMenu())]
        }

        let textFieldRegistration = UICollectionView.CellRegistration<FormTextFieldCell, EditParcelField> { [weak self] cell, _, field in
            guard let self else { return }
            configureTextFieldCell(cell, for: field)
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { footerCell, _, _ in
            var config = UIListContentConfiguration.footer()
            config.text = String(localized: "Enter a pickup code, a tracking number, or both.")
            config.textProperties.font = .preferredFont(forTextStyle: .footnote)
            config.textProperties.color = .secondaryLabel
            footerCell.contentConfiguration = config
        }

        dataSource = UICollectionViewDiffableDataSource<EditParcelSection, EditParcelField>(
            collectionView: collectionView
        ) { collectionView, indexPath, field in
            switch field {
            case .channel:
                collectionView.dequeueConfiguredReusableCell(using: channelRegistration, for: indexPath, item: ())
            case .pickupCode, .station, .trackingNumber, .note:
                collectionView.dequeueConfiguredReusableCell(using: textFieldRegistration, for: indexPath, item: field)
            }
        }

        dataSource.supplementaryViewProvider = { collectionView, elementKind, indexPath in
            guard elementKind == UICollectionView.elementKindSectionFooter else { return nil }
            return collectionView.dequeueConfiguredReusableSupplementary(using: footerRegistration, for: indexPath)
        }
    }

    func configureTextFieldCell(_ cell: FormTextFieldCell, for field: EditParcelField) {
        switch field {
        case .pickupCode:
            cell.configure(
                title: String(localized: "Pickup Code"),
                text: draft.pickupCode,
                placeholder: String(localized: "Optional"),
                font: ParcelTypography.previewCodeFont,
                keyboardType: .asciiCapable,
                autocapitalizationType: .allCharacters,
                disableCorrections: true
            ) { [weak self] text in
                self?.updateField(.pickupCode, value: text)
            }
        case .station:
            cell.configure(
                title: String(localized: "Station"),
                text: draft.stationLabel,
                placeholder: String(localized: "Optional"),
                font: .preferredFont(forTextStyle: .body),
                keyboardType: .default,
                autocapitalizationType: .words,
                disableCorrections: false
            ) { [weak self] text in
                self?.updateField(.station, value: text)
            }
        case .trackingNumber:
            cell.configure(
                title: String(localized: "Tracking Number"),
                text: draft.trackingNumber,
                placeholder: String(localized: "Optional"),
                font: ParcelTypography.trackingNumberFont,
                keyboardType: .asciiCapable,
                autocapitalizationType: .allCharacters,
                disableCorrections: true
            ) { [weak self] text in
                self?.updateField(.trackingNumber, value: text)
            }
        case .note:
            cell.configure(
                title: String(localized: "Note"),
                text: draft.note,
                placeholder: String(localized: "Optional"),
                font: .preferredFont(forTextStyle: .body),
                keyboardType: .default,
                autocapitalizationType: .sentences,
                disableCorrections: false
            ) { [weak self] text in
                self?.updateField(.note, value: text)
            }
        case .channel:
            break
        }
    }

    func makeChannelMenu() -> UIMenu {
        let actions = PickupChannel.allCases.map { channel in
            UIAction(
                title: channel.localizedName,
                image: channel.symbolImage(),
                state: channel == draft.channel ? .on : .off
            ) { [weak self] _ in
                self?.selectChannel(channel)
            }
        }
        return UIMenu(options: .singleSelection, children: actions)
    }

    func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<EditParcelSection, EditParcelField>()
        snapshot.appendSections([.primary, .details])
        snapshot.appendItems([.channel, .pickupCode], toSection: .primary)
        snapshot.appendItems([.station, .trackingNumber, .note], toSection: .details)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func updateSaveButtonState() {
        saveButton.isEnabled = draft.isValid
    }
}

private final class FormTextFieldCell: UICollectionViewListCell {
    private let titleLabel = UILabel()
    private let textField = UITextField()
    private var onTextChange: (String) -> Void = { _ in }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        title: String,
        text: String,
        placeholder: String,
        font: UIFont,
        keyboardType: UIKeyboardType,
        autocapitalizationType: UITextAutocapitalizationType,
        disableCorrections: Bool,
        onTextChange: @escaping (String) -> Void
    ) {
        titleLabel.text = title
        textField.text = text
        textField.placeholder = placeholder
        textField.font = font
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = autocapitalizationType
        textField.autocorrectionType = disableCorrections ? .no : .default
        textField.smartDashesType = disableCorrections ? .no : .default
        textField.smartQuotesType = disableCorrections ? .no : .default
        self.onTextChange = onTextChange
    }

    private func configureLayout() {
        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel
        titleLabel.numberOfLines = 0

        textField.adjustsFontForContentSizeCategory = true
        textField.textColor = .label
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .done
        textField.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                onTextChange(textField.text ?? "")
            },
            for: .editingChanged
        )
        textField.addAction(
            UIAction { [weak self] _ in
                self?.textField.resignFirstResponder()
            },
            for: .primaryActionTriggered
        )

        let stackView = UIStackView(arrangedSubviews: [titleLabel, textField])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 4

        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }
}
