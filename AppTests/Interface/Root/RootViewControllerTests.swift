@testable import App
import Core
import Foundation
import Testing
import UIKit

struct RootViewControllerTests {
    @Test
    func installsTwoTabsAndPreservesSingleYixiaojiInstance() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let root = RootViewController(dependencies: env.dependencies)
        root.loadViewIfNeeded()

        #expect(root.tabs.count == 2)
        #expect(root.tabs[0].identifier == RootViewController.TabIdentifier.parcels)
        #expect(root.tabs[1].identifier == RootViewController.TabIdentifier.yixiaoji)
        #expect(root.selectedTab?.identifier == RootViewController.TabIdentifier.parcels)

        let firstNav = root.tabs[1].viewController as? UINavigationController
        let secondNav = root.tabs[1].viewController as? UINavigationController
        #expect(firstNav === secondNav)
        #expect(firstNav?.viewControllers.first === root.yixiaojiViewController)
    }

    @Test
    func tappingYixiaojiParcelCopiesSwitchesTabAndShowsHandoff() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let result = try env.store.add(
            [
                ParsedParcelDraft(
                    pickupCode: "A03-8821",
                    channel: .yixiaoji,
                    stationLabel: "Sample Locker A1",
                    note: "Demo Item"
                ),
            ],
            source: .pasted
        )
        let parcelID = try #require(result.added.first?.id)

        let root = RootViewController(dependencies: env.dependencies)
        root.loadViewIfNeeded()
        root.dashboardViewController.loadViewIfNeeded()

        root.dashboardViewController.handleSelection(
            of: .parcel(parcelID),
            sourceView: root.dashboardViewController.view
        )

        #expect(env.clipboard.lastCopied == "A03-8821")
        #expect(root.selectedTab?.identifier == RootViewController.TabIdentifier.yixiaoji)
        #expect(root.yixiaojiViewController.activeHandoffCode == "A03-8821")
    }
}
