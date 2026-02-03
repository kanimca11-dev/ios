import Foundation

class ApiService: ObservableObject {
    @Published var appConfig: AppConfig?
    @Published var isLoading = true
    @Published var error: String?
    
    // Replace with your actual API endpoint and App Token
    // These should ideally come from Info.plist or Build Settings
    private let baseUrl = "https://your-api-domain.com/api/v1" 
    private let appToken = "YOUR_APP_TOKEN" 
    
    func fetchConfig() {
        guard let url = URL(string: "\(baseUrl)/config") else {
            self.error = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.error = error.localizedDescription
                    return
                }
                
                guard let data = data else {
                    self?.error = "No data received"
                    return
                }
                
                do {
                    // Assuming the API returns a wrapper like { success: true, data: { ... } }
                    // Adjust decoding based on actual API response structure
                    let decoder = JSONDecoder()
                    let result = try decoder.decode(AppConfigResponse.self, from: data)
                    self?.appConfig = result.data
                } catch {
                    self?.error = "Failed to decode config: \(error.localizedDescription)"
                    print("Decode error: \(error)")
                }
            }
        }.resume()
    }
}

struct AppConfigResponse: Codable {
    let success: Bool
    let data: AppConfig
}
