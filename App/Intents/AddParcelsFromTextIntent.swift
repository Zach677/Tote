import AppIntents
import Core
import Foundation

struct AddParcelsFromTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Parcels from Text"
    static let description = IntentDescription(
        "Extract pickup codes and tracking numbers from text, SMS messages, or screenshots and save them to Tote.",
        resultValueName: "Saved Parcel Count"
    )
    static let supportedModes: IntentModes = .background

    @Parameter(
        title: "Text",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var text: String

    @Dependency
    private var parcelStore: ParcelStore

    static var parameterSummary: some ParameterSummary {
        Summary("Add parcels from \(\.$text)")
    }

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let outcome = try Self.ingest(text: text, into: parcelStore)
        return .result(value: outcome.savedCount, dialog: outcome.dialog)
    }

    struct IngestionOutcome {
        let savedCount: Int
        let addedCount: Int
        let updatedCount: Int
        let skippedDuplicateCount: Int
        let dialogResource: LocalizedStringResource

        var dialog: IntentDialog {
            IntentDialog(dialogResource)
        }
    }

    @MainActor
    static func ingest(
        text: String,
        into parcelStore: ParcelStore,
        parser: PickupParser = PickupParser(),
        notificationCenter: NotificationCenter = .default
    ) throws -> IngestionOutcome {
        let drafts = parser.parse(text).filter(\.isValid)
        guard !drafts.isEmpty else {
            return IngestionOutcome(
                savedCount: 0,
                addedCount: 0,
                updatedCount: 0,
                skippedDuplicateCount: 0,
                dialogResource: LocalizedStringResource("No pickup codes or tracking numbers found.")
            )
        }

        let result = try parcelStore.add(drafts, source: .pasted)
        let addedCount = result.added.count
        let updatedCount = result.updated.count
        let skippedCount = result.skippedDuplicateCount
        let savedCount = addedCount + updatedCount

        if savedCount > 0 {
            notificationCenter.post(name: .toteParcelsDidChange, object: nil)
        }

        let dialogResource = makeDialogResource(
            addedCount: addedCount,
            updatedCount: updatedCount,
            skippedCount: skippedCount
        )

        return IngestionOutcome(
            savedCount: savedCount,
            addedCount: addedCount,
            updatedCount: updatedCount,
            skippedDuplicateCount: skippedCount,
            dialogResource: dialogResource
        )
    }

    private static func makeDialogResource(
        addedCount: Int,
        updatedCount: Int,
        skippedCount: Int
    ) -> LocalizedStringResource {
        let savedCount = addedCount + updatedCount
        guard savedCount > 0 else {
            if skippedCount == 1 {
                return LocalizedStringResource("Already in Tote.")
            }
            return LocalizedStringResource("All \(skippedCount) parcels are already in Tote.")
        }

        if skippedCount > 0 {
            if savedCount == 1 {
                return LocalizedStringResource("Saved 1 parcel to Tote (\(skippedCount) skipped).")
            }
            return LocalizedStringResource("Saved \(savedCount) parcels to Tote (\(skippedCount) skipped).")
        }

        if addedCount > 0, updatedCount > 0 {
            return LocalizedStringResource("Added \(addedCount) and updated \(updatedCount) parcels in Tote.")
        }

        if addedCount > 0 {
            if addedCount == 1 {
                return LocalizedStringResource("Added 1 parcel to Tote.")
            }
            return LocalizedStringResource("Added \(addedCount) parcels to Tote.")
        }

        if updatedCount == 1 {
            return LocalizedStringResource("Updated 1 parcel in Tote.")
        }
        return LocalizedStringResource("Updated \(updatedCount) parcels in Tote.")
    }
}

struct ToteAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddParcelsFromTextIntent(),
            phrases: [
                "Add parcels to \(.applicationName)",
                "Save pickup code in \(.applicationName)",
            ],
            shortTitle: "Add Parcels",
            systemImageName: "shippingbox"
        )
    }
}
