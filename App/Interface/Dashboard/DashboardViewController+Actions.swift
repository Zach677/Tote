import Core
import Foundation
import UIKit

extension DashboardViewController {
    @objc func handleSegmentChanged() {
        let segment = Segment(rawValue: segmentedControl.selectedSegmentIndex) ?? .pending
        selectSegment(segment)
    }

    func selectSegment(_ segment: Segment) {
        selectedSegment = segment
        segmentedControl.selectedSegmentIndex = segment.rawValue
        applySnapshot(animatingDifferences: false)
        collectionView.setContentOffset(
            CGPoint(x: 0, y: -collectionView.adjustedContentInset.top),
            animated: false
        )
    }

    @objc func handleSettingsTapped() {
        presentSettings()
    }

    @objc func handleAddTapped() {
        presentQuickAdd()
    }

    @objc func handlePullToRefresh() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            await self?.syncYixiaojiIfSignedIn()
        }
    }

    @discardableResult
    func syncYixiaojiIfSignedIn() async -> AddParcelsResult? {
        defer {
            if refreshControl.isRefreshing {
                refreshControl.endRefreshing()
            }
        }

        guard dependencies.yixiaoji.currentSession != nil else {
            reloadParcels(animatingDifferences: false)
            return nil
        }

        do {
            let remote = try await dependencies.yixiaoji.fetchPendingParcels()
            let result = try dependencies.parcelStore.syncSyncedParcels(remote.map { $0.makeDraft() })
            reloadParcels(animatingDifferences: true)
            return result
        } catch let apiError as YixiaojiAPIError {
            presentYixiaojiSyncErrorAlert(apiError)
            return nil
        } catch {
            presentStoreErrorAlert(title: String(localized: "Couldn’t Sync Yixiaoji"))
            return nil
        }
    }

    func presentSettings() {
        let settingsController = SettingsViewController(dependencies: dependencies)
        settingsController.onParcelsChanged = { [weak self] in
            self?.reloadParcels(animatingDifferences: true)
        }
        let navigationController = UINavigationController(rootViewController: settingsController)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigationController, animated: true)
    }

    func presentLockerUnlock(for parcel: Parcel) {
        lastPresentedLockerParcel = parcel
        if let onOpenLocker {
            onOpenLocker(parcel)
            return
        }

        let unlockController = LockerUnlockViewController(parcel: parcel, dependencies: dependencies)
        unlockController.onParcelUpdated = { [weak self] _ in
            self?.reloadParcels(animatingDifferences: false)
        }
        unlockController.onMarkPickedUp = { [weak self] parcelID in
            self?.markParcelPickedUp(id: parcelID)
        }

        let navigationController = UINavigationController(rootViewController: unlockController)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        guard presentedViewController == nil, viewIfLoaded?.window != nil else { return }
        present(navigationController, animated: true)
    }

    func presentQuickAdd() {
        let quickAddController = QuickAddViewController(
            dependencies: dependencies,
            existingParcels: parcels
        ) { [weak self] result in
            self?.handleQuickAddCompletion(result)
        }
        let navigationController = UINavigationController(rootViewController: quickAddController)
        navigationController.presentationController?.delegate = quickAddController
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigationController, animated: true)
    }

    func handleQuickAddCompletion(_ result: AddParcelsResult) {
        if selectedSegment != .pending {
            selectedSegment = .pending
            segmentedControl.selectedSegmentIndex = Segment.pending.rawValue
        }
        reloadParcels(animatingDifferences: true, scrollToParcelID: result.firstAffectedID)
    }

    func handleSelection(of item: DashboardItem, sourceView: UIView) {
        switch item {
        case .duoduoAction:
            openDuoduoLink()
        case let .parcel(parcelID):
            guard let parcel = parcelsByID[parcelID] else { return }
            handleParcelTap(parcel, sourceView: sourceView)
        case .empty:
            break
        }
    }

    func openDuoduoLink() {
        guard let url = DuoduoLinkValidator.validatedURL(from: dependencies.settings.duoduoURLString) else {
            presentDuoduoOpenFailureAlert()
            return
        }

        dependencies.launcher.open(url) { [weak self] success in
            guard let self, !success else { return }
            presentDuoduoOpenFailureAlert()
        }
    }

    func makeTrailingSwipeActions(
        for indexPath: IndexPath,
        isPickedUp: Bool
    ) -> UISwipeActionsConfiguration? {
        guard case let .parcel(parcelID) = dataSource.itemIdentifier(for: indexPath) else {
            return nil
        }

        let primaryAction: UIContextualAction
        if isPickedUp {
            primaryAction = UIContextualAction(
                style: .normal,
                title: String(localized: "Restore")
            ) { [weak self] _, _, completion in
                guard let self else {
                    completion(false)
                    return
                }
                completion(restoreParcel(id: parcelID))
            }
            primaryAction.backgroundColor = UIColor(named: "AccentColor") ?? view.tintColor
            primaryAction.image = UIImage(systemName: "arrow.uturn.backward")
        } else {
            primaryAction = UIContextualAction(
                style: .normal,
                title: String(localized: "Picked Up")
            ) { [weak self] _, _, completion in
                guard let self else {
                    completion(false)
                    return
                }
                completion(markParcelPickedUp(id: parcelID))
            }
            primaryAction.backgroundColor = .systemGreen
            primaryAction.image = UIImage(systemName: "checkmark")
        }

        let deleteAction = UIContextualAction(
            style: .destructive,
            title: String(localized: "Delete")
        ) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            completion(deleteParcel(id: parcelID))
        }
        deleteAction.image = UIImage(systemName: "trash")

        // Keep the non-destructive action first so full swipe never triggers Delete.
        let configuration = UISwipeActionsConfiguration(actions: [primaryAction, deleteAction])
        configuration.performsFirstActionWithFullSwipe = true
        return configuration
    }

    @discardableResult
    func markParcelPickedUp(id: Parcel.ID) -> Bool {
        do {
            let updated = try dependencies.parcelStore.markPickedUp(id: id)
            applyLoadedParcels(updated, animatingDifferences: true)
            return true
        } catch {
            presentStoreErrorAlert(title: String(localized: "Couldn’t Save Parcels"))
            return false
        }
    }

    @discardableResult
    func restoreParcel(id: Parcel.ID) -> Bool {
        do {
            let updated = try dependencies.parcelStore.restoreToPending(id: id)
            applyLoadedParcels(updated, animatingDifferences: true)
            return true
        } catch {
            presentStoreErrorAlert(title: String(localized: "Couldn’t Save Parcels"))
            return false
        }
    }

    @discardableResult
    func deleteParcel(id: Parcel.ID) -> Bool {
        do {
            let updated = try dependencies.parcelStore.delete(id: id)
            applyLoadedParcels(updated, animatingDifferences: true)
            return true
        } catch {
            presentStoreErrorAlert(title: String(localized: "Couldn’t Save Parcels"))
            return false
        }
    }

    func presentStoreErrorAlert(title: String) {
        let alert = UIAlertController(
            title: title,
            message: String(localized: "Please try again."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        presentAlertIfPossible(alert)
    }
}

private extension DashboardViewController {
    func handleParcelTap(_ parcel: Parcel, sourceView: UIView) {
        if parcel.isPickedUp {
            let value = parcel.hasPickupCode ? parcel.pickupCode : parcel.trackingNumber
            copyWithFeedback(value, sourceView: sourceView, showToast: true)
            return
        }

        if parcel.isTrackingOnly {
            copyWithFeedback(parcel.trackingNumber, sourceView: sourceView, showToast: false)
            openDuoduoLink()
            return
        }

        if parcel.channel == .locker {
            presentLockerUnlock(for: parcel)
            return
        }

        copyWithFeedback(parcel.pickupCode, sourceView: sourceView, showToast: true)
    }

    func copyWithFeedback(
        _ value: String,
        sourceView: UIView,
        showToast: Bool,
        announce: Bool = true
    ) {
        guard !value.isEmpty else { return }
        dependencies.clipboard.copy(value)
        UINotificationFeedbackGenerator(view: sourceView).notificationOccurred(.success)
        if announce {
            UIAccessibility.post(
                notification: .announcement,
                argument: String(localized: "Copied \(value)")
            )
        }
        if showToast {
            copyToastView.show(copiedValue: value)
        }
    }

    func presentDuoduoOpenFailureAlert() {
        let alert = UIAlertController(
            title: String(localized: "Can’t Open Duoduo"),
            message: String(localized: "Check that Pinduoduo is installed, or change the link in Settings."),
            preferredStyle: .alert
        )
        let settingsAction = UIAlertAction(title: String(localized: "Settings"), style: .default) { [weak self] _ in
            self?.presentSettings()
        }
        let okAction = UIAlertAction(title: String(localized: "OK"), style: .default)
        alert.addAction(settingsAction)
        alert.addAction(okAction)
        alert.preferredAction = okAction
        presentAlertIfPossible(alert)
    }

    func presentYixiaojiSyncErrorAlert(_ error: YixiaojiAPIError) {
        let title: String
        let message: String
        let showSettings: Bool

        switch error {
        case .sessionExpired, .notSignedIn:
            title = String(localized: "Session Expired")
            message = String(localized: "Your Yixiaoji session expired. Please sign in again in Settings.")
            showSettings = true
        case let .serverError(serverMessage), let .invalidCredentials(serverMessage):
            title = String(localized: "Couldn’t Sync Yixiaoji")
            message = serverMessage.isEmpty ? String(localized: "Please try again.") : serverMessage
            showSettings = false
        case .invalidResponse, .networkError:
            title = String(localized: "Couldn’t Sync Yixiaoji")
            message = String(localized: "Check your connection, then try again.")
            showSettings = false
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if showSettings {
            alert.addAction(
                UIAlertAction(title: String(localized: "Settings"), style: .default) { [weak self] _ in
                    self?.presentSettings()
                }
            )
        }
        let okAction = UIAlertAction(title: String(localized: "OK"), style: .default)
        alert.addAction(okAction)
        alert.preferredAction = okAction
        presentAlertIfPossible(alert)
    }

    func presentAlertIfPossible(_ alert: UIAlertController) {
        guard presentedViewController == nil, viewIfLoaded?.window != nil else { return }
        present(alert, animated: true)
    }
}
