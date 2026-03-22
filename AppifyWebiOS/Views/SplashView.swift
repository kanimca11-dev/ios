import SwiftUI

/// Static full-screen splash shown while the WebView is loading.
struct SplashView: View {
    let splashImage: UIImage?
    let primaryColor: Color
    let logoImage: UIImage?

    var body: some View {
        if let splash = splashImage {
            // ── Full-screen splash (downloaded from config) ───────────────────
            Image(uiImage: splash)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        } else {
            // ── First-launch fallback: brand color background ─────────────────
            primaryColor
                .ignoresSafeArea()
                .overlay(
                    Group {
                        if let logo = logoImage {
                            Image(uiImage: logo)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 160, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        }
                    }
                )
        }
    }
}
