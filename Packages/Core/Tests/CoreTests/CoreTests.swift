import Core
import Foundation
import Testing

@Suite("Parcel Model")
struct ParcelModelTests {
    @Test("PickupChannel allCases follows exact 5-group physical display order")
    func channelDisplayOrder() {
        #expect(
            PickupChannel.allCases == [
                .station,
                .locker,
                .jd,
                .sfExpress,
                .other,
            ]
        )
    }

    @Test("PickupChannel marks station and locker as physical pickup points")
    func physicalPickupPointClassification() {
        #expect(PickupChannel.station.isPhysicalPickupPoint)
        #expect(PickupChannel.locker.isPhysicalPickupPoint)
        #expect(PickupChannel.jd.isPhysicalPickupPoint == false)
        #expect(PickupChannel.sfExpress.isPhysicalPickupPoint == false)
        #expect(PickupChannel.other.isPhysicalPickupPoint == false)
    }

    @Test("PickupChannel encodes and decodes canonical raw values and rejects unknown values")
    func channelCodableRoundTrip() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        let cases: [(channel: PickupChannel, raw: String)] = [
            (.station, "\"station\""),
            (.locker, "\"locker\""),
            (.jd, "\"jd\""),
            (.sfExpress, "\"sfExpress\""),
            (.other, "\"other\""),
        ]

        for item in cases {
            let encoded = try String(decoding: encoder.encode(item.channel), as: UTF8.self)
            #expect(encoded == item.raw)
            let decoded = try decoder.decode(PickupChannel.self, from: Data(item.raw.utf8))
            #expect(decoded == item.channel)
        }

        do {
            _ = try decoder.decode(PickupChannel.self, from: Data("\"unknownChannel\"".utf8))
            Issue.record("Expected DecodingError.dataCorrupted for unknown PickupChannel raw value")
        } catch DecodingError.dataCorrupted {
            // Expected error
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Parcel computed properties reflect pickup code, tracking number, and status")
    func parcelComputedProperties() {
        let pickupDate = Date(timeIntervalSince1970: 1_700_000_000)

        let codeParcel = Parcel(pickupCode: " a03 - 8821 ", channel: .locker)
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
            channel: .station
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
            channel: .station
        )
        #expect(draft.normalizedPickupCode == "12-3-0000")
        #expect(draft.normalizedTrackingNumber == "SF0000000000000")
        #expect(draft.hasPickupCode)
        #expect(draft.hasTrackingNumber)
        #expect(draft.isTrackingOnly == false)
        #expect(draft.isValid)
    }
}
