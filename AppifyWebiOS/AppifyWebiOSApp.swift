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
        let showNav = config.features.showBottomNav && !shouldHideNav(config: config)
        return VStack(spacing: 0) {
            WebView(
                url: URL(string: config.targetUrl)!,
                navigationState: nav,
                userAgentSuffix: config.userAgentSuffix,
                onFirstPageLoaded: {
                    withAnimation(.easeOut(duration: 0.6)) { showSplash = false }
                }
            )
            if showNav {
                bottomNavBar(config: config)
            }
        }
    }

    // MARK: - Bottom Navigation Bar (actually navigates — fixes original bug)

    private func bottomNavBar(config: AppConfig) -> some View {
        HStack(spacing: 0) {
            ForEach(config.features.navigationTabs) { tab in
                let isActive = !tab.path.isEmpty && nav.currentUrl.contains(tab.path)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let dest: String
                    if tab.path.hasPrefix("http") {
                        dest = tab.path
                    } else {
                        let base = config.targetUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        let path = tab.path.hasPrefix("/") ? tab.path : "/\(tab.path)"
                        dest = base + path
                    }
                    nav.navigateTo = dest
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: sfSymbol(for: tab.icon))
                            .font(.system(size: 20, weight: isActive ? .semibold : .regular))
                            .symbolVariant(isActive ? .fill : .none)
                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .foregroundColor(isActive ? .white : .white.opacity(0.65))
                }
            }
        }
        .background(primaryColor)
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
        switch icon.lowercased() {
        // Home / navigation
        case "home", "house":                          return "house"
        case "menu", "hamburger":                      return "line.3.horizontal"
        case "back":                                   return "chevron.left"
        // Shopping
        case "shopping_cart", "cart", "bag":           return "cart"
        case "store", "shop", "storefront":            return "storefront"
        case "orders", "order":                        return "bag"
        // People
        case "person", "account", "profile", "user":  return "person"
        case "persons", "people", "customers", "users","person_2","group": return "person.2"
        // Settings / tools
        case "settings", "setting", "gear":            return "gear"
        case "tune", "filter", "sliders":              return "slider.horizontal.3"
        // Content
        case "favorite", "favorites", "heart", "like": return "heart"
        case "star", "starred":                        return "star"
        case "bookmark", "bookmarks":                  return "bookmark"
        case "list", "list_alt":                       return "list.bullet"
        case "grid", "grid_view", "category":          return "square.grid.2x2"
        // Communication
        case "mail", "email", "message":               return "envelope"
        case "chat", "forum":                          return "bubble.left"
        case "notifications", "notification", "bell":  return "bell"
        case "phone", "call":                          return "phone"
        // Analytics / data
        case "dashboard", "analytics", "insights":     return "chart.bar"
        case "chart", "bar_chart":                     return "chart.bar.xaxis"
        case "trending_up", "trend":                   return "chart.line.uptrend.xyaxis"
        // Planning / calendar
        case "plan", "planning", "calendar", "event", "schedule": return "calendar"
        case "task", "tasks", "checklist":             return "checklist"
        case "clipboard":                              return "clipboard"
        // Location
        case "location", "map", "place", "pin":        return "map"
        // Media
        case "image", "photo", "gallery":              return "photo"
        case "camera":                                 return "camera"
        case "video":                                  return "video"
        // Misc
        case "search", "find":                         return "magnifyingglass"
        case "info", "information":                    return "info.circle"
        case "help", "question":                       return "questionmark.circle"
        case "add", "plus":                            return "plus"
        case "edit", "pencil":                         return "pencil"
        case "delete", "trash":                        return "trash"
        case "share":                                  return "square.and.arrow.up"
        case "download":                               return "arrow.down.circle"
        case "upload":                                 return "arrow.up.circle"
        case "refresh", "sync":                        return "arrow.clockwise"
        case "work", "business", "briefcase":          return "briefcase"
        case "money", "attach_money", "payment", "wallet": return "dollarsign.circle"
        case "inventory", "warehouse":                 return "shippingbox"
        case "report", "reports":                      return "doc.text"
        case "support", "headset":                     return "headphones"
        case "loyalty", "rewards":                     return "gift"
        case "tracking":                               return "location.circle"
        default:                                       return "circle"
        }
    }

    private func applyOrientation(_ orientation: String) {
        // requestGeometryUpdate requires iOS 16+; on iOS 15 portrait is the default
        guard #available(iOS 16.0, *) else { return }
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
