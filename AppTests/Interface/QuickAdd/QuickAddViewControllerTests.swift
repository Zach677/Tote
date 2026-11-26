@testable import App
import Core
import Foundation
import Testing
import UIKit

struct QuickAddViewControllerTests {
    @Test
    func emptyStateShowsManualEntryAndDisablesAdd() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let controller = QuickAddViewController(
            dependencies: env.dependencies,
            existingParcels: []
        ) { _ in }
        controller.loadViewIfNeeded()

        #expect(controller.currentSections() == [.input, .manualEntry])
        #expect(!controller.hasUnsavedDrafts)
        #expect(!controller.isModalInPresentation)
    }

    @Test
    func liveParsingExcludesDuplicatesAndPersistsOnlyNewParcels() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let existing = try env.store.add(
            [
                ParsedParcelDraft(pickupCode: "12-3-0000", channel: .duoduo, stationLabel: "North Pickup Point"),
            ],
            source: .pasted
        ).added

        var completionResult: AddParcelsResult?
        let controller = QuickAddViewController(
            dependencies: env.dependencies,
            existingParcels: existing
        ) { result in
            completionResult = result
        }
        controller.loadViewIfNeeded()

        let input = """
        【多多驿站】您的快递已到North Pickup Point，凭取件码12-3-0000领取。
        【菜鸟驿站】您的包裹已到达North Pickup Point，取件码5-1-2207。
        """
        controller.updateInputText(input)

        #expect(controller.currentSections() == [.input, .results])
        #expect(controller.classifiedDrafts.count == 2)
        #expect(controller.duplicateCount == 1)
        #expect(controller.addableDrafts.count == 1)
        #expect(controller.addableDrafts.first?.pickupCode == "5-1-2207")
        #expect(controller.hasUnsavedDrafts)
        #expect(controller.isModalInPresentation)

        let committed = try #require(controller.commitParsedDrafts())
        #expect(committed.added.count == 1)
        #expect(committed.added.first?.pickupCode == "5-1-2207")
        #expect(committed.added.first?.source == .pasted)
        #expect(completionResult == committed)

        let persisted = try env.store.load()
        #expect(persisted.count == 2)
    }

    @Test
    func unparsedInputShowsUnparsedStateAndManualEntryPersistsManualSource() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        var completionResult: AddParcelsResult?
        let controller = QuickAddViewController(
            dependencies: env.dependencies,
            existingParcels: []
        ) { result in
            completionResult = result
        }
        controller.loadViewIfNeeded()

        controller.updateInputText("Hello from family chat without any code")
        #expect(controller.currentSections() == [.input, .unparsed])
        #expect(!controller.hasUnsavedDrafts)

        let editor = EditParcelViewController(mode: .new) { draft in
            controller.commitManualDraft(draft)
        }
        editor.loadViewIfNeeded()

        #expect(!editor.isSaveEnabled)
        editor.selectChannel(.sfExpress)
        editor.updateField(.trackingNumber, value: "SF0000000000000")
        editor.updateField(.note, value: "Demo Item")
        #expect(editor.isSaveEnabled)

        editor.commitSave()

        let result = try #require(completionResult)
        #expect(result.added.count == 1)
        #expect(result.added.first?.trackingNumber == "SF0000000000000")
        #expect(result.added.first?.channel == .sfExpress)
        #expect(result.added.first?.source == .manual)

        let persisted = try env.store.load()
        #expect(persisted.count == 1)
    }

    @Test
    func editingParsedDraftUpdatesClassificationInPlace() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let existing = [
            Parcel(pickupCode: "12-3-0000", channel: .duoduo, stationLabel: "North Pickup Point"),
        ]
        let controller = QuickAddViewController(
            dependencies: env.dependencies,
            existingParcels: existing
        ) { _ in }
        controller.loadViewIfNeeded()

        controller.updateInputText("【多多驿站】取件码4-2-1048")
        guard var draft = controller.drafts.first else {
            Issue.record("Expected one parsed draft")
            return
        }
        #expect(controller.duplicateCount == 0)

        draft.pickupCode = "12-3-0000"
        controller.updateDraft(draft)

        #expect(controller.duplicateCount == 1)
        #expect(controller.addableDrafts.isEmpty)
        #expect(!controller.hasUnsavedDrafts)
    }

    @Test
    func pasteItemProvidersParsesPastedStringAsynchronously() async throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let controller = QuickAddViewController(
            dependencies: env.dependencies,
            existingParcels: []
        ) { _ in }
        controller.loadViewIfNeeded()

        let provider = NSItemProvider(object: "【菜鸟驿站】您的包裹已到North Pickup Point，取件码4-2-1048。" as NSString)
        controller.paste(itemProviders: [provider])

        let deadline = ContinuousClock.now + .seconds(2)
        while controller.drafts.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(controller.drafts.count == 1)
        #expect(controller.drafts.first?.channel == .cainiao)
        #expect(controller.drafts.first?.pickupCode == "4-2-1048")
    }

    @Test
    func duplicateManualEntryDoesNotCompleteOrPersistDuplicate() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let existing = try env.store.add(
            [ParsedParcelDraft(pickupCode: "12-3-0000", channel: .duoduo)],
            source: .pasted
        ).added

        var completionCalled = false
        let controller = QuickAddViewController(
            dependencies: env.dependencies,
            existingParcels: existing
        ) { _ in
            completionCalled = true
        }
        controller.loadViewIfNeeded()

        let duplicateDraft = ParsedParcelDraft(pickupCode: "12-3-0000", channel: .duoduo)
        let result = try #require(controller.commitManualDraft(duplicateDraft))
        #expect(result.added.isEmpty)
        #expect(result.updated.isEmpty)
        #expect(result.skippedDuplicateCount == 1)
        #expect(!completionCalled)
        #expect(try env.store.load().count == 1)
    }
}
