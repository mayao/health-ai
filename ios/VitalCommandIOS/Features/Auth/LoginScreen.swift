import SwiftUI
import AuthenticationServices
import VitalCommandMobileCore

struct LoginScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var authManager: AuthManager

    @StateObject private var discovery = ServerDiscoveryService()
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var didAttemptAutoLogin = false
    @State private var showServerConfig = false
    @State private var serverReachable: Bool?
    @State private var isCheckingServer = false

    private let tealColor = Color(hex: "#0f766e") ?? .teal
    private let darkText = Color(red: 0.05, green: 0.13, blue: 0.2)

    var body: some View {
        ZStack {
            loginBackground
            VStack(spacing: 0) {
                Spacer().frame(height: 72)
                logoSection
                    .padding(.bottom, 48)
                loginCard
                    .padding(.horizontal, 24)
                Spacer()
                bottomInfo
            }
        }
        .task {
            guard !didAttemptAutoLogin else { return }
            didAttemptAutoLogin = true
            await checkServerReachability()
            if serverReachable != true {
                await discoverReachableServerIfNeeded()
            }
            if serverReachable == true, !authManager.isAuthenticated {
                await directLogin()
            }
        }
        .onChange(of: settings.serverURLString) {
            serverReachable = nil
            errorMessage = nil
            Task {
                await checkServerReachability()
                if serverReachable != true {
                    await discoverReachableServerIfNeeded()
                }
            }
        }
        .sheet(isPresented: $showServerConfig) {
            LoginServerConfigSheet(serverReachable: $serverReachable)
                .environmentObject(settings)
        }
    }

    // MARK: - Sub-views

    private var loginBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.99, blue: 0.97),
                Color(red: 0.93, green: 0.96, blue: 0.94),
                Color.white
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var logoSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tealColor, Color(hex: "#0d5263") ?? .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)
                    .shadow(color: tealColor.opacity(0.3), radius: 20, y: 10)

                Image(systemName: "heart.text.clipboard")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text("Health AI")
                    .font(.title.weight(.bold))
                    .foregroundColor(darkText)

                Text("把健康数据整理成你看得懂的趋势和建议")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .onLongPressGesture(minimumDuration: 1.2) {
            showServerConfig = true
        }
    }

    private var loginCard: some View {
        VStack(spacing: 24) {
            welcomeSection
            serverStatusBanner
            errorBanner
            deviceEntryButton
            appleLoginButton
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(tealColor.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 20, y: 10)
    }

    private var welcomeSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 44))
                .foregroundStyle(tealColor)
                .padding(.bottom, 4)

            Text("欢迎使用 Health AI")
                .font(.title3.weight(.semibold))
                .foregroundColor(darkText)

            Text("默认推荐先使用本机快速进入，确保联网后可秒级登录；Apple 账号绑定可在后续设置里完成。\nHealth AI 仅用于健康整理、趋势解释与生活方式建议，不替代医生诊断。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    private var appleLoginButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(.black)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.black)
                    .overlay {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                                .font(.headline)
                            Text("使用 Apple 登录")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                    }
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(isLoggingIn || serverReachable == false)

            if serverReachable == false {
                Text("当前暂时连不到登录服务。你可以稍后再试，或先使用本机快速进入。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var serverStatusBanner: some View {
        if let reachable = serverReachable {
            HStack(spacing: 8) {
                Circle()
                    .fill(reachable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(reachable ? "登录服务已连接" : "当前网络下登录服务暂时不可用")
                    .font(.caption)
                    .foregroundStyle(reachable ? Color.secondary : Color.red.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                (reachable ? Color.green : Color.red).opacity(0.06),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.8))
                    Text("你可以直接重试，或先使用本机快速进入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var deviceEntryButton: some View {
        Button {
            Task { await directLogin() }
        } label: {
            HStack(spacing: 10) {
                if isLoggingIn {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "iphone")
                        .font(.title3)
                }
                Text("使用本机快速进入")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [tealColor, Color(hex: "#0d5263") ?? .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .shadow(color: tealColor.opacity(0.3), radius: 12, y: 6)
        }
        .disabled(isLoggingIn)
    }

    private var bottomInfo: some View {
        VStack(spacing: 6) {
            Text("继续使用即表示你理解：Health AI 提供的是健康管理支持，不是医疗诊断。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Server check

    private func checkServerReachability() async {
        isCheckingServer = true
        defer { isCheckingServer = false }
        serverReachable = await isServerReachable(settings.trimmedServerURLString)
    }

    private func isServerReachable(_ rawURL: String) async -> Bool {
        let base = rawURL.hasSuffix("/") ? String(rawURL.dropLast()) : rawURL
        guard let url = URL(string: "\(base)/api/auth/me") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.httpMethod = "GET"
        request.setValue("HealthAI-iOS-LoginReachability", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return (200...499).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    private func discoverReachableServerIfNeeded() async {
        let currentURL = normalizedServerURL(settings.trimmedServerURLString)
        var preferredCandidates: [String] = []
        var seenCandidates = Set<String>()

        for url in AppSettingsStore.builtInServers.map(\.url) + settings.savedServers.map(\.url) {
            guard seenCandidates.insert(url).inserted else { continue }
            preferredCandidates.append(url)
        }

        let normalizedPreferredCandidates = preferredCandidates
            .map(normalizedServerURL)
            .filter { !$0.isEmpty && $0 != currentURL }
        let reachablePreferred = await reachableServerCandidates(normalizedPreferredCandidates)
        if let matchedPreferred = normalizedPreferredCandidates.first(where: { reachablePreferred.contains($0) }) {
            settings.serverURLString = matchedPreferred
            serverReachable = true
            return
        }

        discovery.startScanning()
        defer { discovery.stopScanning() }
        await discovery.scanSubnet()

        let discoveredURLs = discovery.discoveredServers.map(\.urlString)
        settings.rememberDiscoveredServerURLs(discoveredURLs)

        let normalizedDiscovered = discoveredURLs
            .map(normalizedServerURL)
            .filter { !$0.isEmpty && $0 != currentURL }
        let reachableDiscovered = await reachableServerCandidates(normalizedDiscovered)
        if let matchedDiscovered = normalizedDiscovered.first(where: { reachableDiscovered.contains($0) }) {
            settings.serverURLString = matchedDiscovered
            serverReachable = true
            return
        }
    }

    private func reachableServerCandidates(_ candidates: [String]) async -> Set<String> {
        await withTaskGroup(of: (String, Bool).self, returning: Set<String>.self) { group in
            for candidate in candidates {
                group.addTask {
                    let reachable = await isServerReachable(candidate)
                    return (candidate, reachable)
                }
            }

            var reachableCandidates = Set<String>()
            for await (candidate, reachable) in group {
                if reachable {
                    reachableCandidates.insert(candidate)
                }
            }

            return reachableCandidates
        }
    }

    private func normalizedServerURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            return ""
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/"
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString ?? trimmed
    }

    // MARK: - Login methods

    private func directLogin() async {
        errorMessage = nil
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            try await authManager.deviceAutoLogin(using: settings)
            serverReachable = true
        } catch {
            if await settings.recoverToAvailablePublicServer(after: error) {
                do {
                    try await authManager.deviceAutoLogin(using: settings)
                    serverReachable = true
                    return
                } catch {
                    serverReachable = false
                    authManager.enterOfflineMode()
                    return
                }
            }

            serverReachable = false
            authManager.enterOfflineMode()
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .failure(error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            errorMessage = friendlyAppleAuthorizationMessage(for: error)

        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Apple 登录返回格式无效，请重试。"
                return
            }

            Task {
                errorMessage = nil
                isLoggingIn = true
                defer { isLoggingIn = false }

                do {
                    let payload = try AppleAuthorizationPayload(credential: credential)
                    try await authManager.signInWithApple(payload, using: settings)
                    serverReachable = true
                } catch {
                    if await settings.recoverToAvailablePublicServer(after: error) {
                        do {
                            let payload = try AppleAuthorizationPayload(credential: credential)
                            try await authManager.signInWithApple(payload, using: settings)
                            serverReachable = true
                            return
                        } catch {
                            errorMessage = friendlyAppleSignInMessage(for: error)
                            if case let HealthAPIClientError.server(statusCode, _) = error, statusCode >= 500 {
                                serverReachable = false
                            }
                            return
                        }
                    }

                    errorMessage = friendlyAppleSignInMessage(for: error)
                    if case let HealthAPIClientError.server(statusCode, _) = error, statusCode >= 500 {
                        serverReachable = false
                    }
                }
            }
        }
    }

    private func friendlyAppleAuthorizationMessage(for error: Error) -> String {
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .failed:
                return "Apple 授权没有完成，请重新尝试。"
            case .invalidResponse:
                return "Apple 授权返回无效，请重新尝试。"
            case .notHandled:
                return "Apple 授权暂时不可用，请稍后重试。"
            default:
                break
            }
        }

        return "Apple 授权没有完成，请重新尝试。"
    }

    private func friendlyAppleSignInMessage(for error: Error) -> String {
        if case let HealthAPIClientError.server(statusCode, _) = error {
            if statusCode >= 500 {
                return "Apple 登录服务暂时不可用，请稍后重试或先使用本机快速进入。"
            }
            if statusCode == 401 {
                return "Apple 授权已失效或返回无效，请重新尝试。"
            }
        }

        if case let HealthAPIClientError.transport(message) = error {
            if message.isEmpty == false {
                return "当前无法连接登录服务，请检查网络后重试，或先使用本机快速进入。"
            }
        }

        return "Apple 登录暂时不可用，请稍后重试或先使用本机快速进入。"
    }
}

private struct IntroSlide: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let body: String
    let highlights: [String]
}

struct IntroOnboardingScreen: View {
    @Binding var hasSeenOnboarding: Bool
    @State private var selection = 0
    @State private var iconPulse = false
    @State private var cardFloat = false

    private let slides: [IntroSlide] = [
        IntroSlide(
            id: 0,
            icon: "waveform.path.ecg.text.page.fill",
            title: "把健康数据整理成你看得懂的结论",
            body: "Health AI 会把体检、运动、体重、睡眠和上传文件整理成连续趋势，帮助你更快看清目前状态。",
            highlights: ["不是医疗诊断工具", "更适合日常管理与复查跟踪", "重点看变化而不是单次波动"]
        ),
        IntroSlide(
            id: 1,
            icon: "brain.head.profile",
            title: "首页和 AI 洞察先帮你抓重点",
            body: "首页会优先告诉你最近有哪些积极变化、哪些地方还需要继续观察，AI 洞察更偏向解释趋势和下一步建议。",
            highlights: ["优先看核心变化", "解释趋势，不替代医生判断", "建议会结合你已有数据生成"]
        ),
        IntroSlide(
            id: 2,
            icon: "chart.line.uptrend.xyaxis.circle.fill",
            title: "趋势、报告和数据上传各有分工",
            body: "趋势页适合连续观察，报告页适合回顾阶段总结，数据页适合上传体检/报告或同步 Apple 健康。",
            highlights: ["趋势页看连续变化", "报告页看周报/月报", "数据页负责上传与同步"]
        ),
        IntroSlide(
            id: 3,
            icon: "lock.shield.fill",
            title: "你的隐私会被认真对待",
            body: "你可以同步 Apple 健康，也可以手动上传文件。若需要导出或删除数据，可通过邮件向 Health AI团队 提交申请。",
            highlights: ["支持 Apple 健康同步", "不出售个人健康信息", "隐私申请邮箱：yao.ma@qq.com"]
        )
    ]

    private let tealColor = Color(hex: "#0f766e") ?? .teal

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.99, blue: 0.97),
                    Color(red: 0.93, green: 0.96, blue: 0.94),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .hueRotation(.degrees(iconPulse ? 2 : -2))
            .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: iconPulse)

            VStack(spacing: 24) {
                Spacer().frame(height: 40)

                TabView(selection: $selection) {
                    ForEach(slides) { slide in
                        VStack(spacing: 22) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [tealColor, Color(hex: "#0d5263") ?? .cyan],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 96, height: 96)
                                    .shadow(color: tealColor.opacity(0.25), radius: 18, y: 10)
                                    .scaleEffect(iconPulse ? 1.04 : 0.96)

                                Image(systemName: slide.icon)
                                    .font(.system(size: 38))
                                    .foregroundStyle(.white)
                            }
                            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: iconPulse)

                            VStack(spacing: 12) {
                                Text(slide.title)
                                    .font(.title2.weight(.bold))
                                    .multilineTextAlignment(.center)

                                Text(slide.body)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(4)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(slide.highlights, id: \.self) { item in
                                    Label(item, systemImage: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .offset(y: cardFloat ? -4 : 4)
                            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: cardFloat)
                        }
                        .padding(.horizontal, 28)
                        .tag(slide.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 520)
                .contentShape(Rectangle())
                .onTapGesture {
                    advanceSlide()
                }

                HStack(spacing: 8) {
                    ForEach(0..<slides.count, id: \.self) { index in
                        Capsule()
                            .fill(index == selection ? tealColor : Color.white.opacity(0.75))
                            .frame(width: index == selection ? 22 : 8, height: 8)
                            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: selection)
                    }
                }

                Button(selection == slides.count - 1 ? "开始使用" : "下一步") {
                    advanceSlide()
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [tealColor, Color(hex: "#0d5263") ?? .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .padding(.horizontal, 28)

                Button("稍后再看") {
                    hasSeenOnboarding = true
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Spacer(minLength: 24)
            }
        }
        .onAppear {
            iconPulse = true
            cardFloat = true
        }
    }

    private func advanceSlide() {
        if selection == slides.count - 1 {
            hasSeenOnboarding = true
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                selection += 1
            }
        }
    }
}

// MARK: - Server Config Sheet (accessible from Login screen)

struct LoginServerConfigSheet: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    @Binding var serverReachable: Bool?

    @State private var editingURL: String = ""
    @State private var checkingServers: Set<String> = []
    @State private var serverStatuses: [String: Bool] = [:]

    private let tealColor = Color(hex: "#0f766e") ?? .teal

    var body: some View {
        NavigationStack {
            Form {
                currentServerSection
                quickSwitchSection
                checkAllSection
            }
            .navigationTitle("服务器设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                editingURL = settings.trimmedServerURLString
                Task { await checkAllServers() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var currentServerSection: some View {
        Section("当前服务器") {
            HStack {
                TextField(AppSettingsStore.currentRemoteServerURL, text: $editingURL)
                    .appURLTextEntry()

                if checkingServers.contains(editingURL) {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            HStack {
                Button("连接") {
                    settings.serverURLString = editingURL
                    Task { await checkServer(editingURL) }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(tealColor, in: Capsule())

                Button("保存到列表") {
                    settings.serverURLString = editingURL
                    settings.saveCurrentServer()
                }
                .font(.subheadline)
                .foregroundStyle(tealColor)
            }
        }
    }

    private var quickSwitchSection: some View {
        Section("快速切换") {
            ForEach(AppSettingsStore.builtInServers) { server in
                serverRow(name: server.name, url: server.url)
            }

            ForEach(settings.savedServers.filter { saved in
                !AppSettingsStore.builtInServers.map(\.url).contains(saved.url)
            }) { server in
                serverRow(name: server.name, url: server.url)
            }
        }
    }

    private var checkAllSection: some View {
        Section {
            Button("检测所有服务器") {
                Task { await checkAllServers() }
            }
            .font(.subheadline)
        } footer: {
            Text("默认推荐填写 https://app.wellai.online/。在公司局域网调试时，再切换到内网地址；不要填写 localhost 或 127.0.0.1。")
                .font(.caption2)
        }
    }

    @ViewBuilder
    private func serverRow(name: String, url: String) -> some View {
        Button {
            editingURL = url
            settings.serverURLString = url
            Task {
                await checkServer(url)
                dismiss()
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                serverStatusIndicator(for: url)

                if settings.trimmedServerURLString == url {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(tealColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func serverStatusIndicator(for url: String) -> some View {
        if checkingServers.contains(url) {
            ProgressView().scaleEffect(0.7)
        } else if let reachable = serverStatuses[url] {
            HStack(spacing: 4) {
                Circle()
                    .fill(reachable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(reachable ? "在线" : "离线")
                    .font(.caption2)
                    .foregroundStyle(reachable ? .green : .red)
            }
        }
    }

    private func checkServer(_ urlString: String) async {
        checkingServers.insert(urlString)
        defer { checkingServers.remove(urlString) }

        let healthURL = urlString.hasSuffix("/")
            ? urlString + "api/health"
            : urlString + "/api/health"

        guard let url = URL(string: healthURL) else {
            serverStatuses[urlString] = false
            if settings.trimmedServerURLString == urlString {
                serverReachable = false
            }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let reachable = (response as? HTTPURLResponse).map { (200...499).contains($0.statusCode) } ?? false
            serverStatuses[urlString] = reachable
            if settings.trimmedServerURLString == urlString {
                serverReachable = reachable
            }
        } catch {
            serverStatuses[urlString] = false
            if settings.trimmedServerURLString == urlString {
                serverReachable = false
            }
        }
    }

    private func checkAllServers() async {
        let urls = Set(
            AppSettingsStore.builtInServers.map(\.url)
            + settings.savedServers.map(\.url)
            + [editingURL]
        )
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { await checkServer(url) }
            }
        }
    }
}
