import UIKit
import Combine
import UserNotifications
#if canImport(FirebaseCore)
import FirebaseCore
import FirebaseMessaging
#endif

/// Backend uses FCM device tokens, never raw APNs tokens.
final class PushNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationService()
    @Published var pendingDeepLinkUrl: String?
    private(set) var token: String?
    private var enabled = false
    private let updates: OperationQueue = { let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; return queue }()
    private var identity: [String: Any] = [:]
    var hasIdentity: Bool { !(identity["user_id"] as? String ?? "").isEmpty }
    private override init() { super.init() }
    func prepare() {
        UNUserNotificationCenter.current().delegate = self
        // Remove the legacy copy of all localStorage (may contain credentials).
        UserDefaults.standard.removeObject(forKey: "webview_local_storage")
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        #if canImport(FirebaseCore)
        if value, FirebaseApp.app() == nil, Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            Messaging.messaging().delegate = self
        }
        if FirebaseApp.app() != nil { Messaging.messaging().isAutoInitEnabled = value }
        #endif
        if value {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                    DispatchQueue.main.async { if self.enabled { UIApplication.shared.registerForRemoteNotifications() } }
                }
            }
        } else { updates.cancelAllOperations(); UIApplication.shared.unregisterForRemoteNotifications() }
    }
    func requestPermission() {
        guard enabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted { DispatchQueue.main.async { if self.enabled { UIApplication.shared.registerForRemoteNotifications() } } }
        }
    }
    func didRegister(deviceToken: Data) {
        guard enabled else { return }
        #if canImport(FirebaseCore)
        guard FirebaseApp.app() != nil else { return }
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { [weak self] token, _ in
            DispatchQueue.main.async { self?.receiveToken(token) }
        }
        #endif
    }
    func receiveToken(_ value: String?) {
        guard enabled, let value else { return }
        token = value
        sync()
    }
    func updateIdentity(_ payload: [String: Any]) {
        identity["user_id"] = String(String(describing: payload["id"] ?? "").prefix(255))
        identity["user_email"] = String((payload["email"] as? String ?? "").prefix(255))
        identity["user_name"] = String((payload["name"] as? String ?? "").prefix(255))
        sync()
    }
    func updateTags(_ values: [String]) { identity["user_tags"] = Array(values.prefix(50)).map { String($0.prefix(100)) }; sync() }
    func clearIdentity() {
        identity.removeAll()
        guard let token else { return }
        post("push/identity", method: "PUT", body: ["device_token": token, "clear": true])
    }
    private func sync() {
        guard let token else { return }
        var body = identity
        body["device_token"] = token; body["platform"] = "ios"
        post("push/register", method: "POST", body: body)
        if !hasIdentity { post("push/identity", method: "PUT", body: ["device_token": token, "clear": true]) }
    }
    private func post(_ path: String, method: String, body: [String: Any]) {
        guard enabled, ApiService.appToken != "default_token", !ApiService.appToken.isEmpty, let url = ApiService.endpoint(path) else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = method
        request.setValue(ApiService.appToken, forHTTPHeaderField: "X-App-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        // Serialize identity updates so a late login request cannot undo a logout clear.
        let outbound = request
        updates.addOperation {
            let finished = DispatchSemaphore(value: 0)
            let task = ApiService.session.dataTask(with: outbound) { _, _, _ in finished.signal() }
            task.resume()
            if finished.wait(timeout: .now() + 12) == .timedOut { task.cancel() }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(enabled ? [.banner, .badge, .sound] : [])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let url = info["url"] as? String ?? info["push_url"] as? String {
            DispatchQueue.main.async { if self.enabled { self.pendingDeepLinkUrl = url } }
        }
        completionHandler()
    }
}

#if canImport(FirebaseCore)
extension PushNotificationService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        DispatchQueue.main.async { self.receiveToken(fcmToken) }
    }
}
#endif
