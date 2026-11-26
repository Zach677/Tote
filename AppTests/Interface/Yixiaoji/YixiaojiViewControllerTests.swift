@testable import App
import Foundation
import Testing
import UIKit
import WebKit

struct YixiaojiViewControllerTests {
    @Test
    func doesNotAutoLoadWhenDisabledInDependencies() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let controller = YixiaojiViewController(dependencies: env.dependencies)
        controller.loadViewIfNeeded()

        #expect(controller.webView.url == nil)
        #expect(!controller.webView.isLoading)
    }

    @Test
    func handoffBannerShowsReplacesRecopiesAndDismisses() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let controller = YixiaojiViewController(dependencies: env.dependencies)
        controller.handoffAutoDismissDuration = 60
        controller.isVoiceOverRunningProvider = { false }
        controller.loadViewIfNeeded()

        controller.showHandoff(code: "A03-8821")
        let initialBanner = try #require(controller.handoffBannerView)
        #expect(controller.activeHandoffCode == "A03-8821")

        controller.showHandoff(code: "5-1-2207")
        #expect(controller.handoffBannerView === initialBanner)
        #expect(controller.activeHandoffCode == "5-1-2207")

        initialBanner.triggerCopyTap()
        #expect(env.clipboard.lastCopied == "5-1-2207")

        controller.dismissHandoff(animated: false)
        #expect(controller.activeHandoffCode == nil)
        #expect(controller.handoffBannerView == nil)
    }

    @Test
    func handoffAutoDismissesUnlessVoiceOverIsRunning() async throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let voiceOverController = YixiaojiViewController(dependencies: env.dependencies)
        voiceOverController.handoffAutoDismissDuration = 0.05
        voiceOverController.isVoiceOverRunningProvider = { true }
        voiceOverController.loadViewIfNeeded()

        voiceOverController.showHandoff(code: "12-3-0000")
        try await Task.sleep(for: .milliseconds(120))
        #expect(voiceOverController.activeHandoffCode == "12-3-0000")

        let standardController = YixiaojiViewController(dependencies: env.dependencies)
        standardController.handoffAutoDismissDuration = 0.05
        standardController.isVoiceOverRunningProvider = { false }
        standardController.loadViewIfNeeded()

        standardController.showHandoff(code: "4-2-1048")
        let deadline = ContinuousClock.now + .seconds(2)
        while standardController.activeHandoffCode != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(standardController.activeHandoffCode == nil)
    }

    @Test
    func webViewUsesPersistentWebsiteDataStore() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let controller = YixiaojiViewController(dependencies: env.dependencies)
        controller.loadViewIfNeeded()

        #expect(controller.webView.configuration.websiteDataStore.isPersistent)
    }

    @Test
    func navigationErrorsShowUnavailableExceptCancellation() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let controller = YixiaojiViewController(dependencies: env.dependencies)
        controller.loadViewIfNeeded()

        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        controller.handleNavigationFailure(cancelled)
        #expect(controller.contentUnavailableConfiguration == nil)

        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        controller.handleNavigationFailure(offline)
        #expect(controller.contentUnavailableConfiguration != nil)

        controller.webView(controller.webView, didCommit: nil)
        #expect(controller.contentUnavailableConfiguration == nil)
    }
}
