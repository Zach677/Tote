import Foundation
import UIKit

protocol ExternalLaunching {
    func open(_ url: URL, completion: @escaping @MainActor (Bool) -> Void)
}

struct SystemExternalLauncher: ExternalLaunching {
    func open(_ url: URL, completion: @escaping @MainActor (Bool) -> Void) {
        UIApplication.shared.open(url, options: [:]) { success in
            completion(success)
        }
    }
}
