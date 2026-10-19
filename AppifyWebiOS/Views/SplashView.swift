import SwiftUI

/// Exact visual continuation of the static OS launch screen, without a second design/animation.
/// iOS owns the real launch screen; it cannot be retained by application code.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackgroundColor").ignoresSafeArea()
            Image("LaunchLogo").resizable().scaledToFit().frame(width: 128, height: 128)
        }
        .allowsHitTesting(true)
        .accessibilityLabel("Opening app")
    }
}
