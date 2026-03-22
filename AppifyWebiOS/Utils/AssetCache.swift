import UIKit

/// Downloads and caches remote images to disk (logo + splash screen).
final class AssetCache {
    static let shared = AssetCache()

    private let dir: URL
    private var logoFile:   URL { dir.appendingPathComponent("splash_logo.png")   }
    private var splashFile: URL { dir.appendingPathComponent("splash_screen.png") }

    private init() {
        dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Logo

    func cachedLogo() -> UIImage? { load(from: logoFile) }

    func cacheLogo(from urlString: String, completion: ((UIImage?) -> Void)? = nil) {
        download(urlString: urlString, to: logoFile, completion: completion)
    }

    // MARK: - Splash screen

    func cachedSplash() -> UIImage? { load(from: splashFile) }

    func cacheSplash(from urlString: String, completion: ((UIImage?) -> Void)? = nil) {
        download(urlString: urlString, to: splashFile, completion: completion)
    }

    // MARK: - Private helpers

    private func load(from file: URL) -> UIImage? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return UIImage(contentsOfFile: file.path)
    }

    private func download(urlString: String, to file: URL, completion: ((UIImage?) -> Void)?) {
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion?(nil) }
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard self != nil, let data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }
            if let png = image.pngData() {
                try? png.write(to: file, options: .atomic)
            }
            DispatchQueue.main.async { completion?(image) }
        }.resume()
    }
}
