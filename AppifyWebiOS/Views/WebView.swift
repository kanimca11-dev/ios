import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    @ObservedObject var session: WebSession
    func makeUIView(context: Context) -> WKWebView { session.webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
    // The session store, rather than SwiftUI tab changes, owns WKWebView lifetime.
}
