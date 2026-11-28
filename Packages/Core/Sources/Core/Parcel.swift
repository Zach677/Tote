import Foundation

public enum PickupChannel: String, CaseIterable, Codable, Hashable, Sendable {
    case station
    case locker
    case jd
    case sfExpress
    case other

    public var isPhysicalPickupPoint: Bool {
        switch self {
        case .station, .locker:
            true
        case .jd, .sfExpress, .other:
            false
        }
    }
}

public enum ParcelSource: String, Codable, Hashable, Sendable {
    case pasted
    case manual
    case synced
}

public enum ParcelStatus: Codable, Hashable, Sendable {
    case pending
    case pickedUp(at: Date)
}

public struct Parcel: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var pickupCode: String
    public var trackingNumber: String
    public var channel: PickupChannel
    public var stationLabel: String
    public var note: String
    public var lockerMAC: String
    public var lockerSiteID: String
    public var status: ParcelStatus
    public var source: ParcelSource
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        pickupCode: String = "",
        trackingNumber: String = "",
        channel: PickupChannel = .other,
        stationLabel: String = "",
        note: String = "",
        lockerMAC: String = "",
        lockerSiteID: String = "",
        status: ParcelStatus = .pending,
        source: ParcelSource = .pasted,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.pickupCode = pickupCode
        self.trackingNumber = trackingNumber
        self.channel = channel
        self.stationLabel = stationLabel
        self.note = note
        self.lockerMAC = lockerMAC
        self.lockerSiteID = lockerSiteID
        self.status = status
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var normalizedPickupCode: String {
        ParcelNormalization.normalizePickupCode(pickupCode)
    }

    public var normalizedTrackingNumber: String {
        ParcelNormalization.normalizeTrackingNumber(trackingNumber)
    }

    public var hasPickupCode: Bool {
        !normalizedPickupCode.isEmpty
    }

    public var hasTrackingNumber: Bool {
        !normalizedTrackingNumber.isEmpty
    }

    public var isTrackingOnly: Bool {
        !hasPickupCode && hasTrackingNumber
    }

    public var isValid: Bool {
        hasPickupCode || hasTrackingNumber
    }

    public var isPending: Bool {
        if case .pending = status {
            return true
        }
        return false
    }

    public var isPickedUp: Bool {
        !isPending
    }

    public var pickedUpAt: Date? {
        if case let .pickedUp(at: date) = status {
            return date
        }
        return nil
    }

    func trimmed() -> Parcel {
        Parcel(
            id: id,
            pickupCode: ParcelNormalization.cleanDisplayCode(pickupCode),
            trackingNumber: ParcelNormalization.cleanDisplayTrackingNumber(trackingNumber),
            channel: channel,
            stationLabel: stationLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            lockerMAC: lockerMAC.trimmingCharacters(in: .whitespacesAndNewlines),
            lockerSiteID: lockerSiteID.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status,
            source: source,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public struct ParsedParcelDraft: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var pickupCode: String
    public var trackingNumber: String
    public var channel: PickupChannel
    public var stationLabel: String
    public var note: String
    public var lockerMAC: String
    public var lockerSiteID: String

    public init(
        id: UUID = UUID(),
        pickupCode: String = "",
        trackingNumber: String = "",
        channel: PickupChannel = .other,
        stationLabel: String = "",
        note: String = "",
        lockerMAC: String = "",
        lockerSiteID: String = ""
    ) {
        self.id = id
        self.pickupCode = pickupCode
        self.trackingNumber = trackingNumber
        self.channel = channel
        self.stationLabel = stationLabel
        self.note = note
        self.lockerMAC = lockerMAC
        self.lockerSiteID = lockerSiteID
    }

    public var normalizedPickupCode: String {
        ParcelNormalization.normalizePickupCode(pickupCode)
    }

    public var normalizedTrackingNumber: String {
        ParcelNormalization.normalizeTrackingNumber(trackingNumber)
    }

    public var hasPickupCode: Bool {
        !normalizedPickupCode.isEmpty
    }

    public var hasTrackingNumber: Bool {
        !normalizedTrackingNumber.isEmpty
    }

    public var isTrackingOnly: Bool {
        !hasPickupCode && hasTrackingNumber
    }

    public var isValid: Bool {
        hasPickupCode || hasTrackingNumber
    }

    public func makeParcel(source: ParcelSource, now: Date) -> Parcel {
        Parcel(
            id: id,
            pickupCode: ParcelNormalization.cleanDisplayCode(pickupCode),
            trackingNumber: ParcelNormalization.cleanDisplayTrackingNumber(trackingNumber),
            channel: channel,
            stationLabel: stationLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            lockerMAC: lockerMAC.trimmingCharacters(in: .whitespacesAndNewlines),
            lockerSiteID: lockerSiteID.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .pending,
            source: source,
            createdAt: now,
            updatedAt: now
        )
    }
}

enum ParcelNormalization {
    private static let dashScalars: Set<Unicode.Scalar> = [
        "\u{FF0D}", // Fullwidth hyphen-minus
        "\u{2014}", // Em dash
        "\u{2013}", // En dash
        "\u{2212}", // Minus sign
        "\u{FE63}", // Small hyphen-minus
        "\u{2010}", // Hyphen
        "\u{2011}", // Non-breaking hyphen
        "\u{2012}", // Figure dash
    ]

    static func normalizeFullwidthAndDashes(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        result.reserveCapacity(text.unicodeScalars.count)

        for scalar in text.unicodeScalars {
            if dashScalars.contains(scalar) {
                result.append("-")
            } else if scalar.value == 0x3000 {
                result.append(" ")
            } else if scalar.value >= 0xFF01, scalar.value <= 0xFF5E,
                      let ascii = Unicode.Scalar(scalar.value - 0xFEE0)
            {
                result.append(ascii)
            } else {
                result.append(scalar)
            }
        }

        return String(result)
    }

    static func cleanDisplayCode(_ raw: String) -> String {
        let normalized = normalizeFullwidthAndDashes(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(normalized.unicodeScalars.count)
        for scalar in normalized.unicodeScalars where !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            scalars.append(scalar)
        }
        return String(scalars).uppercased()
    }

    static func cleanDisplayTrackingNumber(_ raw: String) -> String {
        let normalized = normalizeFullwidthAndDashes(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(normalized.unicodeScalars.count)
        for scalar in normalized.unicodeScalars where !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            scalars.append(scalar)
        }
        return String(scalars).uppercased()
    }

    static func normalizePickupCode(_ raw: String) -> String {
        cleanDisplayCode(raw)
    }

    static func normalizeTrackingNumber(_ raw: String) -> String {
        cleanDisplayTrackingNumber(raw).replacingOccurrences(of: "-", with: "")
    }
}
