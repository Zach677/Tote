import AppIntents
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    let dependencies: AppDependencies

    override init() {
        let dependencies = AppDependencies.live()
        self.dependencies = dependencies
        super.init()
        AppDependencyManager.shared.add(dependency: dependencies.parcelStore)
    }
}
