import UIKit

final class RootViewController: UINavigationController {
    let dependencies: AppDependencies
    let dashboardViewController: DashboardViewController

    init(dependencies: AppDependencies = .live()) {
        self.dependencies = dependencies
        dashboardViewController = DashboardViewController(dependencies: dependencies)
        super.init(rootViewController: dashboardViewController)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
