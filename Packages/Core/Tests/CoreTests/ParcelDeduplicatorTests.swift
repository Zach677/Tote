import Core
import Foundation
import Testing

@Suite("ParcelDeduplicator")
struct ParcelDeduplicatorTests {
    private let deduplicator = ParcelDeduplicator()

    @Test("Marks identical pending channel and pickup code as duplicate")
    func exactPickupCodeDuplicate() {
        let existing = Parcel(
            pickupCode: "12-3-0000",
            channel: .duoduo,
            stationLabel: "Demo Station B"
        )
        let draft = ParsedParcelDraft(
            pickupCode: " １２－３－００００ ",
            channel: .duoduo
        )

        #expect(deduplicator.classify(draft, against: [existing]) == .duplicate(existingID: existing.id))
    }

    @Test("Allows same pickup code on a different channel")
    func differentChannelAllowsSameCode() {
        let existing = Parcel(pickupCode: "12-3-0000", channel: .duoduo)
        let draft = ParsedParcelDraft(pickupCode: "12-3-0000", channel: .cainiao)

        #expect(deduplicator.classify(draft, against: [existing]) == .new)
    }

    @Test("Upgrades pending tracking-only parcel when draft provides a pickup code")
    func trackingOnlyUpgradeAndMerge() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_003_600)
        let existing = Parcel(
            pickupCode: "",
            trackingNumber: "SF0000000000000",
            channel: .sfExpress,
            stationLabel: "",
            note: "Demo Item",
            status: .pending,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let draft = ParsedParcelDraft(
            pickupCode: "12-3-0000",
            trackingNumber: "SF0000000000000",
            channel: .duoduo,
            stationLabel: "Demo Station B",
            note: ""
        )

        #expect(
            deduplicator.classify(draft, against: [existing])
                == .upgradeTrackingOnly(existingID: existing.id)
        )

        let merged = deduplicator.merge(draft, into: existing, updatedAt: updatedAt)
        #expect(merged.id == existing.id)
        #expect(merged.pickupCode == "12-3-0000")
        #expect(merged.trackingNumber == "SF0000000000000")
        #expect(merged.channel == .duoduo)
        #expect(merged.stationLabel == "Demo Station B")
        #expect(merged.note == "Demo Item")
        #expect(merged.createdAt == createdAt)
        #expect(merged.updatedAt == updatedAt)
    }

    @Test("Does not let picked-up parcels block re-adding the same code or waybill")
    func pickedUpDoesNotBlockReAdd() {
        let pickedUp = Parcel(
            pickupCode: "12-3-0000",
            trackingNumber: "YT0000000000000",
            channel: .duoduo,
            status: .pickedUp(at: Date(timeIntervalSince1970: 1_700_000_000))
        )
        let draft = ParsedParcelDraft(
            pickupCode: "12-3-0000",
            trackingNumber: "YT0000000000000",
            channel: .duoduo
        )

        #expect(deduplicator.classify(draft, against: [pickedUp]) == .new)
    }

    @Test("Detects intra-batch duplicates and tracking-only upgrades within one batch")
    func intraBatchClassification() {
        let first = ParsedParcelDraft(pickupCode: "4-2-1048", channel: .cainiao)
        let duplicateOfFirst = ParsedParcelDraft(pickupCode: "4-2-1048", channel: .cainiao)
        let trackingDraft = ParsedParcelDraft(trackingNumber: "YT0000000000000", channel: .other)
        let upgradeDraft = ParsedParcelDraft(
            pickupCode: "12-3-0000",
            trackingNumber: "YT0000000000000",
            channel: .duoduo
        )

        let classified = deduplicator.classify(
            [first, duplicateOfFirst, trackingDraft, upgradeDraft],
            against: []
        )

        #expect(classified.map(\.kind) == [
            .new,
            .duplicate(existingID: first.id),
            .new,
            .upgradeTrackingOnly(existingID: trackingDraft.id),
        ])
    }

    @Test("Marks tracking-only draft as duplicate when pending parcel already has a code for that tracking number")
    func trackingOnlyDuplicateOfCodedParcel() {
        let existing = Parcel(
            pickupCode: "12-3-0000",
            trackingNumber: "YT0000000000000",
            channel: .duoduo
        )
        let incoming = ParsedParcelDraft(
            trackingNumber: "YT0000000000000",
            channel: .other
        )

        #expect(
            deduplicator.classify(incoming, against: [existing])
                == .duplicate(existingID: existing.id)
        )
    }
}
