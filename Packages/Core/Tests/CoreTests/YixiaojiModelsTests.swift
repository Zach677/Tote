import Core
import Foundation
import Testing

@Suite("YixiaojiModels & Sync")
struct YixiaojiModelsTests {
    @Test("Parses login response with mixed numeric and string fields and cleans trailing-comma site IDs")
    func parsesLoginResponseAndUpdatesUserInfo() throws {
        let loginJSON = Data(
            """
            {
              "code": 1,
              "msg": "ok",
              "data": {
                "uid": 1024,
                "token": "demo-token-abc",
                "phone": "13800000000",
                "express_uids": "42,",
                "nickname": "Demo User"
              }
            }
            """.utf8
        )

        let session = try YixiaojiResponseParser.parseLoginResponse(loginJSON, username: "demo-user")
        #expect(session.uid == "1024")
        #expect(session.token == "demo-token-abc")
        #expect(session.username == "demo-user")
        #expect(session.phone == "13800000000")
        #expect(session.nickname == "Demo User")
        #expect(session.defaultSiteID == "42")
        #expect(session.displayAccountName == "Demo User")

        let userInfoJSON = Data(
            """
            {
              "code": "1",
              "data": {
                "id": "1024",
                "token": "demo-token-refreshed",
                "express_uids": "99, 100, 0, 99,",
                "express_name": "Sample Locker A1"
              }
            }
            """.utf8
        )

        let refreshed = try #require(YixiaojiResponseParser.parseUserInfoResponse(userInfoJSON, updating: session))
        #expect(refreshed.token == "demo-token-refreshed")
        #expect(refreshed.defaultSiteID == "99,100")
        #expect(refreshed.defaultSiteName == "Sample Locker A1")
    }

    @Test("Rejects failed login response with invalidCredentials")
    func rejectsFailedLogin() {
        let failedJSON = Data(#"{"errorCode":1001,"msg":"Wrong password"}"#.utf8)
        #expect(throws: YixiaojiAPIError.invalidCredentials("Wrong password")) {
            try YixiaojiResponseParser.parseLoginResponse(failedJSON, username: "demo")
        }
    }

    @Test("Parses search results with zero and non-zero bind_mac and filters picked-up state")
    func parsesSearchParcels() throws {
        let searchJSON = Data(
            """
            {
              "code": 1,
              "msg": "ok",
              "data": [
                {
                  "take_code": 5240000,
                  "order_sn": "YT0000000000000",
                  "address": "Sample Locker A1",
                  "bind_mac": "AA:BB:CC:DD:EE:01",
                  "express_uids": 42,
                  "mobile": "13800000000",
                  "is_get": 0,
                  "is_open": 0
                },
                {
                  "take_code": "05240001",
                  "order_sn": "JD0000000000000",
                  "address": "Sample Locker B2",
                  "bind_mac": 0,
                  "express_uids": "43,",
                  "is_get": 1,
                  "is_open": 1
                }
              ]
            }
            """.utf8
        )

        let parcels = try YixiaojiResponseParser.parseSearchResponse(searchJSON)
        #expect(parcels.count == 2)

        #expect(parcels[0].pickupCode == "5240000")
        #expect(parcels[0].trackingNumber == "YT0000000000000")
        #expect(parcels[0].cabinetName == "Sample Locker A1")
        #expect(parcels[0].cabinetMAC == "AA:BB:CC:DD:EE:01")
        #expect(parcels[0].siteID == "42")
        #expect(!parcels[0].isPickedUp)

        #expect(parcels[1].pickupCode == "05240001")
        #expect(parcels[1].cabinetMAC.isEmpty)
        #expect(parcels[1].siteID == "43")
        #expect(parcels[1].isPickedUp)
    }

