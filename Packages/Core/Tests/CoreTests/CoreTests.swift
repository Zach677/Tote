import Core
import Foundation
import Testing

@Suite("Parcel Model")
struct ParcelModelTests {
    @Test("PickupChannel allCases follows exact display order")
    func channelDisplayOrder() {
        #expect(
            PickupChannel.allCases == [
                .duoduo,
                .yixiaoji,
                .cainiao,
                .sfExpress,
                .jd,
                .other,
            ]
        )
    }

    @Test("Parcel computed properties reflect pickup code, tracking number, and status")
    func parcelComputedProperties() {
        let pickupDate = Date(timeIntervalSince1970: 1_700_000_000)

        let codeParcel = Parcel(pickupCode: " a03 - 8821 ", channel: .yixiaoji)
        #expect(codeParcel.hasPickupCode)
        #expect(codeParcel.hasTrackingNumber == false)
        #expect(codeParcel.isTrackingOnly == false)
        #expect(codeParcel.isValid)
        #expect(codeParcel.isPending)
        #expect(codeParcel.isPickedUp == false)
        #expect(codeParcel.pickedUpAt == nil)
        #expect(codeParcel.normalizedPickupCode == "A03-8821")

        let trackingOnly = Parcel(trackingNumber: " yt-0000000000000 ", channel: .other)
        #expect(trackingOnly.hasPickupCode == false)
        #expect(trackingOnly.hasTrackingNumber)
        #expect(trackingOnly.isTrackingOnly)
        #expect(trackingOnly.isValid)
        #expect(trackingOnly.normalizedTrackingNumber == "YT0000000000000")

        let codedWithTracking = Parcel(
            pickupCode: "12-3-0000",
            trackingNumber: "YT0000000000000",
            channel: .duoduo
        )
        #expect(codedWithTracking.hasPickupCode)
        #expect(codedWithTracking.hasTrackingNumber)
        #expect(codedWithTracking.isTrackingOnly == false)
        #expect(codedWithTracking.isValid)

        let emptyParcel = Parcel(pickupCode: "   ", trackingNumber: "\n")
        #expect(emptyParcel.isValid == false)
        #expect(emptyParcel.isTrackingOnly == false)

        let pickedUpParcel = Parcel(
            pickupCode: "12-3-0000",
            status: .pickedUp(at: pickupDate)
        )
        #expect(pickedUpParcel.isPending == false)
        #expect(pickedUpParcel.isPickedUp)
        #expect(pickedUpParcel.pickedUpAt == pickupDate)
    }

    @Test("ParsedParcelDraft normalizes fullwidth codes and derives validity")
    func draftNormalization() {
        let draft = ParsedParcelDraft(
            pickupCode: "１２－３－００００",
            trackingNumber: "ｓｆ０００００００００００００",
            channel: .duoduo
        )
        #expect(draft.normalizedPickupCode == "12-3-0000")
        #expect(draft.normalizedTrackingNumber == "SF0000000000000")
        #expect(draft.hasPickupCode)
        #expect(draft.hasTrackingNumber)
        #expect(draft.isTrackingOnly == false)
        #expect(draft.isValid)
    }
}
