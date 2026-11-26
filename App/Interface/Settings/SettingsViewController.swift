import Core
import Foundation
import UIKit

nonisolated enum SettingsSection: Hashable {
    case duoduoLink
    case actions
}

nonisolated enum SettingsItem: Hashable {
    case urlEditor
    case testLink
    case resetLink
}

final class SettingsViewController: UIViewController {
    let dependencies: AppDependencies
    private(set) var urlText: String

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SettingsSection, SettingsItem>!
    private var doneButton: UIBarButtonItem!
    private weak var editorCell: SettingsURLEditorCell?

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

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        urlText = dependencies.settings.duoduoURLString
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
        applyInitialSnapshot()
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

        doneButton = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in
                self?.saveAndDismiss()
            }
        )
        doneButton.style = .prominent
        navigationItem.rightBarButtonItem = doneButton
    }

    func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            let section = self?.dataSource?.sectionIdentifier(for: sectionIndex)
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            switch section {
            case .duoduoLink:
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

        let actionRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, SettingsItem> { [weak self] cell, _, item in
            guard let self else { return }
            var content = UIListContentConfiguration.cell()
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.textProperties.adjustsFontForContentSizeCategory = true

            switch item {
            case .testLink:
                content.text = String(localized: "Test Link")
                content.textProperties.color = isLinkValid ? .tintColor : .tertiaryLabel
            case .resetLink:
                content.text = String(localized: "Reset to Default Link")
                content.textProperties.color = canResetToDefault ? .tintColor : .tertiaryLabel
            case .urlEditor:
                break
            }

            cell.contentConfiguration = content
            cell.accessories = []
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { headerCell, _, _ in
            var config = UIListContentConfiguration.header()
            config.text = String(localized: "Duoduo Station Link")
            headerCell.contentConfiguration = config
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<SettingsLinkFooterView>(
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
            case .testLink, .resetLink:
                collectionView.dequeueConfiguredReusableCell(using: actionRegistration, for: indexPath, item: item)
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

    func applyInitialSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<SettingsSection, SettingsItem>()
        snapshot.appendSections([.duoduoLink, .actions])
        snapshot.appendItems([.urlEditor], toSection: .duoduoLink)
        snapshot.appendItems([.testLink, .resetLink], toSection: .actions)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func updateValidationUI() {
        doneButton.isEnabled = isLinkValid

        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([.testLink, .resetLink])
        dataSource.apply(snapshot, animatingDifferences: false)

        if let footer = collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionFooter,
            at: IndexPath(item: 0, section: 0)
        ) as? SettingsLinkFooterView {
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
        case .testLink:
            testCurrentLink()
        case .resetLink:
            resetToDefault()
        case .urlEditor:
            break
        }
    }

    private func isActionEnabled(_ item: SettingsItem) -> Bool {
        switch item {
        case .urlEditor:
            false
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
