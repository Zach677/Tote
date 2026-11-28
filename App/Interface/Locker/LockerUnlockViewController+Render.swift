import Core
import UIKit

extension LockerUnlockViewController {
    func render() {
        renderCabinetCard()
        renderStateAndButtons()
    }
}

private extension LockerUnlockViewController {
    func renderCabinetCard() {
        let isSignedIn = dependencies.yixiaoji.currentSession != nil

        if !isSignedIn {
            cabinetValueLabel.text = selectedCabinetName.isEmpty
                ? String(localized: "Not Signed In")
                : selectedCabinetName
            cabinetStatusLabel.text = String(localized: "Sign in to Yixiaoji to select a locker and open the door directly.")
            cabinetStatusLabel.textColor = .secondaryLabel
            cabinetStatusLabel.isHidden = false
            cabinetPickerButton.isHidden = true
            cabinetSpinner.stopAnimating()
            return
        }

        cabinetValueLabel.text = selectedCabinetName.isEmpty
            ? String(localized: "Choose Locker")
            : selectedCabinetName

        if isLoadingCabinets {
            cabinetSpinner.startAnimating()
        } else {
            cabinetSpinner.stopAnimating()
        }

        if didAutoMatchCabinet, !selectedCabinetMAC.isEmpty {
            cabinetStatusLabel.text = String(localized: "Matched to this parcel’s locker")
            cabinetStatusLabel.textColor = .systemGreen
            cabinetStatusLabel.isHidden = false
        } else if hasExplicitCabinetTarget {
            cabinetStatusLabel.text = String(localized: "Selected locker for opening")
            cabinetStatusLabel.textColor = .secondaryLabel
            cabinetStatusLabel.isHidden = false
        } else {
            cabinetStatusLabel.text = String(localized: "Choose the locker in front of you before opening.")
            cabinetStatusLabel.textColor = .secondaryLabel
            cabinetStatusLabel.isHidden = false
        }

        if !availableCabinets.isEmpty {
            var pickerConfig = UIButton.Configuration.tinted()
            pickerConfig.cornerStyle = .capsule
            pickerConfig.title = String(localized: "Change")
            pickerConfig.image = UIImage(systemName: "chevron.up.chevron.down")
            pickerConfig.imagePlacement = .trailing
            pickerConfig.imagePadding = 4
            pickerConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            cabinetPickerButton.configuration = pickerConfig
            cabinetPickerButton.menu = makeCabinetMenu()
            cabinetPickerButton.isHidden = false
        } else {
            cabinetPickerButton.isHidden = true
        }
    }

    func makeCabinetMenu() -> UIMenu {
        let actions = availableCabinets.map { cabinet in
            let isSelected = (!selectedSiteID.isEmpty && cabinet.id == selectedSiteID)
                || (!selectedCabinetName.isEmpty && cabinet.name == selectedCabinetName)
            return UIAction(
                title: cabinet.name,
                subtitle: cabinet.displayDetail.isEmpty ? nil : cabinet.displayDetail,
                state: isSelected ? .on : .off
            ) { [weak self] _ in
                self?.selectCabinet(cabinet)
            }
        }
        return UIMenu(title: String(localized: "Choose Locker"), options: .singleSelection, children: actions)
    }

    func renderStateAndButtons() {
        let isSignedIn = dependencies.yixiaoji.currentSession != nil
        let accentColor = UIColor(named: "AccentColor") ?? view.tintColor ?? .systemOrange

        switch unlockState {
        case .ready:
            resultCard.isHidden = true
            if !isSignedIn {
                applyFilledButton(
                    primaryButton,
                    title: String(localized: "Sign In to Yixiaoji"),
                    symbolName: "person.crop.circle",
                    backgroundColor: accentColor,
                    foregroundColor: ParcelTypography.accentForegroundColor,
                    isLoading: false,
                    isEnabled: true
                )
            } else if isLoadingCabinets {
                applyFilledButton(
                    primaryButton,
                    title: String(localized: "Loading Lockers…"),
                    symbolName: nil,
                    backgroundColor: accentColor,
                    foregroundColor: ParcelTypography.accentForegroundColor,
                    isLoading: true,
                    isEnabled: false
                )
            } else if !hasExplicitCabinetTarget {
                applyFilledButton(
                    primaryButton,
                    title: String(localized: "Choose a Locker First"),
                    symbolName: "cabinet",
                    backgroundColor: accentColor,
                    foregroundColor: ParcelTypography.accentForegroundColor,
                    isLoading: false,
                    isEnabled: false
                )
            } else {
                applyFilledButton(
                    primaryButton,
                    title: String(localized: "Open Locker"),
                    symbolName: "lock.open.fill",
                    backgroundColor: accentColor,
                    foregroundColor: ParcelTypography.accentForegroundColor,
                    isLoading: false,
                    isEnabled: true
                )
            }
            applyPlainSecondaryButton(title: String(localized: "Open Yixiaoji in Safari"), isEnabled: true)

        case .unlocking:
            resultCard.isHidden = true
            applyFilledButton(
                primaryButton,
                title: String(localized: "Opening Locker…"),
                symbolName: nil,
                backgroundColor: accentColor,
                foregroundColor: ParcelTypography.accentForegroundColor,
                isLoading: true,
                isEnabled: false
            )
            applyPlainSecondaryButton(title: String(localized: "Open Yixiaoji in Safari"), isEnabled: true)

        case let .opened(compartment, message):
            resultCard.isHidden = false
            resultCard.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.14)
            resultTitleLabel.text = compartment.isEmpty
                ? String(localized: "Locker Opened")
                : String(localized: "Compartment")
            resultTitleLabel.textColor = .systemGreen
            resultBigValueLabel.isHidden = compartment.isEmpty
            resultBigValueLabel.text = compartment
            resultBigValueLabel.textColor = .systemGreen
            resultMessageLabel.text = message.isEmpty
                ? String(localized: "Collect your parcel and close the door.")
                : message
            resultMessageLabel.textColor = .label

            applyFilledButton(
                primaryButton,
                title: String(localized: "Mark as Picked Up"),
                symbolName: "checkmark.circle.fill",
                backgroundColor: .systemGreen,
                foregroundColor: .white,
                isLoading: false,
                isEnabled: true
            )
            applyPlainSecondaryButton(title: String(localized: "Open Again"), isEnabled: canUnlock)

        case let .unconfirmed(message):
            resultCard.isHidden = false
            resultCard.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.16)
            resultTitleLabel.text = String(localized: "Door May Already Be Open")
            resultTitleLabel.textColor = .systemOrange
            resultBigValueLabel.isHidden = true
            let guidance = String(localized: "Check the locker in front of you before opening again.")
            resultMessageLabel.text = message.isEmpty ? guidance : "\(message)\n\(guidance)"
            resultMessageLabel.textColor = .label

