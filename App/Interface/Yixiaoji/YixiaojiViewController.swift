import Foundation
import UIKit
import WebKit

final class YixiaojiViewController: UIViewController {
    let dependencies: AppDependencies
    let webView: WKWebView

    var handoffAutoDismissDuration: TimeInterval = 8.0
    var isVoiceOverRunningProvider: () -> Bool = { UIAccessibility.isVoiceOverRunning }

    private let progressView = UIProgressView(progressViewStyle: .bar)
    private var backButton: UIBarButtonItem!
    private var homeButton: UIBarButtonItem!
    private var reloadOrStopButton: UIBarButtonItem!

    private var observations: [NSKeyValueObservation] = []
    private var progressHideTask: Task<Void, Never>?
    private var handoffDismissTask: Task<Void, Never>?
    private var hasLoadedInitialPage = false

    private(set) var handoffBannerView: HandoffBannerView?

    var activeHandoffCode: String? {
        handoffBannerView?.code
    }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        progressHideTask?.cancel()
        handoffDismissTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureNavigationBar()
        configureWebView()
        configureProgressView()
        observeWebViewState()

        if dependencies.autoLoadYixiaoji, !hasLoadedInitialPage {
            hasLoadedInitialPage = true
            loadHomePage()
        }
    }

    func loadHomePage() {
        contentUnavailableConfiguration = nil
        webView.load(URLRequest(url: dependencies.yixiaojiURL))
    }

    func showHandoff(code: String) {
        guard !code.isEmpty else { return }

        if let existingBanner = handoffBannerView {
            existingBanner.update(code: code)
            announceHandoff(code: code)
            scheduleHandoffAutoDismiss()
            return
        }

        let banner = HandoffBannerView(code: code)
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.onTapCopy = { [weak self, weak banner] tappedCode in
            guard let self else { return }
            dependencies.clipboard.copy(tappedCode)
            if let banner {
                UINotificationFeedbackGenerator(view: banner).notificationOccurred(.success)
            }
            announceHandoff(code: tappedCode)
            scheduleHandoffAutoDismiss()
        }
        banner.onDismiss = { [weak self] in
            self?.dismissHandoff(animated: true)
        }

        view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            banner.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])

        handoffBannerView = banner
        banner.alpha = 0
        if !UIAccessibility.isReduceMotionEnabled {
            banner.transform = CGAffineTransform(translationX: 0, y: -8)
        }

        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut]
        ) {
            banner.alpha = 1
            banner.transform = .identity
        }

        announceHandoff(code: code)
        scheduleHandoffAutoDismiss()
    }

    func dismissHandoff(animated: Bool = true) {
        handoffDismissTask?.cancel()
        handoffDismissTask = nil

        guard let banner = handoffBannerView else { return }
        handoffBannerView = nil

        guard animated else {
            banner.removeFromSuperview()
            return
        }

        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseIn],
            animations: {
                banner.alpha = 0
                if !UIAccessibility.isReduceMotionEnabled {
                    banner.transform = CGAffineTransform(translationX: 0, y: -8)
                }
            },
            completion: { _ in
                banner.removeFromSuperview()
            }
        )
    }

    func handleNavigationFailure(_ error: any Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }

        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: "wifi.slash")
        config.text = String(localized: "Can’t Load Yixiaoji")
        config.secondaryText = String(localized: "Check your connection, then try again.")
        var buttonConfig = UIButton.Configuration.tinted()
        buttonConfig.cornerStyle = .capsule
        buttonConfig.title = String(localized: "Try Again")
        config.button = buttonConfig
        config.buttonProperties.primaryAction = UIAction { [weak self] _ in
            self?.retryLoad()
        }
        contentUnavailableConfiguration = config
    }
}

private extension YixiaojiViewController {
    func configureNavigationBar() {
        title = String(localized: "Yixiaoji")
        navigationItem.largeTitleDisplayMode = .never

        backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.backward"),
            style: .plain,
            target: self,
            action: #selector(handleBackTapped)
        )
        backButton.accessibilityLabel = String(localized: "Back")
        backButton.isEnabled = false
        navigationItem.leftBarButtonItem = backButton

        homeButton = UIBarButtonItem(
            image: UIImage(systemName: "house"),
            style: .plain,
            target: self,
            action: #selector(handleHomeTapped)
        )
        homeButton.accessibilityLabel = String(localized: "Home")

        reloadOrStopButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(handleReloadOrStopTapped)
        )
        reloadOrStopButton.accessibilityLabel = String(localized: "Reload")

        navigationItem.rightBarButtonItems = [reloadOrStopButton, homeButton]
    }

    func configureWebView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func configureProgressView() {
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.alpha = 0
        progressView.isHidden = true

        view.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func observeWebViewState() {
        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updateNavigationControls()
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updateNavigationControls()
                    self?.updateProgressDisplay()
                }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updateProgressDisplay()
                }
            },
        ]
    }

    func updateNavigationControls() {
        backButton.isEnabled = webView.canGoBack
        if webView.isLoading {
            reloadOrStopButton.image = UIImage(systemName: "xmark")
            reloadOrStopButton.accessibilityLabel = String(localized: "Stop Loading")
        } else {
            reloadOrStopButton.image = UIImage(systemName: "arrow.clockwise")
            reloadOrStopButton.accessibilityLabel = String(localized: "Reload")
        }
    }

    func updateProgressDisplay() {
        let progress = Float(webView.estimatedProgress)
        if webView.isLoading {
            progressHideTask?.cancel()
            progressHideTask = nil
            progressView.isHidden = false
            progressView.alpha = 1
            progressView.setProgress(max(0.05, progress), animated: true)
        } else if !progressView.isHidden {
            progressView.setProgress(1.0, animated: true)
            progressHideTask?.cancel()
            progressHideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, !self.webView.isLoading else { return }
                UIView.animate(
                    withDuration: 0.2,
                    animations: {
                        self.progressView.alpha = 0
                    },
                    completion: { [weak self] finished in
                        guard let self, finished, !self.webView.isLoading else { return }
                        progressView.isHidden = true
                        progressView.setProgress(0, animated: false)
                    }
                )
            }
        }
    }

    func scheduleHandoffAutoDismiss() {
        handoffDismissTask?.cancel()
        handoffDismissTask = nil

        guard !isVoiceOverRunningProvider() else { return }

        let delay = handoffAutoDismissDuration
        handoffDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.dismissHandoff(animated: true)
        }
    }

    func announceHandoff(code: String) {
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "Copied \(code)")
        )
    }

    func retryLoad() {
        contentUnavailableConfiguration = nil
        if webView.url != nil {
            webView.reload()
        } else {
            loadHomePage()
        }
    }

    @objc func handleBackTapped() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    @objc func handleHomeTapped() {
        loadHomePage()
    }

    @objc func handleReloadOrStopTapped() {
        if webView.isLoading {
            webView.stopLoading()
        } else {
            retryLoad()
        }
    }
}

extension YixiaojiViewController: WKNavigationDelegate {
    func webView(_: WKWebView, didCommit _: WKNavigation!) {
        contentUnavailableConfiguration = nil
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: any Error) {
        handleNavigationFailure(error)
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
        handleNavigationFailure(error)
    }
}
