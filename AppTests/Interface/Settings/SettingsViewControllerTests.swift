@testable import App
import Core
import Foundation
import Testing
import UIKit

struct SettingsViewControllerTests {
    @Test
    func invalidLinkDisablesDoneAndBlocksTestAndSave() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let controller = SettingsViewController(dependencies: env.dependencies)
        controller.loadViewIfNeeded()

        #expect(controller.navigationItem.leftBarButtonItem != nil)
        #expect(controller.isLinkValid)
        #expect(controller.isDoneEnabled)
        #expect(!controller.canResetToDefault)

        controller.updateURLText("not-a-valid-link")
        #expect(!controller.isLinkValid)
        #expect(!controller.isDoneEnabled)
        #expect(controller.canResetToDefault)

        controller.testCurrentLink()
        #expect(env.launcher.openedURLs.isEmpty)
        #expect(!controller.saveAndDismiss())
        #expect(env.settings.duoduoURLString == DuoduoLinkValidator.defaultURLString)

        controller.updateURLText("pinduoduo://")
        #expect(!controller.isLinkValid)
        #expect(!controller.isDoneEnabled)
    }

    @Test
    func validLinkTestsSavesAndResetRestoresDefault() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let controller = SettingsViewController(dependencies: env.dependencies)
        controller.loadViewIfNeeded()

        let customLink = "pinduoduo://com.xunmeng.pinduoduo/mdkd/identity"
        controller.updateURLText("  \(customLink)  ")

        #expect(controller.isLinkValid)
        #expect(controller.isDoneEnabled)
        #expect(controller.canResetToDefault)

        controller.testCurrentLink()
        #expect(env.launcher.openedURLs.map(\.absoluteString) == [customLink])

        #expect(controller.saveAndDismiss())
        #expect(env.settings.duoduoURLString == customLink)

        controller.resetToDefault()
        #expect(controller.urlText == DuoduoLinkValidator.defaultURLString)
        // Resetting stays pending until Done so swipe-down can discard edits.
        #expect(env.settings.duoduoURLString == customLink)
        #expect(!controller.canResetToDefault)

        #expect(controller.saveAndDismiss())
        #expect(env.settings.duoduoURLString == DuoduoLinkValidator.defaultURLString)
    }

    @Test
    func userDefaultsSettingsStorePersistsTrimsAndResets() throws {
        let suiteName = "ToteSettingsStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        #expect(store.duoduoURLString == DuoduoLinkValidator.defaultURLString)

        let custom = "pinduoduo://com.xunmeng.pinduoduo/mdkd/barcode"
        store.duoduoURLString = "  \(custom) \n"
        #expect(store.duoduoURLString == custom)

        store.duoduoURLString = "   \n  "
        #expect(store.duoduoURLString == DuoduoLinkValidator.defaultURLString)

        store.duoduoURLString = custom
        store.resetDuoduoURL()
        #expect(store.duoduoURLString == DuoduoLinkValidator.defaultURLString)
    }
}
