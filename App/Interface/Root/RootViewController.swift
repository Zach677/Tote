import UIKit

final class RootViewController: UITabBarController {
    enum TabIdentifier {
        static let parcels = "parcels"
        static let yixiaoji = "yixiaoji"
    }

    let dependencies: AppDependencies
    let dashboardViewController: DashboardViewController
    let yixiaojiViewController: YixiaojiViewController

    private let dashboardNavigationController: UINavigationController
    private let yixiaojiNavigationController: UINavigationController
    private lazy var parcelsTab = UITab(
        title: String(localized: "Parcels"),
        image: UIImage(systemName: "shippingbox"),
        identifier: TabIdentifier.parcels
    ) { [dashboardNavigationController] _ in
        dashboardNavigationController
    }

    private lazy var yixiaojiTab = UITab(
        title: String(localized: "Yixiaoji"),
        image: UIImage(systemName: "cabinet"),
        identifier: TabIdentifier.yixiaoji
    ) { [yixiaojiNavigationController] _ in
        yixiaojiNavigationController
    }

    init(dependencies: AppDependencies = .live()) {
        self.dependencies = dependencies
        dashboardViewController = DashboardViewController(dependencies: dependencies)
        yixiaojiViewController = YixiaojiViewController(dependencies: dependencies)
        dashboardNavigationController = UINavigationController(rootViewController: dashboardViewController)
        yixiaojiNavigationController = UINavigationController(rootViewController: yixiaojiViewController)
        super.init(nibName: nil, bundle: nil)

        dashboardViewController.onOpenYixiaoji = { [weak self] code in
            self?.openYixiaoji(handoffCode: code)
        }
        tabs = [parcelsTab, yixiaojiTab]
        selectedTab = parcelsTab
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func openYixiaoji(handoffCode: String) {
        selectedTab = yixiaojiTab
        yixiaojiViewController.loadViewIfNeeded()
        yixiaojiViewController.showHandoff(code: handoffCode)
    }
}
