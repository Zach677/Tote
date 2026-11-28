import Core
import Foundation
import Testing

@Suite("ParcelStore")
struct ParcelStoreTests {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tote-core-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Returns empty array when store file does not exist")
    func loadMissingFileReturnsEmpty() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ParcelStore(directoryURL: dir)
        let loaded = try store.load()

        #expect(loaded.isEmpty)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path) == false)
    }

    @Test("Creates parent directories and persists add, update, markPickedUp, restore, and delete")
    func fullCrudRoundTrip() throws {
        let root = makeTempDirectory()
        let nestedDir = root.appendingPathComponent("Nested/Data", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_001_000)
        let t2 = Date(timeIntervalSince1970: 1_700_002_000)
        let t3 = Date(timeIntervalSince1970: 1_700_003_000)

        let store0 = ParcelStore(directoryURL: nestedDir, now: { t0 })
        let draft = ParsedParcelDraft(
            pickupCode: "12-3-0000",
            trackingNumber: "YT0000000000000",
            channel: .station,
            stationLabel: "Demo Station B",
            note: "Demo Item"
        )

        let addResult = try store0.add([draft], source: .pasted)
        let added = try #require(addResult.added.first)
        #expect(addResult.added.count == 1)
        #expect(addResult.updated.isEmpty)
        #expect(addResult.skippedDuplicateCount == 0)
        #expect(addResult.firstAffectedID == added.id)
        #expect(FileManager.default.fileExists(atPath: store0.fileURL.path))

        // Duplicate add is skipped
        let dupResult = try store0.add([draft], source: .pasted)
        #expect(dupResult.added.isEmpty)
        #expect(dupResult.updated.isEmpty)
        #expect(dupResult.skippedDuplicateCount == 1)
        #expect(dupResult.firstAffectedID == nil)

        // Update
        let store1 = ParcelStore(directoryURL: nestedDir, now: { t1 })
        var edited = added
        edited.stationLabel = "North Pickup Point"
        edited.note = "Updated Item"
        let afterUpdate = try store1.update(edited)
        #expect(afterUpdate.count == 1)
        #expect(afterUpdate[0].stationLabel == "North Pickup Point")
        #expect(afterUpdate[0].note == "Updated Item")
        #expect(afterUpdate[0].updatedAt == t1)

        // Mark picked up
        let store2 = ParcelStore(directoryURL: nestedDir, now: { t2 })
        let afterPicked = try store2.markPickedUp(id: added.id)
        #expect(afterPicked[0].status == .pickedUp(at: t2))
        #expect(afterPicked[0].updatedAt == t2)

        // Restore to pending
        let store3 = ParcelStore(directoryURL: nestedDir, now: { t3 })
        let afterRestore = try store3.restoreToPending(id: added.id)
        #expect(afterRestore[0].status == .pending)
        #expect(afterRestore[0].updatedAt == t3)

        // Delete
        let afterDelete = try store3.delete(id: added.id)
        #expect(afterDelete.isEmpty)
        #expect(try store3.load().isEmpty)
    }

    @Test("Upgrades tracking-only parcel on add and reports updated result")
    func addUpgradesTrackingOnlyParcel() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_005_000)

        let store0 = ParcelStore(directoryURL: dir, now: { t0 })
        let trackingDraft = ParsedParcelDraft(
            trackingNumber: "SF0000000000000",
            channel: .sfExpress,
            note: "Demo Item"
        )
        let initial = try store0.add([trackingDraft], source: .pasted)
        let original = try #require(initial.added.first)

        let store1 = ParcelStore(directoryURL: dir, now: { t1 })
        let arrivalDraft = ParsedParcelDraft(
            pickupCode: "12-3-0000",
            trackingNumber: "SF0000000000000",
            channel: .station,
            stationLabel: "Demo Station B"
        )
        let upgraded = try store1.add([arrivalDraft], source: .pasted)

        #expect(upgraded.added.isEmpty)
        #expect(upgraded.updated.count == 1)
        #expect(upgraded.firstAffectedID == original.id)
        #expect(upgraded.updated[0].id == original.id)
        #expect(upgraded.updated[0].pickupCode == "12-3-0000")
        #expect(upgraded.updated[0].channel == .station)
        #expect(upgraded.updated[0].stationLabel == "Demo Station B")
        #expect(upgraded.updated[0].note == "Demo Item")
    }

    @Test("Auto-prunes picked-up parcels older than 30 days while keeping 29-day and exact 30-day entries")
    func retentionBoundaryPruning() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let day: TimeInterval = 86400
        let nowDate = Date(timeIntervalSince1970: 1_710_000_000)
        let kept29Days = nowDate.addingTimeInterval(-29 * day)
        let keptExact30Days = nowDate.addingTimeInterval(-30 * day)
        let pruned30DaysAndOneSecond = nowDate.addingTimeInterval(-(30 * day + 1))
        let pruned31Days = nowDate.addingTimeInterval(-31 * day)
        let oldPendingDate = nowDate.addingTimeInterval(-60 * day)

        // Seed parcels at their historical timestamps
        let seedStore = ParcelStore(directoryURL: dir, now: { oldPendingDate })
        let added = try seedStore.add(
            [
                ParsedParcelDraft(pickupCode: "1-0-0001", channel: .station),
                ParsedParcelDraft(pickupCode: "1-0-0002", channel: .station),
                ParsedParcelDraft(pickupCode: "1-0-0003", channel: .station),
                ParsedParcelDraft(pickupCode: "1-0-0004", channel: .station),
                ParsedParcelDraft(pickupCode: "1-0-0005", channel: .station),
            ],
            source: .manual
        ).added
        try #require(added.count == 5)

        try ParcelStore(directoryURL: dir, now: { kept29Days }).markPickedUp(id: added[0].id)
        try ParcelStore(directoryURL: dir, now: { keptExact30Days }).markPickedUp(id: added[1].id)
        try ParcelStore(directoryURL: dir, now: { pruned30DaysAndOneSecond }).markPickedUp(id: added[2].id)
        try ParcelStore(directoryURL: dir, now: { pruned31Days }).markPickedUp(id: added[3].id)
        // added[4] stays pending even though it is 60 days old

        let checkStore = ParcelStore(directoryURL: dir, retentionDays: 30, now: { nowDate })
        let remaining = try checkStore.load()
        let remainingIDs = Set(remaining.map(\.id))

        #expect(remainingIDs == Set([added[0].id, added[1].id, added[4].id]))
        #expect(remainingIDs.contains(added[2].id) == false)
        #expect(remainingIDs.contains(added[3].id) == false)

        // Confirm pruning was persisted back to disk
        let reloaded = try ParcelStore(directoryURL: dir, retentionDays: 365, now: { nowDate }).load()
        #expect(Set(reloaded.map(\.id)) == remainingIDs)
    }

    @Test("Throws corruptedData on invalid JSON without overwriting the file")
    func corruptedFileIsPreserved() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ParcelStore(directoryURL: dir)
        let rawCorrupted = Data("{ not valid json".utf8)
        try rawCorrupted.write(to: store.fileURL)

        do {
            _ = try store.load()
            Issue.record("Expected ParcelStoreError.corruptedData")
        } catch ParcelStoreError.corruptedData {
            // Expected error
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let untouched = try Data(contentsOf: store.fileURL)
        #expect(untouched == rawCorrupted)
    }

    @Test("Validates invalid parcels and missing parcel IDs")
    func errorHandlingForInvalidOperations() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ParcelStore(directoryURL: dir)
        let missingID = UUID()

        #expect(throws: ParcelStoreError.invalidParcel) {
            try store.add([ParsedParcelDraft()], source: .manual)
        }
        #expect(throws: ParcelStoreError.invalidParcel) {
            try store.update(Parcel())
        }
        #expect(throws: ParcelStoreError.parcelNotFound(missingID)) {
            try store.update(Parcel(id: missingID, pickupCode: "12-3-0000"))
        }
        #expect(throws: ParcelStoreError.parcelNotFound(missingID)) {
            try store.markPickedUp(id: missingID)
        }
        #expect(throws: ParcelStoreError.parcelNotFound(missingID)) {
            try store.restoreToPending(id: missingID)
        }
        #expect(throws: ParcelStoreError.parcelNotFound(missingID)) {
            try store.delete(id: missingID)
        }
    }

    @Test("Rejects unsupported schema version without clobbering file and decodes whole-second ISO-8601 dates")
    func schemaVersionAndWholeSecondISO8601() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = ParcelStore(
            directoryURL: dir,
            now: { Date(timeIntervalSince1970: 1_764_144_000) }
        )

        let futureSchemaJSON = Data(#"{"schemaVersion":99,"parcels":[]}"#.utf8)
        try futureSchemaJSON.write(to: store.fileURL)

        do {
            _ = try store.load()
            Issue.record("Expected corruptedData for unsupported schema version")
        } catch ParcelStoreError.corruptedData {
            // Expected
        }
        #expect(try Data(contentsOf: store.fileURL) == futureSchemaJSON)

        let wholeSecondJSON = Data(
            """
            {
              "schemaVersion": 1,
              "parcels": [
                {
                  "id": "00000000-0000-0000-0000-000000000010",
                  "pickupCode": "12-3-0000",
                  "trackingNumber": "YT0000000000000",
                  "channel": "station",
                  "stationLabel": "Demo Station B",
                  "note": "",
                  "lockerMAC": "",
                  "lockerSiteID": "",
                  "status": { "pending": {} },
                  "source": "pasted",
                  "createdAt": "2025-11-26T08:00:00Z",
                  "updatedAt": "2025-11-26T08:00:00Z"
                }
              ]
            }
            """.utf8
        )
        try wholeSecondJSON.write(to: store.fileURL)

        let loaded = try store.load()
        let parcel = try #require(loaded.first)
        #expect(loaded.count == 1)
        #expect(parcel.pickupCode == "12-3-0000")
        #expect(parcel.channel == .station)
    }

    @Test("Throws corruptedData on unknown channel string without overwriting the file")
    func rejectsUnknownChannelJSONAsCorruptedData() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = ParcelStore(directoryURL: dir)
        let unknownChannelJSON = Data(
            """
            {
              "schemaVersion": 1,
              "parcels": [
                {
                  "id": "00000000-0000-0000-0000-000000000088",
                  "pickupCode": "12-3-0000",
                  "trackingNumber": "",
                  "channel": "unknownBrand",
                  "stationLabel": "",
                  "note": "",
                  "lockerMAC": "",
                  "lockerSiteID": "",
                  "status": { "pending": {} },
                  "source": "manual",
                  "createdAt": "2025-11-26T08:00:00Z",
                  "updatedAt": "2025-11-26T08:00:00Z"
                }
              ]
            }
            """.utf8
        )
        try unknownChannelJSON.write(to: store.fileURL)

        do {
            _ = try store.load()
            Issue.record("Expected ParcelStoreError.corruptedData for unknown channel string")
        } catch ParcelStoreError.corruptedData {
            // Expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(try Data(contentsOf: store.fileURL) == unknownChannelJSON)
    }

    @Test("Coalesces intra-batch tracking-only and arrival drafts into a single added parcel")
    func intraBatchTrackingUpgradeReportsSingleAddedParcel() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let nowDate = Date(timeIntervalSince1970: 1_700_000_000)
        let store = ParcelStore(directoryURL: dir, now: { nowDate })

        let trackingDraft = ParsedParcelDraft(trackingNumber: "YT0000000000000", channel: .other)
        let arrivalDraft = ParsedParcelDraft(
            pickupCode: "12-3-0000",
            trackingNumber: "YT0000000000000",
            channel: .station,
            stationLabel: "Demo Station B"
        )

        let result = try store.add([trackingDraft, arrivalDraft], source: .pasted)
        #expect(result.added.count == 1)
        #expect(result.updated.isEmpty)
        #expect(result.skippedDuplicateCount == 0)
        #expect(result.added[0].pickupCode == "12-3-0000")
        #expect(result.added[0].trackingNumber == "YT0000000000000")
        #expect(result.added[0].channel == .station)
        #expect(try store.load().count == 1)
    }

    @Test("Rejects duplicate parcel IDs on disk as corruptedData without overwriting file")
    func duplicateIDsOnDiskThrowCorruptedData() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = ParcelStore(directoryURL: dir)
        let dupJSON = Data(
            """
            {
              "schemaVersion": 1,
              "parcels": [
                {
                  "id": "00000000-0000-0000-0000-000000000099",
                  "pickupCode": "1-0-0001",
                  "trackingNumber": "",
                  "channel": "station",
                  "stationLabel": "",
                  "note": "",
                  "lockerMAC": "",
                  "lockerSiteID": "",
                  "status": { "pending": {} },
                  "source": "manual",
                  "createdAt": "2025-11-26T08:00:00Z",
                  "updatedAt": "2025-11-26T08:00:00Z"
                },
                {
                  "id": "00000000-0000-0000-0000-000000000099",
                  "pickupCode": "1-0-0002",
                  "trackingNumber": "",
                  "channel": "locker",
                  "stationLabel": "",
                  "note": "",
                  "lockerMAC": "",
                  "lockerSiteID": "",
                  "status": { "pending": {} },
                  "source": "manual",
                  "createdAt": "2025-11-26T08:00:00Z",
                  "updatedAt": "2025-11-26T08:00:00Z"
                }
              ]
            }
            """.utf8
        )
        try dupJSON.write(to: store.fileURL)

        do {
            _ = try store.load()
            Issue.record("Expected ParcelStoreError.corruptedData for duplicate IDs")
        } catch ParcelStoreError.corruptedData {
            // Expected
        }
        #expect(try Data(contentsOf: store.fileURL) == dupJSON)
    }

    @Test("Keeps exact 30-day boundary picked-up parcel when now has sub-millisecond fractional seconds")
    func subMillisecondRetentionBoundary() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let subMsNow = Date(timeIntervalSince1970: 1_710_000_000.0004)
        let exact30DaysAgo = subMsNow.addingTimeInterval(-30 * 86400)
        let seedStore = ParcelStore(directoryURL: dir, now: { exact30DaysAgo })

        let added = try seedStore.add(
            [ParsedParcelDraft(pickupCode: "1-0-0001", channel: .station)],
            source: .manual
        ).added
        try seedStore.markPickedUp(id: added[0].id)

        let checkStore = ParcelStore(directoryURL: dir, retentionDays: 30, now: { subMsNow })
        let reloaded = try checkStore.load()
        #expect(reloaded.count == 1)
    }
}
