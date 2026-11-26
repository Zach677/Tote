import Foundation

public struct DashboardGroups: Equatable, Sendable {
    public struct ChannelSection: Identifiable, Equatable, Sendable {
        public var id: PickupChannel {
            channel
        }

        public var channel: PickupChannel
        public var parcels: [Parcel]

        public init(channel: PickupChannel, parcels: [Parcel]) {
            self.channel = channel
            self.parcels = parcels
        }
    }

    public var channelSections: [ChannelSection]
    public var awaitingCode: [Parcel]
    public var pickedUp: [Parcel]

    public init(
        channelSections: [ChannelSection] = [],
        awaitingCode: [Parcel] = [],
        pickedUp: [Parcel] = []
    ) {
        self.channelSections = channelSections
        self.awaitingCode = awaitingCode
        self.pickedUp = pickedUp
    }

    public init(parcels: [Parcel]) {
        var byChannel: [PickupChannel: [Parcel]] = [:]
        var trackingOnly: [Parcel] = []
        var completed: [Parcel] = []

        for parcel in parcels {
            if parcel.isPickedUp {
                completed.append(parcel)
            } else if parcel.hasPickupCode {
                byChannel[parcel.channel, default: []].append(parcel)
            } else if parcel.isTrackingOnly {
                trackingOnly.append(parcel)
            }
        }

        channelSections = PickupChannel.allCases.compactMap { channel in
            guard let items = byChannel[channel], !items.isEmpty else { return nil }
            return ChannelSection(
                channel: channel,
                parcels: items.sorted(by: Self.pendingSort)
            )
        }
        awaitingCode = trackingOnly.sorted(by: Self.pendingSort)
        pickedUp = completed.sorted(by: Self.pickedUpSort)
    }

    public var pendingCount: Int {
        channelSections.reduce(0) { $0 + $1.parcels.count } + awaitingCode.count
    }

    public var hasPendingParcels: Bool {
        pendingCount > 0
    }

    public var hasPickedUpParcels: Bool {
        !pickedUp.isEmpty
    }
}

private extension DashboardGroups {
    static func pendingSort(_ lhs: Parcel, _ rhs: Parcel) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func pickedUpSort(_ lhs: Parcel, _ rhs: Parcel) -> Bool {
        let lhsDate = lhs.pickedUpAt ?? .distantPast
        let rhsDate = rhs.pickedUpAt ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
