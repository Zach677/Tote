import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let dependencies = (UIApplication.shared.delegate as? AppDelegate)?.dependencies ?? .live()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = RootViewController(dependencies: dependencies)

        self.window = window
        window.makeKeyAndVisible()
    }
}
