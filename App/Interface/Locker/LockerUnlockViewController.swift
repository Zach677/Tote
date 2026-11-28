import Core
import UIKit

final class LockerUnlockViewController: UIViewController {
    enum UnlockState: Equatable {
        case ready
        case unlocking
        case opened(compartment: String, message: String)
        case unconfirmed(message: String)
        case paymentRequired(message: String, amount: String, overdueDays: String)
        case failed(message: String, isSessionExpired: Bool)
    }

    let dependencies: AppDependencies
    private(set) var parcel: Parcel
    var onParcelUpdated: (Parcel) -> Void = { _ in }
    var onMarkPickedUp: (Parcel.ID) -> Void = { _ in }

    private(set) var unlockState: UnlockState = .ready
    private(set) var selectedCabinetName: String
    private(set) var selectedCabinetMAC: String
    private(set) var selectedSiteID: String
    private(set) var availableCabinets: [YixiaojiCabinet] = []
    private(set) var isLoadingCabinets = false
    private(set) var didAutoMatchCabinet = false
    private(set) var isUsingLastSelectedCabinet = false
    private var userSelectedCabinetManually = false
    private var lookupGeneration = 0

    let scrollView = UIScrollView()
    let contentStack = UIStackView()

    let codeCard = UIView()
    let codeEyebrowLabel = UILabel()
    let codeLabel = UILabel()
    let copyButton = UIButton(type: .system)

    let cabinetCard = UIView()
    let cabinetTitleLabel = UILabel()
    let cabinetValueLabel = UILabel()
    let cabinetStatusLabel = UILabel()
    let cabinetPickerButton = UIButton(type: .system)
    let cabinetSpinner = UIActivityIndicatorView(style: .medium)

    let resultCard = UIView()
    let resultTitleLabel = UILabel()
    let resultBigValueLabel = UILabel()
    let resultMessageLabel = UILabel()

    let primaryButton = UIButton(type: .system)
    let secondaryButton = UIButton(type: .system)

    private var lookupTask: Task<Void, Never>?
    private var unlockTask: Task<Void, Never>?
    private var copyResetTask: Task<Void, Never>?

    var hasExplicitCabinetTarget: Bool {
        !selectedCabinetMAC.isEmpty || !selectedSiteID.isEmpty
    }

    var canUnlock: Bool {
        dependencies.yixiaoji.currentSession != nil
            && !isLoadingCabinets
            && hasExplicitCabinetTarget
    }

    init(parcel: Parcel, dependencies: AppDependencies) {
        self.parcel = parcel
        self.dependencies = dependencies
        selectedCabinetName = parcel.stationLabel
        selectedCabinetMAC = parcel.lockerMAC
        selectedSiteID = parcel.lockerSiteID
        didAutoMatchCabinet = !parcel.lockerMAC.isEmpty
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        lookupTask?.cancel()
        unlockTask?.cancel()
        copyResetTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        configureNavigationBar()
        configureLayout()
        render()

        if dependencies.yixiaoji.currentSession != nil {
            lookupTask = Task { [weak self] in
                await self?.performInitialLookup()
            }
        }
    }

    func performInitialLookup() async {
        guard dependencies.yixiaoji.currentSession != nil else { return }

        lookupGeneration += 1
        let generation = lookupGeneration
        isLoadingCabinets = true
        render()

        defer {
            if lookupGeneration == generation {
                isLoadingCabinets = false
                render()
            }
        }

        // If this parcel has no exact cabinet binding yet (e.g. pasted manually),
        // check Yixiaoji keyword search first, then fall back to pending parcels list.
        // Never overwrite a manual selection made while awaiting network responses.
        if !userSelectedCabinetManually, selectedCabinetMAC.isEmpty, parcel.hasPickupCode {
            let searchMatches = await (try? dependencies.yixiaoji.searchParcels(keyword: parcel.pickupCode)) ?? []
            guard !Task.isCancelled, lookupGeneration == generation else { return }

            if !userSelectedCabinetManually, selectedCabinetMAC.isEmpty,
               let bestMatch = findBestRemoteMatch(in: searchMatches)
            {
                applyMatchedRemoteParcel(bestMatch)
            } else if !userSelectedCabinetManually, selectedCabinetMAC.isEmpty,
                      let pendingBatch = try? await dependencies.yixiaoji.fetchPendingParcels(),
                      !Task.isCancelled, lookupGeneration == generation,
                      !userSelectedCabinetManually, selectedCabinetMAC.isEmpty,
                      let bestMatch = findBestRemoteMatch(in: pendingBatch.parcels)
            {
                applyMatchedRemoteParcel(bestMatch)
            }
        }

        if let cabinets = try? await dependencies.yixiaoji.fetchCabinets(keyword: "") {
            guard !Task.isCancelled, lookupGeneration == generation else { return }
            availableCabinets = cabinets
            if selectedCabinetName.isEmpty, !selectedSiteID.isEmpty,
               let matched = cabinets.first(where: { $0.id == selectedSiteID })
            {
                selectedCabinetName = matched.name
            }
            if !userSelectedCabinetManually, selectedCabinetMAC.isEmpty, selectedSiteID.isEmpty {
                if let last = dependencies.yixiaoji.lastSelectedCabinet {
                    selectedCabinetName = last.name
                    selectedCabinetMAC = last.mac
                    selectedSiteID = last.id
                    isUsingLastSelectedCabinet = true
                }
            }
        }
    }

