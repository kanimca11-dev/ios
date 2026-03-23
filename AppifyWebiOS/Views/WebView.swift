import SwiftUI
import WebKit
import UniformTypeIdentifiers

// MARK: - Navigation State

class NavigationState: ObservableObject {
    @Published var currentUrl: String  = ""
    @Published var isLoading:  Bool    = false
    @Published var canGoBack:  Bool    = false
    @Published var pageLoaded: Bool    = false  // fires once after first real page load
    /// Set from outside (bottom-nav taps) to trigger programmatic navigation
    @Published var navigateTo: String? = nil
}

// MARK: - WebView

struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var navigationState: NavigationState
    let userAgentSuffix: String?
    var onFirstPageLoaded: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        // ── Configuration ──────────────────────────────────────────────────────
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        // JS bridge: window.webkit.messageHandlers.AppifyWeb.postMessage("…")
        cfg.userContentController.add(context.coordinator, name: "AppifyWeb")

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate         = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        // Disable auto inset so website fills edge-to-edge (website CSS handles safe areas)
        wv.scrollView.contentInsetAdjustmentBehavior = .never

        // Custom user agent
        if let suffix = userAgentSuffix {
            let base = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
                       "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
            wv.customUserAgent = "\(base) \(suffix)"
        }

        // ── Pull-to-refresh ────────────────────────────────────────────────────
        let refreshCtl = UIRefreshControl()
        refreshCtl.addTarget(context.coordinator,
                             action: #selector(Coordinator.handleRefresh(_:)),
                             for: .valueChanged)
        wv.scrollView.refreshControl = refreshCtl

        context.coordinator.webView = wv
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        // Programmatic navigation (bottom-nav taps or deep links)
        if let dest = navigationState.navigateTo, !dest.isEmpty {
            let fullUrl: URL?
            if dest.hasPrefix("http") {
                fullUrl = URL(string: dest)
            } else if let base = wv.url {
                fullUrl = URL(string: (base.scheme ?? "https") + "://" + (base.host ?? "") + dest)
            } else {
                fullUrl = nil
            }
            if let u = fullUrl { wv.load(URLRequest(url: u)) }
            DispatchQueue.main.async { self.navigationState.navigateTo = nil }
        }
    }

    // MARK: Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: WebView
        weak var webView: WKWebView?

        init(_ parent: WebView) { self.parent = parent }

        // ── Pull-to-refresh ────────────────────────────────────────────────────
        @objc func handleRefresh(_ sender: UIRefreshControl) {
            webView?.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { sender.endRefreshing() }
        }

        // ── Navigation callbacks ───────────────────────────────────────────────
        func webView(_ wv: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            parent.navigationState.isLoading = true
        }

        func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
            parent.navigationState.isLoading  = false
            parent.navigationState.canGoBack  = wv.canGoBack
            parent.navigationState.currentUrl = wv.url?.absoluteString ?? ""
            wv.scrollView.refreshControl?.endRefreshing()

            // Signal first real page load → hides splash overlay
            if !parent.navigationState.pageLoaded,
               let urlStr = wv.url?.absoluteString, urlStr != "about:blank" {
                parent.navigationState.pageLoaded = true
                parent.onFirstPageLoaded?()
            }

            // Inject throttled scroll listener → posts 'scroll' to Swift bridge
            let scrollJS = """
            (function() {
                if (window.__appifyScrollListenerInstalled) return;
                window.__appifyScrollListenerInstalled = true;
                var t = 0;
                window.addEventListener('scroll', function() {
                    var now = Date.now();
                    if (now - t > 200) {
                        t = now;
                        if (window.webkit && window.webkit.messageHandlers.AppifyWeb) {
                            window.webkit.messageHandlers.AppifyWeb.postMessage('scroll');
                        }
                    }
                }, { passive: true });
            })();
            """
            wv.evaluateJavaScript(scrollJS, completionHandler: nil)

            // Mirror Android UserUtils: cache localStorage JSON
            wv.evaluateJavaScript("JSON.stringify(localStorage)") { result, _ in
                if let json = result as? String {
                    UserDefaults.standard.set(json, forKey: "webview_local_storage")
                }
            }
        }

        func webView(_ wv: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            parent.navigationState.isLoading = false
            wv.scrollView.refreshControl?.endRefreshing()
        }

        func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
            parent.navigationState.isLoading = false
            wv.scrollView.refreshControl?.endRefreshing()
        }

        // ── File upload (UIDocumentPicker via WKUIDelegate) ────────────────────
        // WKOpenPanelParameters arrived in iOS 18.4; on earlier versions the
        // OS shows its own native file picker for <input type="file"> automatically.
        @available(iOS 18.4, *)
        func webView(_ wv: WKWebView,
                     runOpenPanelWith params: WKOpenPanelParameters,
                     initiatedByFrame _: WKFrameInfo,
                     completionHandler: @escaping ([URL]?) -> Void) {

            let types: [UTType] = [.image, .movie, .pdf, .data]
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
            picker.allowsMultipleSelection = params.allowsMultipleSelection

            // Wrap in a host controller so we get the result
            let host = FilePickerHost(onPick: completionHandler)
            picker.delegate = host

            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root  = scene.windows.first?.rootViewController {
                root.present(picker, animated: true)
                // Retain host for the life of the picker
                objc_setAssociatedObject(picker, &AssocKey.host, host, .OBJC_ASSOCIATION_RETAIN)
            } else {
                completionHandler(nil)
            }
        }

        // ── JS Bridge ──────────────────────────────────────────────────────────
        func userContentController(_ uc: WKUserContentController,
                                   didReceive msg: WKScriptMessage) {
            guard msg.name == "AppifyWeb",
                  let body = msg.body as? String else { return }
            NotificationCenter.default.post(name: .webViewJSMessage,
                                            object: nil,
                                            userInfo: ["message": body])
        }
    }
}

// MARK: - File picker delegate helper

private class FilePickerHost: NSObject, UIDocumentPickerDelegate {
    let onPick: ([URL]?) -> Void
    init(onPick: @escaping ([URL]?) -> Void) { self.onPick = onPick }

    func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        onPick(urls)
    }
    func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) {
        onPick(nil)
    }
}

private enum AssocKey { static var host = "filePickerHost" }

// MARK: - Notification names

extension Notification.Name {
    static let webViewJSMessage = Notification.Name("webViewJSMessage")
}
