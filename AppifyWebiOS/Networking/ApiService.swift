import Foundation
import Combine

/// Cached/local settings are available before the first frame; API refresh is background work.
private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let destination = request.url,
              NavigationPolicy(original.absoluteString).isInternal(destination) else { completionHandler(nil); return }
        completionHandler(request)
    }
}

final class ApiService: ObservableObject {
    static let session = URLSession(configuration: .ephemeral, delegate: SameOriginRedirects(), delegateQueue: nil)
    @Published private(set) var appConfig: AppConfig
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var task: URLSessionDataTask?
    static let cacheKey = "native_shell_config_v2"
    static var appToken: String { Bundle.main.object(forInfoDictionaryKey: "APP_TOKEN") as? String ?? "default_token" }
    static var baseURL: URL? {
        let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String ?? ""
        guard let url = URL(string: value), NavigationPolicy.validHTTPS(url) else { return nil }
        return url
    }
    static func endpoint(_ path: String) -> URL? {
        guard let base = baseURL else { return nil }
        return URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/" + path)
    }
    init() {
        let cached = UserDefaults.standard.data(forKey: Self.cacheKey).flatMap { try? JSONDecoder().decode(AppConfig.self, from: $0) }
        let bundled = Bundle.main.url(forResource: "bundled-config", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(AppConfig.self, from: $0) }
        // A cached disabled decision is retained even when offline; no expiry fallback re-enables it.
        appConfig = cached ?? bundled ?? AppConfig(targetUrl: "")
    }
    func fetchConfig() {
        guard task == nil else { return }
        guard Self.appToken != "default_token", !Self.appToken.isEmpty, let url = Self.endpoint("config") else { return }
        isLoading = true
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue(Self.appToken, forHTTPHeaderField: "X-App-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        task = Self.session.dataTask(with: request) { [weak self] data, response, failure in
            DispatchQueue.main.async {
                guard let self else { return }
                self.task = nil; self.isLoading = false
                guard failure == nil, let response = response as? HTTPURLResponse,
                      (200...299).contains(response.statusCode), let data,
                      let config = try? JSONDecoder().decode(AppConfig.self, from: data),
                      (NavigationPolicy(config.targetUrl).base != nil || !config.isActive || !config.isSubscriptionActive) else {
                    self.error = "App settings could not be refreshed. Using saved settings."
                    return
                }
                self.error = nil
                self.appConfig = config
                UserDefaults.standard.set(try? JSONEncoder().encode(config), forKey: Self.cacheKey)
            }
        }
        task?.resume()
    }
}
