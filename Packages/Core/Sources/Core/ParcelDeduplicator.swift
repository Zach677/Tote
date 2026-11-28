import Foundation

public enum DraftIngestionKind: Hashable, Sendable {
    case new
    case upgradeTrackingOnly(existingID: UUID)
    case duplicate(existingID: UUID)
}

public struct ClassifiedDraft: Identifiable, Hashable, Sendable {
    public var id: UUID {
        draft.id
    }

    public var draft: ParsedParcelDraft
    public var kind: DraftIngestionKind

    public init(draft: ParsedParcelDraft, kind: DraftIngestionKind) {
        self.draft = draft
        self.kind = kind
    }
}

public struct ParcelDeduplicator: Sendable {
    public init() {}

    public func classify(
        _ draft: ParsedParcelDraft,
        against existingParcels: [Parcel]
    ) -> DraftIngestionKind {
        let pending = existingParcels.filter(\.isPending)
        return classify(draft, againstPending: pending)
    }

    public func classify(
        _ drafts: [ParsedParcelDraft],
        against existingParcels: [Parcel]
    ) -> [ClassifiedDraft] {
        var workingPending = existingParcels.filter(\.isPending)
        var results: [ClassifiedDraft] = []
        results.reserveCapacity(drafts.count)

        for draft in drafts {
            let kind = classify(draft, againstPending: workingPending)
            results.append(ClassifiedDraft(draft: draft, kind: kind))

            switch kind {
            case .new:
                if draft.isValid {
                    workingPending.append(draft.makeParcel(source: .pasted, now: .distantPast))
                }
            case let .upgradeTrackingOnly(existingID):
                if let index = workingPending.firstIndex(where: { $0.id == existingID }) {
                    workingPending[index] = merge(draft, into: workingPending[index], updatedAt: .distantPast)
                }
            case .duplicate:
                break
            }
        }

        return results
    }

    public func merge(
        _ draft: ParsedParcelDraft,
        into existing: Parcel,
        updatedAt: Date
    ) -> Parcel {
        var merged = existing.trimmed()
        let cleanCode = ParcelNormalization.cleanDisplayCode(draft.pickupCode)
        let cleanTracking = ParcelNormalization.cleanDisplayTrackingNumber(draft.trackingNumber)
        let cleanStation = draft.stationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLockerMAC = draft.lockerMAC.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLockerSiteID = draft.lockerSiteID.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanCode.isEmpty {
            merged.pickupCode = cleanCode
        }
        if merged.trackingNumber.isEmpty, !cleanTracking.isEmpty {
            merged.trackingNumber = cleanTracking
        }
        if draft.channel != .other {
            if merged.channel == .other
                || draft.channel.isPhysicalPickupPoint
                || existing.isTrackingOnly
            {
                merged.channel = draft.channel
            }
        }
        if !cleanStation.isEmpty {
            merged.stationLabel = cleanStation
        }
        if !cleanNote.isEmpty {
            merged.note = cleanNote
        }
        if !cleanLockerMAC.isEmpty {
            merged.lockerMAC = cleanLockerMAC
        }
        if !cleanLockerSiteID.isEmpty {
            merged.lockerSiteID = cleanLockerSiteID
        }

        merged.updatedAt = updatedAt
        return merged
    }
}

private extension ParcelDeduplicator {
    func classify(
        _ draft: ParsedParcelDraft,
        againstPending pending: [Parcel]
    ) -> DraftIngestionKind {
        guard draft.isValid else { return .new }

        if draft.hasPickupCode {
            if let existing = pending.first(where: { candidate in
                guard candidate.hasPickupCode,
                      candidate.channel == draft.channel,
                      candidate.normalizedPickupCode == draft.normalizedPickupCode
                else { return false }

                if draft.hasTrackingNumber,
                   candidate.hasTrackingNumber,
                   draft.normalizedTrackingNumber != candidate.normalizedTrackingNumber
                {
                    return false
                }
                return true
            }) {
                return .duplicate(existingID: existing.id)
            }
        }

        if draft.hasTrackingNumber {
            if let existing = pending.first(where: {
                $0.hasTrackingNumber
                    && $0.normalizedTrackingNumber == draft.normalizedTrackingNumber
            }) {
                if existing.isTrackingOnly, draft.hasPickupCode {
                    return .upgradeTrackingOnly(existingID: existing.id)
                }
                return .duplicate(existingID: existing.id)
            }
        }

        return .new
    }
}
