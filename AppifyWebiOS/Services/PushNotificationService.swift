import UIKit
import UserNotifications

/// APNs push notification registration and deep-link handling.
/// Mirrors Android's MyFirebaseMessagingService.kt
/// Note: For full FCM support add the Firebase iOS SDK via SPM and uncomment the Firebase lines.
final class PushNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationService()

    /// URL to open when a push notification is tapped (observed by ContentView)
    @Published var pendingDeepLinkUrl: String? = nil

    private override init() { super.init() }

    // MARK: - Registration

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    /// Call from AppDelegate / scene delegate after receiving APNs token
    func didRegister(deviceToken: Data) {
        let tokenStr = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[Push] APNs device token: \(tokenStr)")

        // If using Firebase:
        // Messaging.messaging().apnsToken = deviceToken

        syncTokenToBackend(tokenStr)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Foreground notification display
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification,
                                 withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .badge, .sound])
    }

    /// Tap on notification
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 didReceive response: UNNotificationResponse,
                                 withCompletionHandler completion: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let url = userInfo["url"] as? String ?? userInfo["push_url"] as? String {
            DispatchQueue.main.async {
                self.pendingDeepLinkUrl = url
            }
        }
        completion()
    }

    // MARK: - Backend token sync (mirrors Android MyFirebaseMessagingService)

    private func syncTokenToBackend(_ token: String) {
        let apiBase = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
                      ?? "https://www.appifyweb24.com/backend/index.php"
        let appToken = Bundle.main.object(forInfoDictionaryKey: "APP_TOKEN") as? String
                      ?? "default_token"

        guard let url = URL(string: "\(apiBase)/v1/push/register") else { return }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["token": token, "platform": "ios"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request).resume()
    }
}