            applyFilledButton(
                primaryButton,
                title: String(localized: "Mark as Picked Up"),
                symbolName: "checkmark.circle.fill",
                backgroundColor: .systemGreen,
                foregroundColor: .white,
                isLoading: false,
                isEnabled: true
            )
            applyPlainSecondaryButton(title: String(localized: "Open Again"), isEnabled: canUnlock)

        case let .paymentRequired(message, amount, overdueDays):
            resultCard.isHidden = false
            resultCard.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.16)
            resultTitleLabel.text = String(localized: "Overdue Fee Required")
            resultTitleLabel.textColor = .systemOrange
            resultBigValueLabel.isHidden = amount.isEmpty
            resultBigValueLabel.text = amount.isEmpty ? "" : "¥\(amount)"
            resultBigValueLabel.textColor = .systemOrange

            var detailParts: [String] = []
            if !message.isEmpty {
                detailParts.append(message)
            } else if !overdueDays.isEmpty {
                detailParts.append(String(localized: "Overdue by \(overdueDays) days."))
            }
            detailParts.append(String(localized: "Complete payment in Yixiaoji on WeChat, then open again."))
            resultMessageLabel.text = detailParts.joined(separator: "\n")
            resultMessageLabel.textColor = .label

            applyFilledButton(
                primaryButton,
                title: String(localized: "Copy Pickup Code"),
                symbolName: "doc.on.doc",
                backgroundColor: accentColor,
                foregroundColor: ParcelTypography.accentForegroundColor,
                isLoading: false,
                isEnabled: true
            )
            applyPlainSecondaryButton(title: String(localized: "Open Yixiaoji in Safari"), isEnabled: true)

        case let .failed(message, isSessionExpired):
            resultCard.isHidden = false
            resultCard.backgroundColor = UIColor.systemRed.withAlphaComponent(0.14)
            resultTitleLabel.text = isSessionExpired
                ? String(localized: "Session Expired")
                : String(localized: "Couldn’t Open Locker")
            resultTitleLabel.textColor = .systemRed
            resultBigValueLabel.isHidden = true
            resultMessageLabel.text = message
            resultMessageLabel.textColor = .label

            applyFilledButton(
                primaryButton,
                title: isSessionExpired
                    ? String(localized: "Sign In Again")
                    : String(localized: "Try Again"),
                symbolName: isSessionExpired ? "person.crop.circle" : "arrow.clockwise",
                backgroundColor: accentColor,
                foregroundColor: ParcelTypography.accentForegroundColor,
                isLoading: false,
                isEnabled: isSessionExpired || canUnlock
            )
            applyPlainSecondaryButton(title: String(localized: "Open Yixiaoji in Safari"), isEnabled: true)
        }
    }

    func applyFilledButton(
        _ button: UIButton,
        title: String,
        symbolName: String?,
        backgroundColor: UIColor,
        foregroundColor: UIColor,
        isLoading: Bool,
        isEnabled: Bool
    ) {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = backgroundColor
        config.baseForegroundColor = foregroundColor
        config.cornerStyle = .large
        config.title = title
        config.showsActivityIndicator = isLoading
        config.imagePadding = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        if let symbolName, !isLoading {
            config.image = UIImage(systemName: symbolName)
        }
        button.configuration = config
        button.isEnabled = isEnabled && !isLoading
    }

    func applyPlainSecondaryButton(title: String, isEnabled: Bool) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        secondaryButton.configuration = config
        secondaryButton.isEnabled = isEnabled
    }
}
