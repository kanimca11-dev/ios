import UIKit

/// Downloads and caches the splash logo to disk — mirrors Android's AssetCacheManager.kt
final class AssetCache {
    static let shared = AssetCache()
    private let cacheFile: URL

    private init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheFile = dir.appendingPathComponent("splash_logo.png")
    }

    // MARK: - Public

    /// Returns the cached logo UIImage if available, or nil.
    func cachedLogo() -> UIImage? {
        guard FileManager.default.fileExists(atPath: cacheFile.path) else { return nil }
        return UIImage(contentsOfFile: cacheFile.path)
    }

    /// Downloads a logo from `urlString` and writes it to the on-disk cache.
    /// Calls `completion` on the main queue with the downloaded image (or nil on failure).
    func cacheLogo(from urlString: String, completion: ((UIImage?) -> Void)? = nil) {
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion?(nil) }
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            // Write PNG to disk
            if let png = image.pngData() {
                try? png.write(to: self.cacheFile, options: .atomic)
            }

            DispatchQueue.main.async { completion?(image) }
        }.resume()
    }

    /// Returns cached image if fresh, otherwise downloads in background and returns nil.
    /// On completion the next call to `cachedLogo()` will return the new image.
    func logoForSplash(urlString: String?) -> UIImage? {
        let cached = cachedLogo()
        if let urlString, cached == nil {
            cacheLogo(from: urlString)
        }
        return cached
    }
}
