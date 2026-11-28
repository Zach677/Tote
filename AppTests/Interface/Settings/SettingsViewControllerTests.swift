@testable import App
import Core
import Foundation
import Testing
import UIKit

struct SettingsViewControllerTests {
    @Test
    func yixiaojiSectionSyncsParcelsSignsOutAndOpensSafariFallback() async {
        let session = YixiaojiSession(uid: "1001", token: "demo-token", username: "demo", defaultSiteName: "Sample Locker A1")
        let env = TestEnvironment(yixiaojiSession: session)
        defer { env.cleanup() }

        env.yixiaoji.pendingParcelsResult = .success(
            YixiaojiPendingSyncBatch(
                parcels: [
                    YixiaojiRemoteParcel(
                        pickupCode: "05240000",
                        trackingNumber: "YT0000000000000",
                        cabinetName: "Sample Locker A1",
                        cabinetMAC: "MAC-A1",
                        siteID: "42"
                    ),
                ],
                isTruncated: false
            )
        )

        var parcelsChangedCount = 0
        let controller = SettingsViewController(dependencies: env.dependencies)
        controller.onParcelsChanged = { parcelsChangedCount += 1 }
        controller.loadViewIfNeeded()

        #expect(controller.navigationItem.leftBarButtonItem != nil)
        #expect(controller.navigationItem.rightBarButtonItem == nil)
        #expect(controller.isYixiaojiSignedIn)
        let syncResult = await controller.syncYixiaojiNow()
        #expect(syncResult?.added.count == 1)
        #expect(parcelsChangedCount == 1)

        controller.openYixiaojiInSafari()
        #expect(env.launcher.openedURLs == [AppDependencies.yixiaojiWebFallbackURL])

        controller.signOutYixiaoji()
        #expect(!controller.isYixiaojiSignedIn)
        #expect(env.yixiaoji.logoutCount == 1)
    }

    @Test
    func shortcutsSectionOpensAllPresetICloudLinks() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let controller = SettingsViewController(dependencies: env.dependencies)
        controller.loadViewIfNeeded()

        for preset in PresetShortcut.allCases {
            controller.openShortcut(preset)
        }

        #expect(env.launcher.openedURLs == PresetShortcut.allCases.map(\.iCloudURL))
        #expect(env.launcher.openedURLs.allSatisfy { $0.host == "www.icloud.com" && $0.path.hasPrefix("/shortcuts/") })
    }
}
