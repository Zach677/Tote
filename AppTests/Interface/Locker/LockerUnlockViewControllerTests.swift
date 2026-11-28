@testable import App
import Core
import Foundation
import Testing
import UIKit

struct LockerUnlockViewControllerTests {
    @Test
    func lookupAutoMatchesCabinetPersistsBindingAndUnlocksWithExactMAC() async throws {
        let session = YixiaojiSession(uid: "1001", token: "demo-token", username: "demo")
        let env = TestEnvironment(yixiaojiSession: session)
        defer { env.cleanup() }

        let added = try env.store.add(
            [ParsedParcelDraft(pickupCode: "05240000", channel: .locker)],
            source: .pasted
        ).added
        let parcel = try #require(added.first)

        env.yixiaoji.searchResultsByKeyword["05240000"] = [
            YixiaojiRemoteParcel(
                pickupCode: "05240000",
                trackingNumber: "YT0000000000000",
                cabinetName: "Sample Locker A1",
                cabinetMAC: "MAC-A1",
                siteID: "42"
            ),
        ]
        env.yixiaoji.cabinetsResult = .success([
            YixiaojiCabinet(id: "42", name: "Sample Locker A1", mac: "MAC-A1"),
            YixiaojiCabinet(id: "43", name: "Sample Locker B2", mac: "MAC-B2"),
        ])
        env.yixiaoji.unlockResult = .success(.opened(compartment: "19", message: "Door opened", orderSN: "ORD-19"))

        var updatedFromCallback: Parcel?
        let controller = LockerUnlockViewController(parcel: parcel, dependencies: env.dependencies)
        controller.onParcelUpdated = { updatedFromCallback = $0 }
        controller.loadViewIfNeeded()

        await controller.performInitialLookup()

        #expect(controller.didAutoMatchCabinet)
        #expect(controller.selectedCabinetName == "Sample Locker A1")
        #expect(controller.selectedCabinetMAC == "MAC-A1")
        #expect(controller.selectedSiteID == "42")
        #expect(updatedFromCallback?.lockerMAC == "MAC-A1")
        #expect(try env.store.load().first?.lockerMAC == "MAC-A1")

        await controller.performUnlock()

        #expect(
            env.yixiaoji.unlockRequests == [
                FakeYixiaojiService.UnlockRequest(code: "05240000", cabinetMAC: "MAC-A1", siteID: "42"),
            ]
        )
        #expect(controller.unlockState == .opened(compartment: "19", message: "Door opened"))
    }

    @Test
    func manualCabinetChangePersistsSelectionAndHandlesPaymentRequiredAndFallback() async throws {
        let session = YixiaojiSession(uid: "1001", token: "demo-token", username: "demo")
        let env = TestEnvironment(yixiaojiSession: session)
        defer { env.cleanup() }

        let added = try env.store.add(
            [ParsedParcelDraft(pickupCode: "05240001", channel: .locker)],
            source: .pasted
        ).added
        let parcel = try #require(added.first)

        let cabinetB = YixiaojiCabinet(id: "43", name: "Sample Locker B2", mac: "MAC-B2")
        env.yixiaoji.unlockResult = .success(
            .paymentRequired(message: "Overdue 2 days", amount: "1.0", overdueDays: "2")
        )

        let controller = LockerUnlockViewController(parcel: parcel, dependencies: env.dependencies)
        controller.loadViewIfNeeded()
        controller.selectCabinet(cabinetB)

        #expect(controller.selectedCabinetName == "Sample Locker B2")
        #expect(controller.selectedCabinetMAC == "MAC-B2")
        #expect(controller.selectedSiteID == "43")
        #expect(env.yixiaoji.lastSelectedCabinet == cabinetB)

        await controller.performUnlock()
        #expect(
            controller.unlockState == .paymentRequired(
                message: "Overdue 2 days",
                amount: "1.0",
                overdueDays: "2"
            )
        )

        controller.copyCode()
        #expect(env.clipboard.lastCopied == "05240001")

        controller.openInSafari()
        #expect(env.launcher.openedURLs == [AppDependencies.yixiaojiWebFallbackURL])
    }

    @Test
    func loginViewControllerValidatesAndStoresSession() async {
        let env = TestEnvironment()
        defer { env.cleanup() }

        var signedInSession: YixiaojiSession?
        let controller = YixiaojiLoginViewController(dependencies: env.dependencies) { session in
            signedInSession = session
        }
        controller.loadViewIfNeeded()

        #expect(!controller.isSignInEnabled)
        controller.updateUsername("demo-user")
        #expect(!controller.isSignInEnabled)
        controller.updatePassword("secret-pass")
        #expect(controller.isSignInEnabled)

        env.yixiaoji.loginResult = .failure(YixiaojiAPIError.invalidCredentials("Wrong password"))
        #expect(await !controller.submitLogin())
        #expect(controller.errorMessage == "Wrong password")
        #expect(signedInSession == nil)

        let expectedSession = YixiaojiSession(uid: "1001", token: "token-123", username: "demo-user")
        env.yixiaoji.loginResult = .success(expectedSession)
        #expect(await controller.submitLogin())
        #expect(signedInSession == expectedSession)
        #expect(env.yixiaoji.currentSession == expectedSession)
    }

    @Test
    func lookupFallsBackToPendingParcelsAndMatchesLeadingZeroStrippedCode() async throws {
        let session = YixiaojiSession(uid: "1001", token: "demo-token", username: "demo")
        let env = TestEnvironment(yixiaojiSession: session)
        defer { env.cleanup() }

        let added = try env.store.add(
            [ParsedParcelDraft(pickupCode: "05240000", channel: .locker)],
            source: .pasted
        ).added
        let parcel = try #require(added.first)

        // Keyword search returns empty, but pending list has integer-coerced code without leading zero
        env.yixiaoji.pendingParcelsResult = .success(
            YixiaojiPendingSyncBatch(
                parcels: [
                    YixiaojiRemoteParcel(
                        pickupCode: "5240000",
                        trackingNumber: "YT0000000000000",
                        cabinetName: "Sample Locker A1",
                        cabinetMAC: "MAC-A1",
                        siteID: "42"
                    ),
                ],
                isTruncated: false
            )
        )

        let controller = LockerUnlockViewController(parcel: parcel, dependencies: env.dependencies)
        controller.loadViewIfNeeded()
        await controller.performInitialLookup()

        #expect(controller.didAutoMatchCabinet)
        #expect(controller.selectedCabinetName == "Sample Locker A1")
        #expect(controller.selectedCabinetMAC == "MAC-A1")
        #expect(controller.selectedSiteID == "42")
    }

    @Test
    func unlockIsFailClosedWithoutCabinetIgnoresMismatchedSingleResultAndPreservesManualChoice() async throws {
        let session = YixiaojiSession(uid: "1001", token: "demo-token", username: "demo")
        let env = TestEnvironment(yixiaojiSession: session)
        defer { env.cleanup() }

        let added = try env.store.add(
            [ParsedParcelDraft(pickupCode: "05240000", channel: .locker)],
            source: .pasted
        ).added
        let parcel = try #require(added.first)

        // Single search result has a DIFFERENT pickup code -> must NOT match or persist!
        env.yixiaoji.searchResultsByKeyword["05240000"] = [
            YixiaojiRemoteParcel(
                pickupCode: "99999999",
                cabinetName: "Wrong Locker",
                cabinetMAC: "MAC-WRONG",
                siteID: "99"
            ),
        ]

        let controller = LockerUnlockViewController(parcel: parcel, dependencies: env.dependencies)
        controller.loadViewIfNeeded()
        await controller.performInitialLookup()

        #expect(!controller.didAutoMatchCabinet)
        #expect(!controller.hasExplicitCabinetTarget)
        #expect(!controller.canUnlock)
        #expect(!controller.primaryButton.isEnabled)

        await controller.performUnlock()
        #expect(env.yixiaoji.unlockRequests.isEmpty)

        // Manual cabinet selection during an in-flight lookup must NOT be overwritten.
        let manualCabinet = YixiaojiCabinet(id: "43", name: "Sample Locker B2", mac: "MAC-B2")
        env.yixiaoji.searchResultsByKeyword["05240000"] = [
            YixiaojiRemoteParcel(
                pickupCode: "05240000",
                cabinetName: "Sample Locker A1",
                cabinetMAC: "MAC-A1",
                siteID: "42"
            ),
        ]
        env.yixiaoji.searchDelay = .milliseconds(50)

        let raceController = LockerUnlockViewController(parcel: parcel, dependencies: env.dependencies)
        raceController.loadViewIfNeeded()
        let lookupTask = Task {
            await raceController.performInitialLookup()
        }
        try await Task.sleep(for: .milliseconds(10))
        raceController.selectCabinet(manualCabinet)
        await lookupTask.value

        #expect(raceController.selectedCabinetName == "Sample Locker B2")
        #expect(raceController.selectedCabinetMAC == "MAC-B2")
        #expect(raceController.selectedSiteID == "43")
        #expect(raceController.canUnlock)

        // Unconfirmed unlock transitions to .unconfirmed warning state.
        env.yixiaoji.unlockResult = .failure(
            YixiaojiAPIError.unlockUnconfirmed(message: "Timeout checking status", orderSN: "ORD-99")
        )
        await raceController.performUnlock()
        #expect(raceController.unlockState == .unconfirmed(message: "Timeout checking status"))
    }
}