    func selectCabinet(_ cabinet: YixiaojiCabinet) {
        userSelectedCabinetManually = true
        isUsingLastSelectedCabinet = false
        selectedCabinetName = cabinet.name
        selectedCabinetMAC = cabinet.mac
        selectedSiteID = cabinet.id
        didAutoMatchCabinet = false
        dependencies.yixiaoji.lastSelectedCabinet = cabinet

        var updated = parcel
        updated.stationLabel = cabinet.name
        updated.lockerMAC = cabinet.mac
        updated.lockerSiteID = cabinet.id
        persistUpdatedParcel(updated)

        if case .failed = unlockState {
            unlockState = .ready
        }
        render()
    }

    func performUnlock() async {
        guard dependencies.yixiaoji.currentSession != nil else {
            pushLogin()
            return
        }
        guard canUnlock, unlockState != .unlocking else { return }

        unlockState = .unlocking
        render()

        do {
            let result = try await dependencies.yixiaoji.unlockParcel(
                code: parcel.pickupCode,
                cabinetMAC: selectedCabinetMAC.isEmpty ? nil : selectedCabinetMAC,
                siteID: selectedSiteID.isEmpty ? nil : selectedSiteID
            )
            switch result {
            case let .opened(compartment, message, _):
                unlockState = .opened(compartment: compartment, message: message)
                UINotificationFeedbackGenerator(view: view).notificationOccurred(.success)
            case let .paymentRequired(message, amount, overdueDays):
                unlockState = .paymentRequired(message: message, amount: amount, overdueDays: overdueDays)
                UINotificationFeedbackGenerator(view: view).notificationOccurred(.warning)
            }
        } catch is CancellationError {
            unlockState = .unconfirmed(message: "")
        } catch let apiError as YixiaojiAPIError {
            switch apiError {
            case .notSignedIn:
                unlockState = .failed(
                    message: String(localized: "Sign in to Yixiaoji to open lockers."),
                    isSessionExpired: true
                )
            case .missingCabinetSelection:
                unlockState = .ready
            case let .sessionExpired(message):
                let text = message.isEmpty ? String(localized: "Your Yixiaoji session expired. Please sign in again.") : message
                unlockState = .failed(message: text, isSessionExpired: true)
            case let .unlockUnconfirmed(message, _):
                unlockState = .unconfirmed(message: message)
                UINotificationFeedbackGenerator(view: view).notificationOccurred(.warning)
            case let .serverError(message), let .invalidCredentials(message), let .storageError(message):
                let text = message.isEmpty ? String(localized: "Couldn’t open the locker. Check the selected locker and try again.") : message
                unlockState = .failed(message: text, isSessionExpired: false)
            case .invalidResponse, .networkError:
                unlockState = .failed(
                    message: String(localized: "Couldn’t reach Yixiaoji. Check your connection and try again."),
                    isSessionExpired: false
                )
            }
            if case .failed = unlockState {
                UINotificationFeedbackGenerator(view: view).notificationOccurred(.error)
            }
        } catch {
            unlockState = .failed(
                message: String(localized: "Couldn’t reach Yixiaoji. Check your connection and try again."),
                isSessionExpired: false
            )
            UINotificationFeedbackGenerator(view: view).notificationOccurred(.error)
        }

        render()
    }