    @Test("Parses cabinet list, overdue payment submission, and checkOrder compartment fallback")
    func parsesCabinetsAndUnlockFlows() throws {
        let cabinetsJSON = Data(
            """
            {
              "code": 1,
              "data": {
                "express_uids": "42,",
                "data": [
                  {"id": 42, "name": "Sample Locker A1", "address": "North Gate", "city": "Demo City", "mac": "MAC-A1"},
                  {"id": "43", "name": "Sample Locker B2", "address": "South Gate", "city": "", "mac": 0}
                ]
              }
            }
            """.utf8
        )

        let cabinetResult = try YixiaojiResponseParser.parseCabinetsResponse(cabinetsJSON)
        #expect(cabinetResult.defaultSiteID == "42")
        #expect(cabinetResult.cabinets.count == 2)
        #expect(cabinetResult.cabinets[0].mac == "MAC-A1")
        #expect(cabinetResult.cabinets[1].mac.isEmpty)

        let overdueJSON = Data(
            """
            {
              "code": 0,
              "msg": "Overdue fee required",
              "data": { "is_pay": 0, "money": 1.5, "expire_day": 3 }
            }
            """.utf8
        )
        let overdue = try YixiaojiResponseParser.parseUnlockSubmission(overdueJSON)
        #expect(overdue == .paymentRequired(message: "Overdue fee required", amount: "1.5", overdueDays: "3"))

        let submittedJSON = Data(
            """
            {
              "code": 1,
              "msg": "Submitted",
              "data": { "order_sn": "ORD-001" }
            }
            """.utf8
        )
        let submitted = try YixiaojiResponseParser.parseUnlockSubmission(submittedJSON)
        #expect(submitted == .submitted(orderSN: "ORD-001", message: "Submitted"))

        let boxCodeJSON = Data(#"{"code":1,"msg":"Opened","data":{"box_code":28,"dev_code":"A01"}}"#.utf8)
        let openedBox = try YixiaojiResponseParser.parseCheckOrderResponse(
            boxCodeJSON,
            fallbackOrderSN: "ORD-001",
            fallbackMessage: "Done"
        )
        #expect(openedBox == .opened(compartment: "28", message: "Opened", orderSN: "ORD-001"))

        let devFallbackJSON = Data(#"{"code":1,"msg":"Opened","data":{"box_code":0,"dev_code":"B07"}}"#.utf8)
        let openedDev = try YixiaojiResponseParser.parseCheckOrderResponse(
            devFallbackJSON,
            fallbackOrderSN: "ORD-001",
            fallbackMessage: "Done"
        )
        #expect(openedDev == .opened(compartment: "B07", message: "Opened", orderSN: "ORD-001"))
    }

    @Test("syncSyncedParcels adds new locker parcels and enriches existing manual locker parcels without duplicating")
    func syncEnrichesExistingManualParcel() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tote-sync-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_000_500)
        let initialStore = ParcelStore(directoryURL: dir, now: { t0 })

        // User pasted a bare 8-digit locker code before syncing
        _ = try initialStore.add(
            [ParsedParcelDraft(pickupCode: "05240000", channel: .locker)],
            source: .pasted
        )

        let syncStore = ParcelStore(directoryURL: dir, now: { t1 })
        let remote1 = YixiaojiRemoteParcel(
            pickupCode: "05240000",
            trackingNumber: "YT0000000000000",
            cabinetName: "Sample Locker A1",
            cabinetMAC: "MAC-A1",
            siteID: "42"
        )
        let remote2 = YixiaojiRemoteParcel(
            pickupCode: "05240001",
            trackingNumber: "JD0000000000000",
            cabinetName: "Sample Locker B2",
            cabinetMAC: "MAC-B2",
            siteID: "43"
        )

        let firstSync = try syncStore.syncSyncedParcels([remote1.makeDraft(), remote2.makeDraft()])
        #expect(firstSync.added.count == 1)
        #expect(firstSync.updated.count == 1)
        #expect(firstSync.skippedDuplicateCount == 0)

        let saved = try syncStore.load()
        #expect(saved.count == 2)
        let enriched = try #require(saved.first { $0.pickupCode == "05240000" })
        #expect(enriched.stationLabel == "Sample Locker A1")
        #expect(enriched.trackingNumber == "YT0000000000000")
        #expect(enriched.lockerMAC == "MAC-A1")
        #expect(enriched.lockerSiteID == "42")

        // Second sync with identical data skips both without modifying
        let secondSync = try syncStore.syncSyncedParcels(
            [remote1.makeDraft(), remote2.makeDraft()],
            markMissingSyncedLockerParcelsPickedUp: true
        )
        #expect(secondSync.added.isEmpty)
        #expect(secondSync.updated.isEmpty)
        #expect(secondSync.markedPickedUpCount == 0)
        #expect(secondSync.skippedDuplicateCount == 2)

        // Third sync (complete list) omits both remote parcels:
        // only the synced parcel (remote2) is auto-marked picked up; the pasted parcel (remote1) stays pending.
        let thirdSync = try syncStore.syncSyncedParcels(
            [],
            markMissingSyncedLockerParcelsPickedUp: true
        )
        #expect(thirdSync.markedPickedUpCount == 1)
        let afterReconcile = try syncStore.load()
        let pastedParcel = try #require(afterReconcile.first { $0.pickupCode == "05240000" })
        let syncedParcel = try #require(afterReconcile.first { $0.pickupCode == "05240001" })
        #expect(pastedParcel.isPending)
        #expect(syncedParcel.isPickedUp)
    }
}
