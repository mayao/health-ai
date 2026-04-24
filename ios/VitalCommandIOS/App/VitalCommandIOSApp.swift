import SwiftUI

@main
struct VitalCommandIOSApp: App {
    @StateObject private var settings = AppSettingsStore()
    @StateObject private var authManager = AuthManager()
    @StateObject private var autoSync = AutoSyncCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
    @AppStorage("vital-command.has-seen-onboarding") private var hasSeenOnboarding = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if authManager.isLoading || showSplash {
                        launchScreen
                    } else if authManager.isAuthenticated {
                        MainTabView()
                            .environmentObject(settings)
                            .environmentObject(authManager)
                            .environmentObject(autoSync)
                    } else if hasSeenOnboarding {
                        LoginScreen()
                            .environmentObject(settings)
                            .environmentObject(authManager)
                    } else {
                        IntroOnboardingScreen(hasSeenOnboarding: $hasSeenOnboarding)
                    }
                }
            }
            .preferredColorScheme(.light)
            .onAppear {
                // Sync token immediately (before any child .task fires)
                settings.authToken = authManager.token
            }
            .onChange(of: authManager.token) {
                settings.authToken = authManager.token
            }
            .onChange(of: authManager.currentUser?.id) {
                // Force feature pages to reload when account context changes.
                settings.markHealthDataChanged()
            }
            .onChange(of: settings.serverURLString) {
                // When server changes, try re-authenticating on the new server
                Task {
                    guard authManager.isAuthenticated else { return }
                    await authManager.rebindSessionAfterServerSwitch(using: settings)
                }
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active, authManager.isAuthenticated {
                    Task {
                        settings.authToken = authManager.token
                        let previousUserId = authManager.currentUser?.id
                        await authManager.validateSession(using: settings)
                        let currentUserId = authManager.currentUser?.id
                        if previousUserId != currentUserId {
                            settings.markHealthDataChanged()
                        }
                        autoSync.syncIfNeeded(settings: settings)
                    }
                }
            }
            .task {
                // Start auth in parallel with minimum splash duration
                let splashStart = Date()
                settings.authToken = authManager.token
                await authManager.validateSession(using: settings)
                // Auto-sync on first launch
                if authManager.isAuthenticated {
                    autoSync.syncIfNeeded(settings: settings)
                }
                // Ensure splash shows for at least 2.5 seconds
                let elapsed = Date().timeIntervalSince(splashStart)
                let remaining = 2.5 - elapsed
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                }
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }

    private var launchScreen: some View {
        ZStack {
            // Exact background color sampled from SplashBackground image edges
            Color(red: 0.106, green: 0.482, blue: 0.541)
                .ignoresSafeArea()
            Image("SplashBackground")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(.horizontal, 16)
        }
    }
}
