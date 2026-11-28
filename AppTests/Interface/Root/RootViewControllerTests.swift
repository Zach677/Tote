@testable import App
import Core
import Foundation
import Testing
import UIKit

struct RootViewControllerTests {
    @Test
    func wrapsDashboardInSingleNavigationControllerWithoutTabs() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let root = RootViewController(dependencies: env.dependencies)
        root.loadViewIfNeeded()

        #expect(root.viewControllers.count == 1)
        #expect(root.viewControllers.first === root.dashboardViewController)
    }
}
