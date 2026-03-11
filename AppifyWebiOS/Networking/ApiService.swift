import Foundation

class ApiService: ObservableObject {
    @Published var appConfig: AppConfig?
    @Published var isLoading = true
    @Published var error: String?

    // Read from Info.plist (injected via XcodeGen / build settings)
    private var baseUrl: String {
        Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            ?? "https://www.appifyweb24.com/backend/index.php"
    }
    private var appToken: String {
        Bundle.main.object(forInfoDictionaryKey: "APP_TOKEN") as? String
            ?? "default_token"
    }

    private let cacheKey     = "cached_app_config"
    private let cacheTimeKey = "cached_app_config_time"
    private let cacheTTL: TimeInterval = 86_400  // 24 hours

    // MARK: - Public

    func fetchConfig() {
        isLoading = true
        error = nil

        guard let url = URL(string: "\(baseUrl)/config") else {
            loadFromCacheOrFail("Invalid API URL")
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        request.setValue(appToken,             forHTTPHeaderField: "X-App-Token")
        request.setValue("application/json",   forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, err in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let err = err {
                    self?.loadFromCacheOrFail(err.localizedDescription)
                    return
                }
                guard let data = data else {
                    self?.loadFromCacheOrFail("No data received")
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let result = try decoder.decode(AppConfigResponse.self, from: data)
                    self?.appConfig = result.data
                    self?.persistConfig(data)
                    // Persist brand colors for instant display on next cold start
                    if let cfg = self?.appConfig {
                        self?.persistColors(primary: cfg.primaryColor, secondary: cfg.secondaryColor)
                    }
                } catch {
                    self?.loadFromCacheOrFail("Config decode error: \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    // MARK: - Cache helpers

    private func loadFromCacheOrFail(_ msg: String) {
        if let cached = loadCachedConfig() {
            appConfig = cached
        } else {
            error = msg
        }
    }

    private func persistConfig(_ data: Data) {
        UserDefaults.standard.set(data,  forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)
    }

    private func loadCachedConfig() -> AppConfig? {
        guard
            let savedDate = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
            Date().timeIntervalSince(savedDate) < cacheTTL,
            let data = UserDefaults.standard.data(forKey: cacheKey)
        else { return nil }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(AppConfigResponse.self, from: data).data
    }

    // MARK: - Brand color persistence (instant colors before API returns)

    func persistColors(primary: String, secondary: String) {
        UserDefaults.standard.set(primary,   forKey: "brand_primary_color")
        UserDefaults.standard.set(secondary, forKey: "brand_secondary_color")
    }

    static func cachedPrimaryColor() -> String {
        UserDefaults.standard.string(forKey: "brand_primary_color")   ?? "#0F9B9B"
    }
    static func cachedSecondaryColor() -> String {
        UserDefaults.standard.string(forKey: "brand_secondary_color") ?? "#FFFFFF"
    }
}

struct AppConfigResponse: Codable {
    let success: Bool
    let data: AppConfig
}