    func copyCode() {
        guard parcel.hasPickupCode else { return }
        dependencies.clipboard.copy(parcel.pickupCode)
        UINotificationFeedbackGenerator(view: copyButton).notificationOccurred(.success)
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "Copied \(parcel.pickupCode)")
        )

        var config = copyButton.configuration ?? .tinted()
        config.title = String(localized: "Copied")
        config.image = UIImage(systemName: "checkmark")
        copyButton.configuration = config

        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            configureCopyButtonDefault()
        }
    }

    func openInSafari() {
        dependencies.launcher.open(AppDependencies.yixiaojiWebFallbackURL) { _ in }
    }

    func markAsPickedUp() {
        onMarkPickedUp(parcel.id)
        dismiss(animated: true)
    }

    func pushLogin() {
        let existingUsername = dependencies.yixiaoji.currentSession?.username ?? ""
        let loginController = YixiaojiLoginViewController(
            dependencies: dependencies,
            initialUsername: existingUsername
        ) { [weak self] _ in
            guard let self else { return }
            unlockState = .ready
            navigationController?.popViewController(animated: true)
            render()
            lookupTask?.cancel()
            lookupTask = Task { [weak self] in
                await self?.performInitialLookup()
            }
        }
        navigationController?.pushViewController(loginController, animated: true)
    }

    func handlePrimaryActionTapped() {
        switch unlockState {
        case .ready:
            if dependencies.yixiaoji.currentSession == nil {
                pushLogin()
            } else if canUnlock {
                startUnlockTask()
            }
        case .unlocking:
            break
        case .opened, .unconfirmed:
            markAsPickedUp()
        case .paymentRequired:
            copyCode()
        case let .failed(_, isSessionExpired):
            if isSessionExpired {
                pushLogin()
            } else if canUnlock {
                startUnlockTask()
            }
        }
    }

    func handleSecondaryActionTapped() {
        switch unlockState {
        case .opened, .unconfirmed:
            if canUnlock {
                startUnlockTask()
            }
        case .ready, .unlocking, .paymentRequired, .failed:
            openInSafari()
        }
    }
}

private extension LockerUnlockViewController {
    func startUnlockTask() {
        unlockTask?.cancel()
        unlockTask = Task { [weak self] in
            await self?.performUnlock()
        }
    }

    func findBestRemoteMatch(in candidates: [YixiaojiRemoteParcel]) -> YixiaojiRemoteParcel? {
        let normalizedTarget = parcel.normalizedPickupCode
        let targetIsPureDigits = Self.isASCIIPureDigits(normalizedTarget)
        let strippedTarget = String(normalizedTarget.drop(while: { $0 == "0" }))

        let match = candidates.first { candidate in
            let code = candidate.makeDraft().normalizedPickupCode
            if code == normalizedTarget {
                return true
            }
            // Only tolerate leading-zero stripping when both codes are pure ASCII digits
            // (JSON integer coercion) and one is a leading-zero prefix of the other.
            guard targetIsPureDigits,
                  Self.isASCIIPureDigits(code),
                  !strippedTarget.isEmpty,
                  code.count != normalizedTarget.count
            else {
                return false
            }
            let strippedCode = String(code.drop(while: { $0 == "0" }))
            return strippedCode == strippedTarget
        }

        guard let match,
              !match.cabinetMAC.isEmpty || !match.siteID.isEmpty || !match.cabinetName.isEmpty
        else {
            return nil
        }
        return match
    }

    static func isASCIIPureDigits(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
    }

    func applyMatchedRemoteParcel(_ remote: YixiaojiRemoteParcel) {
        isUsingLastSelectedCabinet = false
        if !remote.cabinetName.isEmpty {
            selectedCabinetName = remote.cabinetName
        }
        if !remote.cabinetMAC.isEmpty {
            selectedCabinetMAC = remote.cabinetMAC
            didAutoMatchCabinet = true
        }
        if !remote.siteID.isEmpty {
            selectedSiteID = remote.siteID
        }

        var updated = parcel
        if !remote.cabinetName.isEmpty {
            updated.stationLabel = remote.cabinetName
        }
        if !remote.cabinetMAC.isEmpty {
            updated.lockerMAC = remote.cabinetMAC
        }
        if !remote.siteID.isEmpty {
            updated.lockerSiteID = remote.siteID
        }
        if updated.trackingNumber.isEmpty, !remote.trackingNumber.isEmpty {
            updated.trackingNumber = remote.trackingNumber
        }
        persistUpdatedParcel(updated)
    }

    func persistUpdatedParcel(_ updated: Parcel) {
        parcel = updated
        if (try? dependencies.parcelStore.update(updated)) != nil {
            onParcelUpdated(updated)
        }
    }
}
