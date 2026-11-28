@testable import App
import Core
import Foundation
import Testing
import UIKit

struct DashboardViewControllerTests {
    @Test
    func emptyPendingStillShowsDuoduoActionAboveEmptyState() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let controller = DashboardViewController(dependencies: env.dependencies)
        controller.loadViewIfNeeded()

        let snapshot = controller.dataSource.snapshot()
        #expect(snapshot.sectionIdentifiers == [.duoduoAction, .empty])
        #expect(snapshot.itemIdentifiers(inSection: .duoduoAction) == [.duoduoAction])
        #expect(snapshot.itemIdentifiers(inSection: .empty) == [.empty(isPending: true)])
    }

    @Test
    func pendingOrdersDuoduoActionThenNonEmptyChannelsThenAwaitingCode() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        _ = try env.store.add(
            [
                ParsedParcelDraft(pickupCode: "5-1-2207", channel: .jd, stationLabel: "Demo Station B"),
                ParsedParcelDraft(pickupCode: "12-3-0000", channel: .station, stationLabel: "North Pickup Point"),
                ParsedParcelDraft(trackingNumber: "YT0000000000000", channel: .other, note: "Demo Item"),
                ParsedParcelDraft(pickupCode: "A03-8821", channel: .locker, stationLabel: "Sample Locker A1"),
            ],
            source: .pasted
        )

        let controller = DashboardViewController(dependencies: env.dependencies)
        controller.loadViewIfNeeded()

        let snapshot = controller.dataSource.snapshot()
        #expect(snapshot.sectionIdentifiers == [
            .duoduoAction,
            .channel(.station),
            .channel(.locker),
            .channel(.jd),
            .awaitingCode,
        ])
    }

    @Test
    func tappingRowsPerformsChannelAppropriateActions() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let added = try env.store.add(
            [
                ParsedParcelDraft(pickupCode: "12-3-0000", channel: .station, stationLabel: "North Pickup Point"),
                ParsedParcelDraft(pickupCode: "A03-8821", channel: .locker, stationLabel: "Sample Locker A1"),
                ParsedParcelDraft(trackingNumber: "YT0000000000000", channel: .sfExpress, note: "Demo Item"),
            ],
            source: .pasted
        ).added

        let stationParcel = try #require(added.first { $0.channel == .station })
        let lockerParcel = try #require(added.first { $0.channel == .locker })
        let trackingOnlyParcel = try #require(added.first { $0.isTrackingOnly })

        let controller = DashboardViewController(dependencies: env.dependencies)
        var openedLockerParcels: [Parcel] = []
        controller.onOpenLocker = { openedLockerParcels.append($0) }
        controller.loadViewIfNeeded()

        controller.handleSelection(of: .parcel(stationParcel.id), sourceView: controller.view)
        #expect(env.clipboard.lastCopied == "12-3-0000")
        #expect(controller.copyToastView.currentValue == "12-3-0000")
        #expect(env.launcher.openedURLs.isEmpty)

        controller.handleSelection(of: .parcel(lockerParcel.id), sourceView: controller.view)
        #expect(openedLockerParcels.map(\.id) == [lockerParcel.id])
        #expect(controller.lastPresentedLockerParcel?.id == lockerParcel.id)

        env.launcher.shouldSucceed = false
        controller.handleSelection(of: .parcel(trackingOnlyParcel.id), sourceView: controller.view)
        #expect(env.clipboard.lastCopied == "YT0000000000000")
        #expect(env.launcher.openedURLs == [AppDependencies.duoduoStationURL])

        controller.handleSelection(of: .duoduoAction, sourceView: controller.view)
        #expect(env.launcher.openedURLs.count == 2)
    }

    @Test
    func pullToRefreshSyncsYixiaojiParcelsWhenSignedIn() async {
        let session = YixiaojiSession(uid: "1001", token: "demo-token", username: "demo")
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

        let controller = DashboardViewController(dependencies: env.dependencies)
        controller.loadViewIfNeeded()

        let result = await controller.syncYixiaojiIfSignedIn()
        #expect(result?.added.count == 1)
        #expect(controller.parcels.count == 1)
        #expect(controller.parcels.first?.channel == .locker)
        #expect(controller.parcels.first?.lockerMAC == "MAC-A1")
        #expect(controller.parcels.first?.stationLabel == "Sample Locker A1")
    }

    @Test
    func swipeMutationsAndSegmentSwitchPersistStateChanges() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let added = try env.store.add(
            [
                ParsedParcelDraft(pickupCode: "4-2-1048", channel: .station, stationLabel: "North Pickup Point"),
            ],
            source: .pasted
        ).added
        let parcelID = try #require(added.first?.id)

        let controller = DashboardViewController(dependencies: env.dependencies)
        controller.loadViewIfNeeded()

        let pendingIndexPath = try #require(controller.dataSource.indexPath(for: .parcel(parcelID)))
        let pendingSwipe = try #require(
            controller.makeTrailingSwipeActions(for: pendingIndexPath, isPickedUp: false)
        )
        #expect(pendingSwipe.actions.count == 2)
        #expect(pendingSwipe.performsFirstActionWithFullSwipe)
        #expect(pendingSwipe.actions[0].style == .normal)
        #expect(pendingSwipe.actions[1].style == .destructive)

        #expect(controller.markParcelPickedUp(id: parcelID))
        #expect(controller.groups.pendingCount == 0)
        #expect(controller.groups.pickedUp.count == 1)

        controller.selectSegment(.pickedUp)
        #expect(controller.dataSource.snapshot().sectionIdentifiers == [.pickedUp])

        let pickedUpIndexPath = try #require(controller.dataSource.indexPath(for: .parcel(parcelID)))
        let pickedUpSwipe = try #require(
            controller.makeTrailingSwipeActions(for: pickedUpIndexPath, isPickedUp: true)
        )
        #expect(pickedUpSwipe.actions.count == 2)
        #expect(pickedUpSwipe.performsFirstActionWithFullSwipe)
        #expect(pickedUpSwipe.actions[0].style == .normal)
        #expect(pickedUpSwipe.actions[1].style == .destructive)

        controller.handleSelection(of: .parcel(parcelID), sourceView: controller.view)
        #expect(env.clipboard.lastCopied == "4-2-1048")

        #expect(controller.restoreParcel(id: parcelID))
        #expect(controller.groups.pendingCount == 1)
        #expect(controller.groups.pickedUp.isEmpty)
        #expect(controller.dataSource.snapshot().sectionIdentifiers == [.empty])

        #expect(controller.deleteParcel(id: parcelID))
        #expect(try env.store.load().isEmpty)
    }

    @Test
    func visibleSectionHeaderCountRefreshesWhenParcelCountChanges() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let added = try env.store.add(
            [
                ParsedParcelDraft(pickupCode: "12-3-0001", channel: .station, stationLabel: "North Pickup Point"),
                ParsedParcelDraft(pickupCode: "12-3-0002", channel: .station, stationLabel: "North Pickup Point"),
            ],
            source: .pasted
        ).added
        try #require(added.count == 2)

        let controller = DashboardViewController(dependencies: env.dependencies)
        let nav = UINavigationController(rootViewController: controller)
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = nav
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        controller.collectionView.layoutIfNeeded()

        func visibleCounts() -> [Int] {
            controller.collectionView
                .indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionHeader)
                .compactMap { indexPath in
                    (controller.collectionView.supplementaryView(
                        forElementKind: UICollectionView.elementKindSectionHeader,
                        at: indexPath
                    ) as? DashboardSectionHeaderView)?.displayedCount
                }
        }

        #expect(visibleCounts() == [2])
        #expect(controller.markParcelPickedUp(id: added[0].id))
        controller.collectionView.layoutIfNeeded()
        #expect(visibleCounts() == [1])
    }

    @Test
    func defersInitialLoadErrorAlertUntilViewAppearsInWindow() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        try FileManager.default.createDirectory(at: env.directoryURL, withIntermediateDirectories: true)
        try Data("{ invalid json".utf8).write(to: env.store.fileURL)

        let controller = DashboardViewController(dependencies: env.dependencies)
        controller.loadViewIfNeeded()
        #expect(controller.pendingLoadErrorTitle != nil)
        #expect(controller.presentedViewController == nil)

        let nav = UINavigationController(rootViewController: controller)
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = nav
        window.makeKeyAndVisible()
        nav.view.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        defer {
            nav.dismiss(animated: false)
            window.isHidden = true
        }

        #expect(controller.view.window != nil)
        if controller.pendingLoadErrorTitle != nil {
            controller.viewDidAppear(false)
        }
        #expect(controller.pendingLoadErrorTitle == nil)
        #expect((controller.presentedViewController ?? nav.presentedViewController) is UIAlertController)
    }

    @Test
    func refreshesAutomaticallyOnExternalParcelNotificationAndForegroundReturn() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let controller = DashboardViewController(dependencies: env.dependencies)
        controller.loadViewIfNeeded()
        #expect(controller.parcels.isEmpty)

        // 1. In-process App Intent ingestion posts .toteParcelsDidChange -> immediate reload.
        _ = try AddParcelsFromTextIntent.ingest(
            text: "【Demo Station】凭取件码12-3-0000到站取件",
            into: env.store,
            notificationCenter: env.notificationCenter
        )
        #expect(controller.parcels.count == 1)
        #expect(controller.parcels.first?.pickupCode == "12-3-0000")

        // 2. Direct store write followed by willEnterForegroundNotification -> reload on foreground return.
        _ = try env.store.add(
            [ParsedParcelDraft(pickupCode: "05240000", channel: .locker)],
            source: .pasted
        )
        env.notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        #expect(controller.parcels.count == 2)
        #expect(controller.dataSource.snapshot().sectionIdentifiers.contains(.channel(.locker)))
    }
}
