import SwiftUI
import WebKit
import SafariServices
import AVFoundation

@MainActor
private final class WeakBridge: NSObject, WKScriptMessageHandler {
    weak var session: WebSession?
    init(_ session: WebSession) { self.session = session }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        session?.receive(message)
    }
}

/// One live tab. WKWebsiteDataStore.default preserves the OS cookie/login session.
@MainActor
final class WebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    @Published var currentURL = ""
    @Published var loading = true
    @Published var ready = false
    @Published var error: String?
    @Published var progress = 0.0
    @Published var canGoBack = false
    var interactive = true { didSet { if !interactive { location.stop() } } }
    private let location = NativeLocation()
    var config: AppConfig { didSet { if !config.features.enableLocation { location.stop(message: "Location is disabled for this app.", code: 1) } } }
    let policy: NavigationPolicy
    private(set) var webView: WKWebView!
    var onNativeNavigate: ((String) -> Void)?
    var onReady: (() -> Void)?
    private var observations: [NSKeyValueObservation] = []
    private var deadline: DispatchWorkItem?
    private var documentReady = false
    private var navigationFinished = false
    private var innerAtTop = true
    private(set) var scrollPosition: [String: Int] = [:]
    private var restoreScroll: [String: Int]?
    private var downloads: [ObjectIdentifier: URL] = [:]

    init(config: AppConfig, url: URL, interactionState: Any? = nil, scroll: [String: Int]? = nil) {
        self.config = config
        policy = NavigationPolicy(config.targetUrl)
        super.init()
        let settings = WKWebViewConfiguration()
        settings.websiteDataStore = .default()
        settings.allowsInlineMediaPlayback = true
        settings.mediaTypesRequiringUserActionForPlayback = .all
        if let suffix = config.userAgentSuffix { settings.applicationNameForUserAgent = String(suffix.prefix(128)) }
        settings.userContentController.add(WeakBridge(self), name: "AppifyWeb")
        if let scriptURL = Bundle.main.url(forResource: "appifyweb-bridge", withExtension: "js"),
           let bridge = try? String(contentsOf: scriptURL), let base = policy.base,
           let components = URLComponents(url: base, resolvingAgainstBaseURL: false) {
            var originComponents = components
            originComponents.path = ""; originComponents.query = nil; originComponents.fragment = nil
            originComponents.host = originComponents.host?.lowercased()
            if originComponents.port == 443 { originComponents.port = nil }
            let origin = originComponents.string ?? ""
            let quoted = Self.json(origin)
            let shim = """
            (function(){
              if(window.top!==window || location.origin!==\(quoted)) return;
              window.AppifyNative={postMessage:function(value){window.webkit.messageHandlers.AppifyWeb.postMessage(value);}};
              window.__appifyAppMode=\(config.appModeEnabled);
              window.__appifyVersion=\(Self.json(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"));
              window.__appifyHasIdentity=\(PushNotificationService.shared.hasIdentity);
              \(bridge)
            })();
            """
            settings.userContentController.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if let url = Bundle.main.url(forResource: "location-bridge", withExtension: "js"), let source = try? String(contentsOf: url) {
            settings.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        location.reply = { [weak self] id, result in
            guard let self, let url = self.webView?.url, self.policy.isInternal(url),
                  let data = try? JSONSerialization.data(withJSONObject: result), let json = String(data: data, encoding: .utf8) else { return }
            self.webView.evaluateJavaScript("if(window.__appifyLocationReply)window.__appifyLocationReply(\(id),\(json))", completionHandler: nil)
        }
        webView = WKWebView(frame: .zero, configuration: settings)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(config.uiSecondaryColor)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshPage), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.progress = view.estimatedProgress }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.canGoBack = view.canGoBack }
            }
        ]
        if let interactionState { webView.interactionState = interactionState }
        restoreScroll = scroll
        currentURL = url.absoluteString
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15))
    }
    static func json(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(text.dropFirst().dropLast())
    }
    @objc private func refreshPage() {
        if innerAtTop { reload() } else { webView.scrollView.refreshControl?.endRefreshing() }
    }
    func reload() {
        error = nil
        if webView.url == nil, let url = policy.resolve(currentURL) { webView.load(URLRequest(url: url)) }
        else { webView.reload() }
    }
    func navigate(_ path: String) {
        guard let url = policy.resolve(path) else { return }
        error = nil
        // Native tab switches remain separate; same-tab routes may be handled by the website router.
        let script = "(function(){var e=new CustomEvent('appify:beforeNavigate',{cancelable:true,detail:{path:\(Self.json(url.absoluteString))}});return !window.dispatchEvent(e);})()"
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }
            if result as? Bool != true { self.webView.load(URLRequest(url: url)) }
        }
    }
    func scrollToTop() {
        webView.evaluateJavaScript("window.dispatchEvent(new Event('appify:scrollToTop'))", completionHandler: nil)
        webView.scrollView.setContentOffset(.zero, animated: true)
    }
    func dispose() {
        deadline?.cancel()
        location.stop()
        observations.removeAll()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "AppifyWeb")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }
    deinit { deadline?.cancel() }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        location.stop()
        loading = true; error = nil; progress = 0
        documentReady = false; navigationFinished = false
        deadline?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.fail("This is taking longer than expected. Please try again.") }
        deadline = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: task)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, policy.isInternal(url) else { return }
        currentURL = url.absoluteString
        navigationFinished = true
        finishReady()
        webView.scrollView.refreshControl?.endRefreshing()
    }
    private func finishReady() {
        guard documentReady && navigationFinished else { return }
        deadline?.cancel()
        ready = true; loading = false; error = nil
        if let scroll = restoreScroll {
            restoreScroll = nil
            let x = max(0, scroll["x"] ?? 0), y = max(0, scroll["y"] ?? 0)
            webView.evaluateJavaScript("(function(){var r=document.querySelector('[data-app-scroll-root]')||document.scrollingElement;if(r)r.scrollTo(\(x),\(y));})()", completionHandler: nil)
        }
        onReady?()
    }
    private func fail(_ message: String) {
        deadline?.cancel(); loading = false; error = message
        webView.scrollView.refreshControl?.endRefreshing()
    }
    private func navigationFailed(_ failure: Error) {
        let ns = failure as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        fail("This page could not be loaded. Check your connection and try again.")
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail("The app content was closed by iOS. Tap Retry to restore it.")
    }
    // TLS challenges use system trust validation; no certificate exceptions.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame == false {
            decisionHandler(["https", "about"].contains(url.scheme ?? "") ? .allow : .cancel)
        } else if policy.isInternal(url) {
            if action.targetFrame == nil { decisionHandler(.cancel); navigate(url.absoluteString) }
            else { decisionHandler(action.shouldPerformDownload ? .download : .allow) }
        } else {
            decisionHandler(.cancel)
            if NavigationPolicy.externalAllowed(url) { NativePresentation.open(url) }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
            decisionHandler(.cancel); fail("The website returned an error. Please try again."); return
        }
        guard !response.canShowMIMEType else { decisionHandler(.allow); return }
        guard let url = response.response.url, policy.isInternal(url), response.isForMainFrame else { decisionHandler(.cancel); return }
        decisionHandler(.download)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            if policy.isInternal(url) { navigate(url.absoluteString) }
            else if NavigationPolicy.externalAllowed(url) { NativePresentation.open(url) }
        }
        return nil
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(interactive && frame.isMainFrame && trusted(origin) ? .prompt : .deny)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AppifyDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Bounded retention; only app-owned temporary downloads are removed.
        if let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]) {
            for file in files where ((try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) < Date().addingTimeInterval(-86400) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        let filename = String((suggestedFilename as NSString).lastPathComponent.prefix(150))
        let file = folder.appendingPathComponent(UUID().uuidString + "-" + (filename.isEmpty ? "download" : filename))
        downloads[ObjectIdentifier(download)] = file
        completionHandler(file)
    }
    func downloadDidFinish(_ download: WKDownload) {
        if let file = downloads.removeValue(forKey: ObjectIdentifier(download)) { NativePresentation.share([file]) }
        loading = false
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let file = downloads.removeValue(forKey: ObjectIdentifier(download)) { try? FileManager.default.removeItem(at: file) }
        fail("The download could not be completed. Please try again.")
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard interactive, frame.isMainFrame, trusted(frame.securityOrigin), let controller = NativePresentation.controller else { completionHandler(); return }
        let alert = UIAlertController(title: policy.base?.host, message: String(message.prefix(4096)), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        controller.present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard interactive, frame.isMainFrame, trusted(frame.securityOrigin), let controller = NativePresentation.controller else { completionHandler(false); return }
        let alert = UIAlertController(title: policy.base?.host, message: String(message.prefix(4096)), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        controller.present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard interactive, frame.isMainFrame, trusted(frame.securityOrigin), let controller = NativePresentation.controller else { completionHandler(nil); return }
        let alert = UIAlertController(title: policy.base?.host, message: String(prompt.prefix(4096)), preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in completionHandler(alert?.textFields?.first?.text) })
        controller.present(alert, animated: true)
    }
    private func trusted(_ origin: WKSecurityOrigin) -> Bool {
        guard let base = policy.base else { return false }
        return origin.protocol.lowercased() == "https" && origin.host.lowercased() == base.host?.lowercased()
            && (origin.port == 0 ? 443 : origin.port) == (base.port ?? 443)
    }
    func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, trusted(message.frameInfo.securityOrigin),
              let body = message.body as? String, body.utf8.count <= 16384,
              let data = body.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["version"] as? Int == 1 else { return }
        let payload = event["payload"] as? [String: Any] ?? [:]
        let type = event["type"] as? String
        if !interactive && !["ready", "routeChanged", "scrollPosition"].contains(type ?? "") { return }
        switch type {
        case "location":
            guard let id = payload["id"] as? Int else { return }
            if config.features.enableLocation { location.request(id: id, watch: payload["watch"] as? Bool ?? false) }
            else {
                webView.evaluateJavaScript("if(window.__appifyLocationReply)window.__appifyLocationReply(\(id),{error:{code:1,message:'Location is disabled for this app.'}})", completionHandler: nil)
            }
        case "clearLocation": if let id = payload["id"] as? Int { location.clear(id) }
        case "ready": documentReady = true; finishReady()
        case "routeChanged":
            if let raw = payload["url"] as? String, let url = URL(string: raw), policy.isInternal(url) { currentURL = raw }
        case "navigate": if let path = payload["path"] as? String, policy.resolve(path) != nil { onNativeNavigate?(path) }
        case "scrollState": innerAtTop = payload["atTop"] as? Bool ?? false
        case "scrollPosition": scrollPosition = ["x": max(0, payload["x"] as? Int ?? 0), "y": max(0, payload["y"] as? Int ?? 0)]
        case "share":
            let text = String((payload["text"] as? String ?? "").prefix(4096))
            var items: [Any] = text.isEmpty ? [] : [text]
            if let raw = payload["url"] as? String, let url = URL(string: raw), NavigationPolicy.validHTTPS(url) { items.append(url) }
            if !items.isEmpty { NativePresentation.share(items) }
        case "requestNotifications": if config.features.enablePushNotifications { PushNotificationService.shared.requestPermission() }
        case "identity":
            PushNotificationService.shared.updateIdentity(payload)
            webView.evaluateJavaScript("window.__appifyHasIdentity=\(PushNotificationService.shared.hasIdentity)", completionHandler: nil)
        case "logout":
            PushNotificationService.shared.clearIdentity()
            webView.evaluateJavaScript("window.__appifyHasIdentity=false", completionHandler: nil)
        case "tags": PushNotificationService.shared.updateTags(payload["tags"] as? [String] ?? [])
        case "session": break // Cookies/localStorage stay in WKWebsiteDataStore; never mirror all storage into defaults.
        case "fcmToken":
            if config.features.enablePushNotifications, let token = PushNotificationService.shared.token {
                webView.evaluateJavaScript("if(window.onSaaS_FCMToken)window.onSaaS_FCMToken(\(Self.json(token)))", completionHandler: nil)
            }
        default: break
        }
    }
}

@MainActor
enum NativePresentation {
    static var controller: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let root = scenes.first(where: { $0.activationState == .foregroundActive })?.windows.first(where: \.isKeyWindow)?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
    static func open(_ url: URL) {
        guard NavigationPolicy.externalAllowed(url) else { return }
        if url.scheme == "https", let controller { controller.present(SFSafariViewController(url: url), animated: true) }
        else { UIApplication.shared.open(url) }
    }
    static func share(_ items: [Any]) {
        guard let controller else { return }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = controller.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
        controller.present(sheet, animated: true)
    }
}
