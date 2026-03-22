import SwiftUI

/// Static full-screen splash — shown while the WebView is loading.
/// Mirrors the LaunchScreen to prevent any visual flicker between
/// the system launch screen and the in-app splash.
struct SplashView: View {
    /// Full-screen splash/background image (downloaded from config).
    let splashImage: UIImage?
    /// Brand primary color — used as background when no image is available.
    let primaryColor: Color
    /// App logo — centered on top of the color background fallback.
    let logoImage: UIImage?

    var body: some View {
        ZStack {
            if let splash = splashImage {
                // ── Full-screen splash image ───────────────────────────────────
                Image(uiImage: splash)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            } else {
                // ── Fallback: solid primary color + centered logo ──────────────
                primaryColor
                    .ignoresSafeArea()

                if let logo = logoImage {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                } else {
                    Image(systemName: "globe")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
    }
}
