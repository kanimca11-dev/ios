import SwiftUI

@main
struct AppifyWebiOSApp: App {
    @StateObject private var apiService = ApiService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(apiService)
                .onAppear {
                    apiService.fetchConfig()
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var apiService: ApiService
    @StateObject var navigationState = NavigationState()
    @State private var selectedTab: String = "home"
    
    var body: some View {
        ZStack {
            if apiService.isLoading {
                // Splash / Loading Screen
                VStack {
                    if let splashUrl = apiService.appConfig?.splashLogoUrl, let url = URL(string: splashUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 150, height: 150)
                    } else {
                        Image(systemName: "globe")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.blue)
                    }
                    Text("Loading...")
                        .font(.headline)
                        .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
            } else if let config = apiService.appConfig {
                if !config.isSubscriptionActive {
                    // Subscription Expired
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                            .padding()
                        Text("Subscription Expired")
                            .font(.title)
                        Text(config.subscriptionExpiredMessage)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                } else {
                    // Main App Content
                    VStack(spacing: 0) {
                        WebView(
                            url: URL(string: config.targetUrl)!,
                            navigationState: navigationState,
                            userAgentSuffix: config.userAgentSuffix
                        )
                        
                        // Bottom Navigation
                        if config.features.showBottomNav && !shouldHideNavBar(path: navigationState.currentUrl, hiddenPaths: config.features.hiddenNavPaths) {
                            HStack {
                                ForEach(config.features.navigationTabs) { tab in
                                    Spacer()
                                    Button(action: {
                                        // Navigate logic here
                                        // Usually implies loading a new URL in WebView
                                        // This requires a more complex WebView logic (Observables/Bindings)
                                        print("Navigate to \(tab.url)")
                                    }) {
                                        VStack(spacing: 4) {
                                            Image(systemName: getSystemIconName(for: tab.icon))
                                                .font(.system(size: 20))
                                            Text(tab.label)
                                                .font(.caption)
                                        }
                                        .foregroundColor(config.uiPrimaryColor)
                                    }
                                    Spacer()
                                }
                            }
                            .padding(.vertical, 10)
                            .background(Color.white.shadow(radius: 2))
                        }
                    }
                    .ignoresSafeArea(edges: config.features.showBottomNav ? .top : .all)
                }
            } else if let error = apiService.error {
                // Error Screen
                VStack {
                    Image(systemName: "wifi.slash")
                        .font(.largeTitle)
                    Text("Connection Failed")
                        .font(.title)
                    Text(error)
                        .padding()
                    Button("Retry") {
                        apiService.fetchConfig()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
    }
    
    func shouldHideNavBar(path: String, hiddenPaths: [String]) -> Bool {
        // Simple check if current path contains any hidden path
        // Needs robust URL matching
        for hidden in hiddenPaths {
            if path.contains(hidden) {
                return true
            }
        }
        return false
    }
    
    func getSystemIconName(for icon: String) -> String {
        // Map material icons (from Android) to SF Symbols
        switch icon {
        case "home": return "house.fill"
        case "shopping_cart": return "cart.fill"
        case "person": return "person.fill"
        case "settings": return "gear"
        case "favorite": return "heart.fill"
        case "list": return "list.bullet"
        case "mail": return "envelope.fill"
        case "notifications": return "bell.fill"
        default: return "star.fill"
        }
    }
}
