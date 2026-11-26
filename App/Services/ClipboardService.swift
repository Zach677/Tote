import UIKit

protocol ClipboardManaging {
    func copy(_ text: String)
}

struct SystemClipboardService: ClipboardManaging {
    func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
