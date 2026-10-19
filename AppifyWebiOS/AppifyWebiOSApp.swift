import SwiftUI
import UIKit

@main
struct AppifyWebiOSApp: App {
    @StateObject private var api = ApiService()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(api) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PushNotificationService.shared.prepare()
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        PushNotificationService.shared.didRegister(deviceToken: token)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppOrientation.mask
    }
}

enum AppOrientation {
    static var mask: UIInterfaceOrientationMask = .portrait
    static func apply(_ value: String) {
        mask = value == "landscape" ? .landscape : value == "auto" ? .all : .portrait
        if #available(iOS 16.0, *), let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}

@MainActor
struct ContentView: View {
    @EnvironmentObject private var api: ApiService
    @StateObject private var store = ShellStore()
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var push = PushNotificationService.shared
    @Environment(\.scenePhase) private var phase
    @State private var offerPush = false
    var body: some View {
        let config = api.appConfig
        ZStack {
            config.uiSecondaryColor.ignoresSafeArea()
            if !config.isActive || !config.isSubscriptionActive {
                SubscriptionExpiredView(message: config.subscriptionExpiredMessage, primaryColor: config.uiPrimaryColor, onRetry: { api.fetchConfig() })
            } else if config.features.enableBiometrics && !store.unlocked {
                BiometricLockView(primaryColor: config.uiPrimaryColor) { store.didUnlock() }
            } else if NavigationPolicy(config.targetUrl).base == nil {
                message("Configure a valid HTTPS website and rebuild this app.", retry: { api.fetchConfig() })
            } else if let session = store.active {
                SessionScreen(session: session, store: store, config: config, online: network.isConnected, offerPush: $offerPush)
                    .allowsHitTesting(store.launchFinished)
            }
            if !store.launchFinished && config.isActive && config.isSubscriptionActive && (!config.features.enableBiometrics || store.unlocked) && NavigationPolicy(config.targetUrl).base != nil {
                SplashView().ignoresSafeArea()
            }
        }
        .onAppear { apply(config); api.fetchConfig() }
        .onChange(of: api.appConfig) { apply($0) }
        .onChange(of: phase) { state in
            if state == .background { store.background(); store.rememberSelection() }
            if state == .active { store.foreground(); api.fetchConfig() }
        }
        .onChange(of: network.isConnected) { connected in
            if connected { api.fetchConfig(); if store.active?.error != nil { store.active?.reload() } }
        }
        .onChange(of: push.pendingDeepLinkUrl) { raw in
            guard let raw, let url = URL(string: raw), NavigationPolicy(config.targetUrl).isInternal(url) else { push.pendingDeepLinkUrl = nil; return }
            store.navigate(raw); push.pendingDeepLinkUrl = nil
        }
        .onOpenURL { url in
            if NavigationPolicy(config.targetUrl).isInternal(url) { store.navigate(url.absoluteString) }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL, NavigationPolicy(config.targetUrl).isInternal(url) { store.navigate(url.absoluteString) }
        }
        .alert("Stay up to date", isPresented: $offerPush) {
            Button("Allow") { UserDefaults.standard.set(true, forKey: "notification_prompted"); push.requestPermission() }
            Button("Later", role: .cancel) { UserDefaults.standard.set(true, forKey: "notification_prompted") }
        } message: { Text("Allow notifications for important updates from this app?") }
    }
    private func apply(_ config: AppConfig) {
        store.update(config)
        push.setEnabled(config.features.enablePushNotifications && config.isActive && config.isSubscriptionActive)
        AppOrientation.apply(config.features.screenOrientation)
    }
    private func message(_ text: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 16) { Text(text).multilineTextAlignment(.center); Button("Retry", action: retry).buttonStyle(.borderedProminent) }.padding()
    }
}

@MainActor
private struct SessionScreen: View {
    @ObservedObject var session: WebSession
    @ObservedObject var store: ShellStore
    let config: AppConfig
    let online: Bool
    @Binding var offerPush: Bool
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                WebView(session: session)
                if session.loading && session.ready && session.error == nil {
                    ProgressView(value: session.progress).tint(config.uiPrimaryColor)
                }
                if !session.ready && session.error == nil && store.launchFinished {
                    config.uiSecondaryColor.overlay(ProgressView().tint(config.uiPrimaryColor))
                }
                if let error = session.error {
                    config.uiSecondaryColor.overlay {
                        VStack(spacing: 16) {
                            Image(systemName: online ? "exclamationmark.triangle" : "wifi.slash").font(.largeTitle)
                            Text(error).multilineTextAlignment(.center)
                            Button("Retry") { session.reload() }.buttonStyle(.borderedProminent).tint(config.uiPrimaryColor)
                        }.padding(24)
                    }
                }
            }
            if !online && session.ready { Text("You�re offline. Showing available content.").font(.caption).padding(8).frame(maxWidth: .infinity).background(.thinMaterial) }
            if config.features.showBottomNav && !store.tabs.isEmpty && !config.features.hiddenNavPaths.contains(where: { !$0.isEmpty && NavigationPolicy.matches(session.currentURL, $0) }) {
                HStack(spacing: 0) {
                    ForEach(store.tabs) { tab in
                        let selected = store.selected == tab.path
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            if selected { session.scrollToTop() } else { store.select(tab.path) }
                        } label: {
                            VStack(spacing: 4) { Image(systemName: symbol(tab.icon)); Text(tab.label).font(.caption).lineLimit(1) }
                                .foregroundColor(selected ? config.uiPrimaryColor : .secondary)
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }.accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }.background(config.uiSecondaryColor)
            }
        }
        .id(ObjectIdentifier(session))
        .onChange(of: session.error) { if $0 != nil { store.finishLaunch() } }
        .onChange(of: session.ready) { ready in
            if ready {
                store.finishLaunch()
                if config.features.enablePushNotifications && !UserDefaults.standard.bool(forKey: "notification_prompted") { offerPush = true }
            }
        }
    }
    private func symbol(_ icon: String) -> String {
        switch icon.lowercased() {
        case "home", "house": return "house"
        case "cart", "shopping_cart", "bag": return "cart"
        case "person", "profile", "account", "user": return "person"
        case "shop", "store", "storefront": return "storefront"
        case "orders", "order", "inventory": return "shippingbox"
        case "category", "grid_view", "grid": return "square.grid.2x2"
        case "favorite", "heart": return "heart"
        case "settings", "gear": return "gearshape"
        case "search": return "magnifyingglass"
        case "notifications", "bell": return "bell"
        case "blog", "article": return "newspaper"
        case "map", "location": return "map"
        default: return "circle"
        }
    }
}
