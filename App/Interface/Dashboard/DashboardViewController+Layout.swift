import UIKit

extension DashboardViewController {
    func configureNavigationBar() {
        segmentedControl.selectedSegmentIndex = selectedSegment.rawValue
        segmentedControl.addTarget(self, action: #selector(handleSegmentChanged), for: .valueChanged)

        navigationItem.titleView = segmentedControl
        navigationItem.largeTitleDisplayMode = .never

        let settingsItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(handleSettingsTapped)
        )
        settingsItem.accessibilityLabel = String(localized: "Settings")
        navigationItem.leftBarButtonItem = settingsItem

        let addItem = UIBarButtonItem.prominentIconItem(
            systemName: "plus",
            accessibilityLabel: String(localized: "Add Parcel"),
            primaryAction: UIAction { [weak self] _ in
                self?.handleAddTapped()
            }
        )
        navigationItem.rightBarButtonItem = addItem
    }

    func configureCollectionView() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeCollectionViewLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.delegate = self
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl
        setCollectionView(collectionView)
    }

    func configureHierarchy() {
        copyToastView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(collectionView)
        view.addSubview(copyToastView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            copyToastView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            copyToastView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            copyToastView.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 16
            ),
            copyToastView.trailingAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -16
            ),
        ])
    }

    func makeCollectionViewLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            let sectionIdentifier = self?.dataSource?.sectionIdentifier(for: sectionIndex)
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)

            switch sectionIdentifier {
            case .channel, .awaitingCode:
                config.headerMode = .supplementary
                config.footerMode = .none
                config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                    self?.makeTrailingSwipeActions(for: indexPath, isPickedUp: false)
                }
            case .pickedUp:
                config.headerMode = .none
                config.footerMode = .supplementary
                config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                    self?.makeTrailingSwipeActions(for: indexPath, isPickedUp: true)
                }
            case .duoduoAction, .empty, .none:
                config.headerMode = .none
                config.footerMode = .none
            }

            return NSCollectionLayoutSection.list(using: config, layoutEnvironment: layoutEnvironment)
        }
    }
}
