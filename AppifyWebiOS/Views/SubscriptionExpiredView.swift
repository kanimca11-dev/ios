import SwiftUI

/// Animated subscription-expired screen — mirrors Android's SubscriptionExpiredScreen.kt
struct SubscriptionExpiredView: View {
    let message: String
    let primaryColor: Color
    var onRetry: (() -> Void)? = nil

    // Entrance animation
    @State private var appeared = false

    // Breathing lock icon
    @State private var lockScale: CGFloat = 1.0

    // Pulsing rings
    @State private var ring1Scale: CGFloat = 1.0
    @State private var ring1Opacity: Double = 0.6
    @State private var ring2Scale: CGFloat = 1.0
    @State private var ring2Opacity: Double = 0.4

    var body: some View {
        ZStack {
            // ── Background ────────────────────────────────────────────────────
            RadialGradient(
                colors: [primaryColor.opacity(0.2), Color.black],
                center: .center,
                startRadius: 30,
                endRadius: 400
            )
            .ignoresSafeArea()

            // ── Pulsing rings behind icon ─────────────────────────────────────
            Circle()
                .stroke(primaryColor.opacity(ring1Opacity), lineWidth: 2)
                .frame(width: 180, height: 180)
                .scaleEffect(ring1Scale)

            Circle()
                .stroke(primaryColor.opacity(ring2Opacity), lineWidth: 1.5)
                .frame(width: 240, height: 240)
                .scaleEffect(ring2Scale)

            // ── Main content ──────────────────────────────────────────────────
            VStack(spacing: 28) {
                // Lock icon with breathing animation
                ZStack {
                    Circle()
                        .fill(primaryColor.opacity(0.2))
                        .frame(width: 100, height: 100)
                    Image(systemName: "lock.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .foregroundColor(primaryColor)
                }
                .scaleEffect(lockScale)

                VStack(spacing: 12) {
                    Text("Subscription Expired")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 32)
                }

                // Support card
                VStack(spacing: 8) {
                    Text("Need help?")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Link("Contact Support",
                         destination: URL(string: "mailto:support@appifyweb24.com")!)
                        .font(.subheadline.bold())
                        .foregroundColor(primaryColor)
                }
                .padding()
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)

                // Retry button
                Button(action: { onRetry?() }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(primaryColor)
                    .cornerRadius(10)
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 40)
        }
        .onAppear { startAnimations() }
    }

    private func startAnimations() {
        // Entrance
        withAnimation(.easeOut(duration: 0.6)) { appeared = true }

        // Breathing lock
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            lockScale = 1.12
        }

        // Ring 1 pulse
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            ring1Scale   = 1.3
            ring1Opacity = 0.0
        }
        // Ring 2 pulse (offset)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                ring2Scale   = 1.45
                ring2Opacity = 0.0
            }
        }
    }
}
