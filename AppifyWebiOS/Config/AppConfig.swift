import Foundation
import SwiftUI

struct AppConfig: Codable, Equatable {
    var targetUrl: String
    var primaryColor: String = "#0F9B9B"
    var secondaryColor: String = "#FFFFFF"
    var splashLogoUrl: String?
    var userAgentSuffix: String?
    var subscriptionExpiredMessage: String = "This app's subscription has expired. Please contact the administrator."
    var isActive: Bool = true
    var isSubscriptionActive: Bool = true
    var features: AppFeatures = AppFeatures()

    // Computed Colors
    var uiPrimaryColor: Color   { Color(hex: primaryColor)   }
    var uiSecondaryColor: Color { Color(hex: secondaryColor) }
}

struct AppFeatures: Codable, Equatable {
    var enablePushNotifications: Bool = false
    var enableBiometrics: Bool = false
    var enableLocation: Bool = false
    var showBottomNav: Bool = false
    var screenOrientation: String = "portrait"  // portrait | landscape | auto
    var navigationTabs: [NavigationTab] = []
    var hiddenNavPaths: [String] = []
}

struct NavigationTab: Codable, Identifiable, Equatable {
    var id: String { label + url }
    var label: String
    var icon: String
    var url: String
    
    var path: String {
        if url.hasPrefix("http") {
             if let uri = URL(string: url) {
                 return uri.path
             }
             return "/"
        }
        return url
    }
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
