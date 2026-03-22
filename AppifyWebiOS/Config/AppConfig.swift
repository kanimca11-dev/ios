import Foundation
import SwiftUI

struct AppConfig: Codable, Equatable {
    var targetUrl: String
    var primaryColor: String
    var secondaryColor: String
    var splashLogoUrl: String?
    var splashImageUrl: String?   // full-screen background splash image
    var userAgentSuffix: String?
    var subscriptionExpiredMessage: String
    var isActive: Bool
    var isSubscriptionActive: Bool
    var features: AppFeatures

    // Computed Colors
    var uiPrimaryColor: Color   { Color(hex: primaryColor)   }
    var uiSecondaryColor: Color { Color(hex: secondaryColor) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        targetUrl                  = try c.decode(String.self, forKey: .targetUrl)
        primaryColor               = try c.decodeIfPresent(String.self, forKey: .primaryColor)               ?? "#0F9B9B"
        secondaryColor             = try c.decodeIfPresent(String.self, forKey: .secondaryColor)             ?? "#FFFFFF"
        splashLogoUrl              = try c.decodeIfPresent(String.self, forKey: .splashLogoUrl)
        splashImageUrl             = try c.decodeIfPresent(String.self, forKey: .splashImageUrl)
        userAgentSuffix            = try c.decodeIfPresent(String.self, forKey: .userAgentSuffix)
        subscriptionExpiredMessage = try c.decodeIfPresent(String.self, forKey: .subscriptionExpiredMessage) ?? "Subscription expired."
        isActive                   = try c.decodeIfPresent(Bool.self,   forKey: .isActive)                   ?? true
        isSubscriptionActive       = try c.decodeIfPresent(Bool.self,   forKey: .isSubscriptionActive)       ?? true
        features                   = try c.decodeIfPresent(AppFeatures.self, forKey: .features)              ?? AppFeatures()
    }
}

struct AppFeatures: Codable, Equatable {
    var enablePushNotifications: Bool = false
    var enableBiometrics: Bool = false
    var enableLocation: Bool = false
    var showBottomNav: Bool = false
    var screenOrientation: String = "portrait"  // portrait | landscape | auto
    var navigationTabs: [NavigationTab] = []
    var hiddenNavPaths: [String] = []

    init(enablePushNotifications: Bool = false, enableBiometrics: Bool = false,
         enableLocation: Bool = false, showBottomNav: Bool = false,
         screenOrientation: String = "portrait",
         navigationTabs: [NavigationTab] = [], hiddenNavPaths: [String] = []) {
        self.enablePushNotifications = enablePushNotifications
        self.enableBiometrics        = enableBiometrics
        self.enableLocation          = enableLocation
        self.showBottomNav           = showBottomNav
        self.screenOrientation       = screenOrientation
        self.navigationTabs          = navigationTabs
        self.hiddenNavPaths          = hiddenNavPaths
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enablePushNotifications = try c.decodeIfPresent(Bool.self, forKey: .enablePushNotifications) ?? false
        enableBiometrics        = try c.decodeIfPresent(Bool.self, forKey: .enableBiometrics)        ?? false
        enableLocation          = try c.decodeIfPresent(Bool.self, forKey: .enableLocation)          ?? false
        showBottomNav           = try c.decodeIfPresent(Bool.self, forKey: .showBottomNav)           ?? false
        screenOrientation       = try c.decodeIfPresent(String.self, forKey: .screenOrientation)     ?? "portrait"
        navigationTabs          = try c.decodeIfPresent([NavigationTab].self, forKey: .navigationTabs) ?? []
        hiddenNavPaths          = try c.decodeIfPresent([String].self, forKey: .hiddenNavPaths)      ?? []
    }
}

struct NavigationTab: Codable, Identifiable, Equatable {
    var id: String { label + path }
    var label: String
    var icon: String
    var path: String
}

// Helper for Hex Colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 15, 155, 155)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
