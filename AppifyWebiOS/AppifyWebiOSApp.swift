import SwiftUI

// MARK: - App Entry

@main
struct AppifyWebiOSApp: App {
    @StateObject private var apiService = ApiService()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(apiService)
                .onAppear { apiService.fetchConfig() }
        }
    }
}

// MARK: - App Delegate (APNs)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        PushNotificationService.shared.didRegister(deviceToken: token)
    }
    func application(_ app: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[Push] APNs registration failed: \(error.localizedDescription)")
    }
}

// MARK: - Root Content View

struct ContentView: View {
    @EnvironmentObject var apiService: ApiService
    @StateObject private var nav = NavigationState()
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var pushService = PushNotificationService.shared

    // Brand colors — loaded from cache instantly so no flash on cold start
    @State private var primaryColor   = Color(hex: ApiService.cachedPrimaryColor())
    @State private var secondaryColor = Color(hex: ApiService.cachedSecondaryColor())

    // Splash logo cached on disk
    @State private var logoImage: UIImage? = AssetCache.shared.cachedLogo()

    // Splash overlay stays until WebView fires onFirstPageLoaded (max 8s safety fallback)
    @State private var showSplash = true

    // Biometric gate
    @State private var isUnlocked = false

    var body: some View {
        ZStack {
            mainContent
            splashOverlay
        }
        // Push notification deep-link: when user taps a notification, navigate WebView
        .onChange(of: pushService.pendingDeepLinkUrl) { url in
            guard let url else { return }
            nav.navigateTo = url
            pushService.pendingDeepLinkUrl = nil
        }
        .onChange(of: apiService.appConfig) { cfg in
            guard let cfg else { return }
            primaryColor   = cfg.uiPrimaryColor
            secondaryColor = cfg.uiSecondaryColor

            // Cache logo to disk in background
            if let logoUrl = cfg.splashLogoUrl {
                AssetCache.shared.cacheLogo(from: logoUrl) { img in
                    if let img { logoImage = img }
                }
            }
            // Push notifications
            if cfg.features.enablePushNotifications {
                PushNotificationService.shared.requestPermission()
            }
            // Screen orientation
            applyOrientation(cfg.features.screenOrientation)

            // If app or subscription not active, drop splash immediately
            if !cfg.isActive || !cfg.isSubscriptionActive {
                withAnimation { showSplash = false }
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if !network.isConnected && apiService.appConfig == nil {
            offlineView
        } else if let config = apiService.appConfig {
            if !config.isActive || !config.isSubscriptionActive {
                SubscriptionExpiredView(
                    message: config.subscriptionExpiredMessage,
                    primaryColor: primaryColor,
                    onRetry: { apiService.fetchConfig() }
                )
            } else if config.features.enableBiometrics && !isUnlocked {
                BiometricLockView(primaryColor: primaryColor) {
                    withAnimation { isUnlocked = true }
                }
            } else {
                appShell(config: config)
            }
        } else if let error = apiService.error {
            errorView(message: error)
        } else {
            // Still loading on first launch — splash overlay covers this
            Color.black.ignoresSafeArea()
        }
    }

    // MARK: - App Shell (WebView + optional bottom nav)

    private func appShell(config: AppConfig) -> some View {
        VStack(spacing: 0) {
            WebView(
                url: URL(string: config.targetUrl)!,
                navigationState: nav,
                userAgentSuffix: config.userAgentSuffix,
                onFirstPageLoaded: {
                    withAnimation(.easeOut(duration: 0.6)) { showSplash = false }
                }
            )

            if config.features.showBottomNav && !shouldHideNav(config: config) {
                bottomNavBar(config: config)
            }
        }
        .ignoresSafeArea(edges: config.features.showBottomNav ? .top : .all)
    }

    // MARK: - Bottom Navigation Bar (actually navigates — fixes original bug)

    private func bottomNavBar(config: AppConfig) -> some View {
        HStack(spacing: 0) {
            ForEach(config.features.navigationTabs) { tab in
                let isActive = nav.currentUrl.contains(tab.path) && !tab.path.isEmpty

                Button {
                    // Haptic feedback (mirrors Android)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    // Actually navigate (fixes original iOS "print" stub)
                    nav.navigateTo = tab.url
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: sfSymbol(for: tab.icon))
                            .font(.system(size: 20))
                            .symbolVariant(isActive ? .fill : .none)
                        Text(tab.label)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(isActive ? primaryColor : Color(UIColor.systemGray))
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.bottom, 4)
        .background(
            Color(UIColor.systemBackground)
                .shadow(color: .black.opacity(0.12), radius: 4, y: -2)
        )
    }

    // MARK: - Splash Overlay

    @ViewBuilder
    private var splashOverlay: some View {
        if showSplash {
            SplashView(primaryColor: primaryColor, logoImage: logoImage)
                .ignoresSafeArea()
                .transition(.opacity)
                .onAppear {
                    // Safety fallback: hide after 8 s if WebView never fires onPageFinished
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                        withAnimation(.easeOut(duration: 0.6)) { showSplash = false }
                    }
                }
        }
    }

    // MARK: - Offline / Error views

    private var offlineView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 52))
                .foregroundColor(.gray)
            Text("No Connection")
                .font(.title2.bold())
            Text("Please check your internet connection and try again.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") { apiService.fetchConfig() }
                .buttonStyle(.borderedProminent)
                .tint(primaryColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundColor(.orange)
            Text("Something went wrong")
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") { apiService.fetchConfig() }
                .buttonStyle(.borderedProminent)
                .tint(primaryColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
    }

    // MARK: - Helpers

    private func shouldHideNav(config: AppConfig) -> Bool {
        config.features.hiddenNavPaths.contains { nav.currentUrl.contains($0) }
    }

    private func sfSymbol(for icon: String) -> String {
        switch icon {
        case "home":          return "house"
        case "shopping_cart": return "cart"
        case "person":        return "person"
        case "settings":      return "gear"
        case "favorite":      return "heart"
        case "list":          return "list.bullet"
        case "mail":          return "envelope"
        case "notifications": return "bell"
        case "search":        return "magnifyingglass"
        case "category":      return "square.grid.2x2"
        case "dashboard":     return "chart.bar"
        default:              return "star"
        }
    }

    private func applyOrientation(_ orientation: String) {
        let mask: UIInterfaceOrientationMask
        switch orientation {
        case "landscape": mask = .landscape
        case "auto":      mask = .all
        default:          mask = .portrait
        }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}
