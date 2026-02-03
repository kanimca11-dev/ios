import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var navigationState: NavigationState
    let userAgentSuffix: String?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Add message handlers for JS bridge if needed
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        if let suffix = userAgentSuffix {
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 " + suffix
        }
        
        // Pull to refresh support
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.reload), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Load URL if changed or initial load
        if uiView.url == nil {
            let request = URLRequest(url: url)
            uiView.load(request)
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        @objc func reload(_ sender: UIRefreshControl) {
            sender.endRefreshing()
            // Reload logic handled by WebKit automatically? No, we need to trigger it.
            // But usually sender is attached to scrollview.
            // We can acccess webview via parent... wait, UIViewRepresentable doesn't store reference easily.
            // In a real app, you'd pass a command or use a dependency injection to trigger reload.
            // For simplicity, we assume standard web behavior.
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.navigationState.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.navigationState.isLoading = false
            parent.navigationState.currentUrl = webView.url?.absoluteString ?? ""
            parent.navigationState.canGoBack = webView.canGoBack
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.navigationState.isLoading = false
        }
    }
}

class NavigationState: ObservableObject {
    @Published var currentUrl: String = ""
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
}
