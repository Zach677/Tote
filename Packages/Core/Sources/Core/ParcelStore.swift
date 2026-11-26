import Foundation

public enum ParcelStoreError: Error, Equatable, Sendable {
    case corruptedData(String)
    case parcelNotFound(UUID)
    case invalidParcel
    case ioFailure(String)
}

public struct AddParcelsResult: Equatable, Sendable {
    public var added: [Parcel]
    public var updated: [Parcel]
    public var skippedDuplicateCount: Int
    public var firstAffectedID: UUID?

    public init(
        added: [Parcel] = [],
        updated: [Parcel] = [],
        skippedDuplicateCount: Int = 0,
        firstAffectedID: UUID? = nil
    ) {
        self.added = added
        self.updated = updated
        self.skippedDuplicateCount = skippedDuplicateCount
        self.firstAffectedID = firstAffectedID
    }
}

public struct ParcelStore: Sendable {
    public static let defaultFileName = "parcels.json"
    public static let defaultRetentionDays = 30
    public static let currentSchemaVersion = 1

    public let fileURL: URL
    public let retentionDays: Int
    private let now: @Sendable () -> Date

    public init(
        fileURL: URL,
        retentionDays: Int = ParcelStore.defaultRetentionDays,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.retentionDays = max(0, retentionDays)
        self.now = now
    }

    public init(
        directoryURL: URL,
        fileName: String = ParcelStore.defaultFileName,
        retentionDays: Int = ParcelStore.defaultRetentionDays,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(
            fileURL: directoryURL.appendingPathComponent(fileName, isDirectory: false),
            retentionDays: retentionDays,
            now: now
        )
    }

    public func load() throws -> [Parcel] {
        let parcels = try readParcelsFromDisk()
        let currentDate = now()
        let rawCutoff = currentDate.addingTimeInterval(-TimeInterval(retentionDays) * 86400)
        // Align with millisecond precision of ISO-8601 persistence so sub-ms truncation
        // never prematurely prunes an exact retention-boundary timestamp.
        let cutoff = Date(timeIntervalSince1970: floor(rawCutoff.timeIntervalSince1970 * 1000) / 1000)

        let retained = parcels.filter { parcel in
            guard let pickedUpAt = parcel.pickedUpAt else { return true }
            return pickedUpAt >= cutoff
        }

        if retained.count != parcels.count {
            try saveParcelsToDisk(retained)
        }

        return retained
    }

    public func add(
        _ drafts: [ParsedParcelDraft],
        source: ParcelSource
    ) throws -> AddParcelsResult {
        guard !drafts.isEmpty else {
            return AddParcelsResult()
        }
        guard drafts.allSatisfy(\.isValid) else {
            throw ParcelStoreError.invalidParcel
        }

        var parcels = try load()
        let deduplicator = ParcelDeduplicator()
        let classified = deduplicator.classify(drafts, against: parcels)
        let timestamp = now()

        var addedIDs: [UUID] = []
        var updatedIDs: [UUID] = []
        var skippedDuplicateCount = 0
        var firstAffectedID: UUID?

        for item in classified {
            switch item.kind {
            case .new:
                let parcel = item.draft.makeParcel(source: source, now: timestamp)
                parcels.append(parcel)
                addedIDs.append(parcel.id)
                if firstAffectedID == nil {
                    firstAffectedID = parcel.id
                }
            case let .upgradeTrackingOnly(existingID):
                guard let index = parcels.firstIndex(where: { $0.id == existingID }) else {
                    continue
                }
                let merged = deduplicator.merge(item.draft, into: parcels[index], updatedAt: timestamp)
                parcels[index] = merged
                if !addedIDs.contains(existingID), !updatedIDs.contains(existingID) {
                    updatedIDs.append(existingID)
                }
                if firstAffectedID == nil {
                    firstAffectedID = existingID
                }
            case .duplicate:
                skippedDuplicateCount += 1
            }
        }

        if !addedIDs.isEmpty || !updatedIDs.isEmpty {
            try saveParcelsToDisk(parcels)
        }

        let byID = Dictionary(parcels.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let added = addedIDs.compactMap { byID[$0] }
        let updated = updatedIDs.compactMap { byID[$0] }

        return AddParcelsResult(
            added: added,
            updated: updated,
            skippedDuplicateCount: skippedDuplicateCount,
            firstAffectedID: firstAffectedID
        )
    }

    @discardableResult
    public func update(_ parcel: Parcel) throws -> [Parcel] {
        guard parcel.isValid else {
            throw ParcelStoreError.invalidParcel
        }

        var parcels = try load()
        guard let index = parcels.firstIndex(where: { $0.id == parcel.id }) else {
            throw ParcelStoreError.parcelNotFound(parcel.id)
        }

        var updated = parcel.trimmed()
        updated.updatedAt = now()
        parcels[index] = updated

        try saveParcelsToDisk(parcels)
        return parcels
    }

    @discardableResult
    public func markPickedUp(id: UUID) throws -> [Parcel] {
        var parcels = try load()
        guard let index = parcels.firstIndex(where: { $0.id == id }) else {
            throw ParcelStoreError.parcelNotFound(id)
        }

        let timestamp = now()
        parcels[index].status = .pickedUp(at: timestamp)
        parcels[index].updatedAt = timestamp

        try saveParcelsToDisk(parcels)
        return parcels
    }

    @discardableResult
    public func restoreToPending(id: UUID) throws -> [Parcel] {
        var parcels = try load()
        guard let index = parcels.firstIndex(where: { $0.id == id }) else {
            throw ParcelStoreError.parcelNotFound(id)
        }

        parcels[index].status = .pending
        parcels[index].updatedAt = now()

        try saveParcelsToDisk(parcels)
        return parcels
    }

    @discardableResult
    public func delete(id: UUID) throws -> [Parcel] {
        var parcels = try load()
        guard let index = parcels.firstIndex(where: { $0.id == id }) else {
            throw ParcelStoreError.parcelNotFound(id)
        }

        parcels.remove(at: index)
        try saveParcelsToDisk(parcels)
        return parcels
    }
}

// MARK: - Persistence Envelope

private extension ParcelStore {
    struct Document: Codable, Sendable {
        var schemaVersion: Int
        var parcels: [Parcel]
    }

    func readParcelsFromDisk() throws -> [Parcel] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ParcelStoreError.ioFailure(error.localizedDescription)
        }

        let document: Document
        do {
            document = try Self.makeDecoder().decode(Document.self, from: data)
        } catch {
            throw ParcelStoreError.corruptedData(error.localizedDescription)
        }

        guard document.schemaVersion == Self.currentSchemaVersion else {
            throw ParcelStoreError.corruptedData("Unsupported schema version: \(document.schemaVersion)")
        }

        let uniqueIDs = Set(document.parcels.map(\.id))
        guard uniqueIDs.count == document.parcels.count else {
            throw ParcelStoreError.corruptedData("Duplicate parcel IDs found in store")
        }

        return document.parcels
    }

    func saveParcelsToDisk(_ parcels: [Parcel]) throws {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let document = Document(schemaVersion: Self.currentSchemaVersion, parcels: parcels)
            let data = try Self.makeEncoder().encode(document)
            try data.write(to: fileURL, options: .atomic)
        } catch let error as ParcelStoreError {
            throw error
        } catch {
            throw ParcelStoreError.ioFailure(error.localizedDescription)
        }
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
                return date
            }
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date string: \(string)"
            )
        }
        return decoder
    }
}
