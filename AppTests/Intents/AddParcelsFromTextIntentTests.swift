@testable import App
import AppIntents
import Core
import Foundation
import Testing

struct AddParcelsFromTextIntentTests {
    @Test
    func ingestsSMSAndOCRLikeTextUpgradesTrackingOnlySkipsDuplicatesAndNotifiesOnlyWhenChanged() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let notifications = NotificationCounter()
        let token = env.notificationCenter.addObserver(
            forName: .toteParcelsDidChange,
            object: nil,
            queue: nil
        ) { _ in
            notifications.increment()
        }
        defer { env.notificationCenter.removeObserver(token) }

        // 1. Non-parcel text (including OTP verification SMS) returns 0 without throwing or notifying.
        let otpOutcome = try AddParcelsFromTextIntent.ingest(
            text: "【Demo App】您的验证码是847291，5分钟内有效。",
            into: env.store,
            notificationCenter: env.notificationCenter
        )
        #expect(otpOutcome.savedCount == 0)
        #expect(otpOutcome.addedCount == 0)
        #expect(otpOutcome.updatedCount == 0)
        #expect(otpOutcome.skippedDuplicateCount == 0)
        #expect(notifications.count == 0)
        #expect(try env.store.load().isEmpty)

        // 2. Tracking-only message adds 1 awaiting-code parcel and posts notification.
        let trackingOutcome = try AddParcelsFromTextIntent.ingest(
            text: "订单已发货，圆通单号 YT0000000000000",
            into: env.store,
            notificationCenter: env.notificationCenter
        )
        #expect(trackingOutcome.savedCount == 1)
        #expect(trackingOutcome.addedCount == 1)
        #expect(notifications.count == 1)

        // 3. Pickup message with the same tracking number upgrades the existing parcel (savedCount == 1).
        let upgradeOutcome = try AddParcelsFromTextIntent.ingest(
            text: "【Demo Station】运单YT0000000000000已到站，凭取件码12-3-0000取件",
            into: env.store,
            notificationCenter: env.notificationCenter
        )
        #expect(upgradeOutcome.savedCount == 1)
        #expect(upgradeOutcome.addedCount == 0)
        #expect(upgradeOutcome.updatedCount == 1)
        #expect(notifications.count == 2)

        let storedAfterUpgrade = try env.store.load()
        #expect(storedAfterUpgrade.count == 1)
        #expect(storedAfterUpgrade[0].pickupCode == "12-3-0000")
        #expect(storedAfterUpgrade[0].trackingNumber == "YT0000000000000")
        #expect(storedAfterUpgrade[0].source == .pasted)

        // 4. Re-running the same text skips as duplicate and does NOT post notification.
        let duplicateOutcome = try AddParcelsFromTextIntent.ingest(
            text: "【Demo Station】凭取件码12-3-0000取件",
            into: env.store,
            notificationCenter: env.notificationCenter
        )
        #expect(duplicateOutcome.savedCount == 0)
        #expect(duplicateOutcome.skippedDuplicateCount == 1)
        #expect(notifications.count == 2)

        // 5. Mixed batch with 1 existing duplicate and 1 new locker code adds only the new parcel.
        let mixedOutcome = try AddParcelsFromTextIntent.ingest(
            text: """
            12-3-0000
            05240000
            """,
            into: env.store,
            notificationCenter: env.notificationCenter
        )
        #expect(mixedOutcome.savedCount == 1)
        #expect(mixedOutcome.addedCount == 1)
        #expect(mixedOutcome.skippedDuplicateCount == 1)
        #expect(!String(localized: mixedOutcome.dialogResource).contains("%"))
        #expect(notifications.count == 3)
        #expect(try env.store.load().count == 2)

        // 6. Batch that simultaneously upgrades a tracking-only parcel and adds a brand-new parcel.
        _ = try env.store.add(
            [ParsedParcelDraft(trackingNumber: "SF0000000000001", channel: .sfExpress)],
            source: .pasted
        )
        let addAndUpdateOutcome = try AddParcelsFromTextIntent.ingest(
            text: """
            【Demo Station】运单SF0000000000001已到站，取件码8-2-1048
            【Demo Station】取件码9-1-2048
            """,
            into: env.store,
            notificationCenter: env.notificationCenter
        )
        #expect(addAndUpdateOutcome.addedCount == 1)
        #expect(addAndUpdateOutcome.updatedCount == 1)
        #expect(addAndUpdateOutcome.savedCount == 2)
        #expect(!String(localized: addAndUpdateOutcome.dialogResource).contains("%"))
        #expect(notifications.count == 4)
        #expect(try env.store.load().count == 4)
    }

    @Test
    func dialogNeverEchoesPickupCodesOrTrackingNumbersAndPropagatesStoreErrors() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let sensitiveCode = "05240000"
        let sensitiveTracking = "YT0000000000000"
        let outcome = try AddParcelsFromTextIntent.ingest(
            text: "【Demo Locker】运单\(sensitiveTracking)已入柜，取件码\(sensitiveCode)",
            into: env.store,
            notificationCenter: env.notificationCenter
        )
        let dialogText = String(localized: outcome.dialogResource)
        #expect(!dialogText.isEmpty)
        #expect(!dialogText.contains(sensitiveCode))
        #expect(!dialogText.contains(sensitiveTracking))
        #expect(outcome.savedCount == 1)

        // Corrupted store must throw rather than silently returning 0.
        try Data("{ corrupted json".utf8).write(to: env.store.fileURL)
        #expect(throws: ParcelStoreError.self) {
            try AddParcelsFromTextIntent.ingest(
                text: "12-3-0000",
                into: env.store,
                notificationCenter: env.notificationCenter
            )
        }
    }

    @Test
    func registersAppShortcutForAddParcelsFromTextIntent() {
        #expect(ToteAppShortcuts.appShortcuts.count == 1)
    }
}

private final nonisolated class NotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
