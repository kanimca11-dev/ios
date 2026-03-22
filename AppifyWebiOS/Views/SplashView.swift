import SwiftUI

/// Static full-screen splash shown while the WebView is loading.
/// Uses GeometryReader so the image always fills the exact screen bounds
/// regardless of safe area insets or device size.
struct SplashView: View {
    let splashImage: UIImage?
    let primaryColor: Color
    let logoImage: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Always-present background (fills safe-area gaps, matches LaunchScreen) ──
                primaryColor

                if let splash = splashImage {
                    // ── Full-screen splash image ──────────────────────────────
                    Image(uiImage: splash)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                } else if let logo = logoImage {
                    // ── First-launch fallback: color bg + centered logo ───────
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                }
                // No globe icon — primaryColor handles the no-asset case cleanly
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}
