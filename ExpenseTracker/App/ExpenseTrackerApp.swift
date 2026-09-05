import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct ExpenseTrackerApp: App {
    @State private var isSignedIn = false
    @State private var signInError: String?

    init() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isSignedIn {
                    RootTabView()
                } else if let signInError {
                    VStack(spacing: 12) {
                        Text("Couldn't connect")
                            .font(.headline)
                        Text(signInError)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("Retry") {
                            self.signInError = nil
                            Task { await signInAnonymouslyIfNeeded() }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .task {
                await signInAnonymouslyIfNeeded()
            }
        }
    }

    // Firestore's security rules now require an authenticated request. The app
    // has no login screen, so this signs in anonymously behind the scenes —
    // no credentials, no UI, just a device-scoped identity Firestore accepts.
    //
    // Wrapped with a manual timeout: without this, a hung network call (or a
    // misconfigured Firebase Auth provider) leaves the app stuck on a spinner
    // forever with no visible error — which is exactly what happened the first
    // time this shipped.
    private func signInAnonymouslyIfNeeded() async {
        if Auth.auth().currentUser != nil {
            isSignedIn = true
            return
        }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await Auth.auth().signInAnonymously()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    throw TimeoutError()
                }
                try await group.next()
                group.cancelAll()
            }
            isSignedIn = true
        } catch is TimeoutError {
            signInError = "Sign-in timed out after 10 seconds. Check your network connection, or that Anonymous sign-in is enabled for this Firebase project (Firebase Console → Authentication → Sign-in method)."
        } catch {
            signInError = error.localizedDescription
        }
    }
}

private struct TimeoutError: Error {}
