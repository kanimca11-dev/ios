import SwiftUI
import LocalAuthentication

/// Biometric / device-credential lock screen — mirrors Android's BiometricLockScreen.kt
struct BiometricLockView: View {
    let primaryColor: Color
    var onUnlocked: () -> Void

    @State private var errorMessage: String? = nil
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                // Lock icon
                ZStack {
                    Circle()
                        .fill(primaryColor.opacity(0.15))
                        .frame(width: 110, height: 110)
                    Image(systemName: "lock.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .foregroundColor(primaryColor)
                }

                VStack(spacing: 8) {
                    Text("Authentication Required")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text("Verify your identity to continue")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button(action: authenticate) {
                    HStack(spacing: 10) {
                        Image(systemName: biometricIcon)
                        Text(isAuthenticating ? "Verifying…" : "Unlock")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 14)
                    .background(isAuthenticating ? primaryColor.opacity(0.5) : primaryColor)
                    .cornerRadius(10)
                }
                .disabled(isAuthenticating)
            }
        }
        .onAppear { authenticate() }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private var biometricIcon: String {
        let ctx = LAContext()
        var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
            return ctx.biometryType == .faceID ? "faceid" : "touchid"
        }
        return "lock.open.fill"
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage     = nil

        let ctx    = LAContext()
        var err: NSError?
        let policy: LAPolicy = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        ctx.evaluatePolicy(policy, localizedReason: "Unlock the app") { success, error in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    onUnlocked()
                } else {
                    errorMessage = error?.localizedDescription ?? "Authentication failed"
                }
            }
        }
    }
}
