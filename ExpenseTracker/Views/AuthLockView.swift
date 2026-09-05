import SwiftUI
import LocalAuthentication

// Wraps `content` behind a Face ID / Touch ID / device passcode prompt.
// Locks again whenever the app leaves the foreground, so switching apps or
// locking the phone re-locks this content the next time it's viewed.
struct AuthLockView<Content: View>: View {
    @State private var isUnlocked = false
    @State private var authError: String?
    @Environment(\.scenePhase) private var scenePhase
    let reason: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if isUnlocked {
                content()
            } else {
                lockedPlaceholder
            }
        }
        .onAppear {
            if !isUnlocked { authenticate() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                isUnlocked = false
            }
        }
    }

    private var lockedPlaceholder: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Palette.mutedText)
                Text("Locked")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                if let authError {
                    Text(authError)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.mutedText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Button("Unlock") { authenticate() }
                    .font(.system(size: 14, weight: .semibold))
            }
        }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode or biometrics set up on this device at all — fail
            // open rather than permanently locking someone out with no way in.
            isUnlocked = true
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evaluateError in
            DispatchQueue.main.async {
                isUnlocked = success
                authError = success ? nil : (evaluateError?.localizedDescription ?? "Authentication failed")
            }
        }
    }
}
