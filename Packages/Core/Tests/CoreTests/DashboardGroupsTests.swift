import Core
import Foundation
import Testing

@Suite("DashboardGroups")
struct DashboardGroupsTests {
    @Test("Orders non-empty channel sections in PickupChannel order and omits empty channels")
    func channelSectionOrderAndOmission() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let parcels = [
            Parcel(pickupCode: "5-1-2207", channel: .jd, createdAt: baseDate),
            Parcel(pickupCode: "12-3-0000", channel: .duoduo, createdAt: baseDate),
            Parcel(pickupCode: "4-2-1048", channel: .cainiao, createdAt: baseDate),
            Parcel(pickupCode: "A03-8821", channel: .yixiaoji, createdAt: baseDate),
        ]

        let groups = DashboardGroups(parcels: parcels)
        #expect(groups.channelSections.map(\.channel) == [.duoduo, .yixiaoji, .cainiao, .jd])
        #expect(groups.awaitingCode.isEmpty)
        #expect(groups.pickedUp.isEmpty)
        #expect(groups.pendingCount == 4)
        #expect(groups.hasPendingParcels)
        #expect(groups.hasPickedUpParcels == false)
    }

    @Test("Sorts pending parcels newest-first with deterministic UUID tie-breaking")
    func pendingSortingAndTieBreaking() throws {
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_700_001_000)
        let lowID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let highID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))

        let older = Parcel(pickupCode: "1-0-0001", channel: .duoduo, createdAt: olderDate)
        let newerHigh = Parcel(id: highID, pickupCode: "1-0-0003", channel: .duoduo, createdAt: newerDate)
        let newerLow = Parcel(id: lowID, pickupCode: "1-0-0002", channel: .duoduo, createdAt: newerDate)

        let groups = DashboardGroups(parcels: [older, newerHigh, newerLow])
        let duoduoSection = try #require(groups.channelSections.first)

        #expect(duoduoSection.parcels.map(\.id) == [lowID, highID, older.id])
    }

    @Test("Separates tracking-only pending parcels into awaitingCode sorted newest-first")
    func trackingOnlySeparation() {
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_002_000)

        let olderTracking = Parcel(trackingNumber: "YT0000000000000", channel: .other, createdAt: t1)
        let newerTracking = Parcel(trackingNumber: "SF0000000000000", channel: .sfExpress, createdAt: t2)
        let coded = Parcel(pickupCode: "12-3-0000", trackingNumber: "JD0000000000000", channel: .duoduo, createdAt: t1)

        let groups = DashboardGroups(parcels: [olderTracking, coded, newerTracking])

        #expect(groups.channelSections.map(\.channel) == [.duoduo])
        #expect(groups.awaitingCode.map(\.trackingNumber) == ["SF0000000000000", "YT0000000000000"])
        #expect(groups.pendingCount == 3)
    }

    @Test("Sorts picked-up parcels by newest pickedUpAt first")
    func pickedUpOrdering() {
        let createdOld = Date(timeIntervalSince1970: 1_700_000_000)
        let createdNew = Date(timeIntervalSince1970: 1_700_010_000)
        let pickedEarlier = Date(timeIntervalSince1970: 1_700_020_000)
        let pickedLater = Date(timeIntervalSince1970: 1_700_030_000)

        let firstPicked = Parcel(
            pickupCode: "4-2-1048",
            channel: .cainiao,
            status: .pickedUp(at: pickedEarlier),
            createdAt: createdNew
        )
        let secondPicked = Parcel(
            pickupCode: "12-3-0000",
            channel: .duoduo,
            status: .pickedUp(at: pickedLater),
            createdAt: createdOld
        )

        let groups = DashboardGroups(parcels: [firstPicked, secondPicked])
        #expect(groups.channelSections.isEmpty)
        #expect(groups.pickedUp.map(\.id) == [secondPicked.id, firstPicked.id])
        #expect(groups.hasPickedUpParcels)
    }
}
