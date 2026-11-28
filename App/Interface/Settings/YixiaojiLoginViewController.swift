import Core
import UIKit

nonisolated enum YixiaojiLoginSection: Hashable {
    case credentials
}

nonisolated enum YixiaojiLoginField: Hashable {
    case username
    case password
}

final class YixiaojiLoginViewController: UIViewController {
    let dependencies: AppDependencies
    let onSignedIn: (YixiaojiSession) -> Void

    private(set) var username = ""
    private(set) var password = ""
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<YixiaojiLoginSection, YixiaojiLoginField>!
    private var signInButton: UIBarButtonItem!
    private var loginTask: Task<Void, Never>?

    var isSignInEnabled: Bool {
        !isSubmitting
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    init(
        dependencies: AppDependencies,
        initialUsername: String = "",
        onSignedIn: @escaping (YixiaojiSession) -> Void
    ) {
        self.dependencies = dependencies
        username = initialUsername
        self.onSignedIn = onSignedIn
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loginTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        configureNavigationBar()
        configureCollectionView()
        configureDataSource()
        applyInitialSnapshot()
        updateUIState()
    }

    func updateUsername(_ value: String) {
        username = value
        errorMessage = nil
        updateUIState()
    }

    func updatePassword(_ value: String) {
        password = value
        errorMessage = nil
        updateUIState()
    }

    @discardableResult
    func submitLogin() async -> Bool {
        guard isSignInEnabled else { return false }
        view.endEditing(true)
        isSubmitting = true
        errorMessage = nil
        updateUIState()

        defer {
            isSubmitting = false
            updateUIState()
        }

        do {
            let session = try await dependencies.yixiaoji.login(username: username, password: password)
            onSignedIn(session)
            return true
        } catch let apiError as YixiaojiAPIError {
            errorMessage = Self.localizedErrorMessage(for: apiError)
            return false
        } catch {
            errorMessage = String(localized: "Couldn’t sign in. Check your connection and try again.")
            return false
        }
    }
}

private extension YixiaojiLoginViewController {
    func configureNavigationBar() {
        title = String(localized: "Sign In to Yixiaoji")
        navigationItem.largeTitleDisplayMode = .never

        signInButton = UIBarButtonItem(
            title: String(localized: "Sign In"),
            style: .prominent,
            target: self,
            action: #selector(handleSignInTapped)
        )
        signInButton.applyProminentTitleContrast()
        navigationItem.rightBarButtonItem = signInButton
    }

    func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            config.headerMode = .none
            config.footerMode = .supplementary
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
        let fieldRegistration = UICollectionView.CellRegistration<LoginFieldCell, YixiaojiLoginField> { [weak self] cell, _, field in
            guard let self else { return }
            switch field {
            case .username:
                cell.configure(
                    title: String(localized: "Account"),
                    text: username,
                    placeholder: String(localized: "Phone or username"),
                    isSecure: false,
                    contentType: .username,
                    returnKeyType: .next,
                    onTextChange: { [weak self] text in
                        self?.updateUsername(text)
                    },
                    onReturn: {}
                )
            case .password:
                cell.configure(
                    title: String(localized: "Password"),
                    text: password,
                    placeholder: String(localized: "Password"),
                    isSecure: true,
                    contentType: .password,
                    returnKeyType: .go,
                    onTextChange: { [weak self] text in
                        self?.updatePassword(text)
                    },
                    onReturn: { [weak self] in
                        self?.handleSignInTapped()
                    }
                )
            }
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] footerCell, _, _ in
            guard let self else { return }
            configureFooter(footerCell)
        }

        dataSource = UICollectionViewDiffableDataSource<YixiaojiLoginSection, YixiaojiLoginField>(
            collectionView: collectionView
        ) { collectionView, indexPath, field in
            collectionView.dequeueConfiguredReusableCell(using: fieldRegistration, for: indexPath, item: field)
        }

        dataSource.supplementaryViewProvider = { collectionView, elementKind, indexPath in
            guard elementKind == UICollectionView.elementKindSectionFooter else { return nil }
            return collectionView.dequeueConfiguredReusableSupplementary(using: footerRegistration, for: indexPath)
        }
    }

    func applyInitialSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<YixiaojiLoginSection, YixiaojiLoginField>()
        snapshot.appendSections([.credentials])
        snapshot.appendItems([.username, .password], toSection: .credentials)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func configureFooter(_ footerCell: UICollectionViewListCell) {
        var config = UIListContentConfiguration.footer()
        config.textProperties.font = .preferredFont(forTextStyle: .footnote)
        if let errorMessage, !errorMessage.isEmpty {
            config.text = errorMessage
            config.textProperties.color = .systemRed
        } else {
            config.text = String(localized: "Your Yixiaoji session is stored only in iOS Keychain on this iPhone.")
            config.textProperties.color = .secondaryLabel
        }
        footerCell.contentConfiguration = config
    }

    func updateUIState() {
        if isSubmitting {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        } else {
            signInButton.isEnabled = isSignInEnabled
            navigationItem.rightBarButtonItem = signInButton
        }

        if let footer = collectionView?.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionFooter,
            at: IndexPath(item: 0, section: 0)
        ) as? UICollectionViewListCell {
            configureFooter(footer)
            collectionView.performBatchUpdates(nil)
        }
    }

    @objc func handleSignInTapped() {
        guard isSignInEnabled else { return }
        loginTask?.cancel()
        loginTask = Task { [weak self] in
            _ = await self?.submitLogin()
        }
    }

    static func localizedErrorMessage(for error: YixiaojiAPIError) -> String {
        switch error {
        case let .invalidCredentials(message):
            message.isEmpty ? String(localized: "Invalid account or password.") : message
        case .storageError:
            String(localized: "Couldn’t save your session securely. Please try again.")
        case let .serverError(message), let .sessionExpired(message):
            message.isEmpty ? String(localized: "Couldn’t sign in. Please try again.") : message
        case .notSignedIn, .missingCabinetSelection, .unlockUnconfirmed, .invalidResponse, .networkError:
            String(localized: "Couldn’t sign in. Check your connection and try again.")
        }
    }
}

private final class LoginFieldCell: UICollectionViewListCell {
    private let titleLabel = UILabel()
    private let textField = UITextField()
    private var onTextChange: (String) -> Void = { _ in }
    private var onReturn: () -> Void = {}

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
        isSecure: Bool,
        contentType: UITextContentType,
        returnKeyType: UIReturnKeyType,
        onTextChange: @escaping (String) -> Void,
        onReturn: @escaping () -> Void
    ) {
        titleLabel.text = title
        if textField.text != text {
            textField.text = text
        }
        textField.placeholder = placeholder
        textField.isSecureTextEntry = isSecure
        textField.textContentType = contentType
        textField.returnKeyType = returnKeyType
        self.onTextChange = onTextChange
        self.onReturn = onReturn
    }

    private func configureLayout() {
        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel

        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.textColor = .label
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.clearButtonMode = .whileEditing
        textField.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                onTextChange(textField.text ?? "")
            },
            for: .editingChanged
        )
        textField.addAction(
            UIAction { [weak self] _ in
                self?.onReturn()
            },
            for: .primaryActionTriggered
        )

        let stack = UIStackView(arrangedSubviews: [titleLabel, textField])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 4

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }
}
