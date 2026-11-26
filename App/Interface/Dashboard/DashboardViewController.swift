import Core
import UIKit

final class DashboardViewController: UIViewController {
    enum Segment: Int {
        case pending = 0
        case pickedUp = 1
    }

    let dependencies: AppDependencies
    var onOpenYixiaoji: (String) -> Void = { _ in }

    var selectedSegment: Segment = .pending
    private(set) var parcels: [Parcel] = []
    private(set) var groups = DashboardGroups()
    var parcelsByID: [Parcel.ID: Parcel] = [:]

    let segmentedControl = UISegmentedControl(items: [
        String(localized: "Pending"),
        String(localized: "Picked Up"),
    ])
    let copyToastView = CopyToastView()
    private(set) var collectionView: UICollectionView!
    var dataSource: UICollectionViewDiffableDataSource<DashboardSection, DashboardItem>!

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
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
        configureHierarchy()
        configureDataSource()
        reloadParcels(animatingDifferences: false)
    }

    func reloadParcels(animatingDifferences: Bool, scrollToParcelID: Parcel.ID? = nil) {
        do {
            let loaded = try dependencies.parcelStore.load()
            applyLoadedParcels(
                loaded,
                animatingDifferences: animatingDifferences,
                scrollToParcelID: scrollToParcelID
            )
        } catch {
            presentStoreErrorAlert(title: String(localized: "Couldn’t Load Parcels"))
        }
    }

    func applyLoadedParcels(
        _ loaded: [Parcel],
        animatingDifferences: Bool,
        scrollToParcelID: Parcel.ID? = nil
    ) {
        parcels = loaded
        groups = DashboardGroups(parcels: loaded)
        parcelsByID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        applySnapshot(
            animatingDifferences: animatingDifferences,
            scrollToParcelID: scrollToParcelID
        )
    }

    func setCollectionView(_ collectionView: UICollectionView) {
        self.collectionView = collectionView
    }
}
