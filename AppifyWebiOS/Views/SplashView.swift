import SwiftUI

/// Animated splash screen — mirrors Android's SplashScreen.kt
/// Shows pulsing rings, orbiting dot, loading dots, and brand logo.
struct SplashView: View {
    let primaryColor: Color
    let logoImage: UIImage?

    // Ring animations
    @State private var ring1Scale: CGFloat = 1.0
    @State private var ring1Opacity: Double = 0.5
    @State private var ring2Scale: CGFloat = 1.0
    @State private var ring2Opacity: Double = 0.3

    // Orbit dot
    @State private var orbitAngle: Double = 0

    // Loading dots
    @State private var dot1Scale: CGFloat = 0.5
    @State private var dot2Scale: CGFloat = 0.5
    @State private var dot3Scale: CGFloat = 0.5

    // Logo entrance
    @State private var logoScale: CGFloat = 0.3
    @State private var logoOpacity: Double = 0

    var body: some View {
        ZStack {
            // ── Background radial gradient ────────────────────────────────────
            RadialGradient(
                colors: [primaryColor.opacity(0.3), Color.black],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()

            // ── Pulsing ring 1 ────────────────────────────────────────────────
            Circle()
                .stroke(primaryColor.opacity(ring1Opacity), lineWidth: 2)
                .frame(width: 220, height: 220)
                .scaleEffect(ring1Scale)

            // ── Pulsing ring 2 ────────────────────────────────────────────────
            Circle()
                .stroke(primaryColor.opacity(ring2Opacity), lineWidth: 1.5)
                .frame(width: 280, height: 280)
                .scaleEffect(ring2Scale)

            // ── Orbiting shimmer dot ──────────────────────────────────────────
            Circle()
                .fill(primaryColor.opacity(0.9))
                .frame(width: 10, height: 10)
                .offset(x: 115)
                .rotationEffect(.degrees(orbitAngle))

            // ── Logo ──────────────────────────────────────────────────────────
            Group {
                if let img = logoImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 280, height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 56, style: .continuous))
                } else {
                    ZStack {
                        Circle()
                            .fill(primaryColor.opacity(0.25))
                            .frame(width: 280, height: 280)
                        Image(systemName: "globe")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 140)
                            .foregroundColor(primaryColor)
                    }
                }
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)

            // ── Loading dots at bottom ────────────────────────────────────────
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    loadingDot(scale: dot1Scale)
                    loadingDot(scale: dot2Scale)
                    loadingDot(scale: dot3Scale)
                }
                .padding(.bottom, 80)
            }
        }
        .onAppear { startAnimations() }
    }

    private func loadingDot(scale: CGFloat) -> some View {
        Circle()
            .fill(primaryColor)
            .frame(width: 10, height: 10)
            .scaleEffect(scale)
    }

    private func startAnimations() {
        // Logo spring entrance
        withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) {
            logoScale   = 1.0
            logoOpacity = 1.0
        }

        // Ring 1 pulse (infinite)
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            ring1Scale   = 1.25
            ring1Opacity = 0.0
        }

        // Ring 2 pulse (offset phase)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                ring2Scale   = 1.35
                ring2Opacity = 0.0
            }
        }

        // Orbit dot rotation
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            orbitAngle = 360
        }

        // Loading dots cascade
        animateDot(delay: 0.0)  { dot1Scale = $0 }
        animateDot(delay: 0.2)  { dot2Scale = $0 }
        animateDot(delay: 0.4)  { dot3Scale = $0 }
    }

    private func animateDot(delay: Double, assign: @escaping (CGFloat) -> Void) {
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                assign(1.0)
            }
        }
    }
}
