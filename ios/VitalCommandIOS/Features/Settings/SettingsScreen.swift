import SwiftUI
import AuthenticationServices
import VitalCommandMobileCore

struct SettingsScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var discovery = ServerDiscoveryService()
    @State private var showLogoutConfirmation = false
    @State private var syncStatus: SyncStatusResponse?
    @State private var isSyncing = false
    @State private var syncError: String?
    @State private var syncMessage: String?
    @State private var serverStatuses: [String: Bool] = [:]
    @State private var checkingServers: Set<String> = []
    @State private var modelStatus: AIModelStatusResponse?
    @State private var isLoadingModelStatus = false
    @State private var isSwitchingProvider = false
    @State private var availableUsers: [UserListItem] = []
    @State private var isLoadingUsers = false
    @State private var currentUserId: String?
    @State private var isSwitchingUser = false
    @State private var isCreatingTestUser = false
    @State private var canSwitchUser = false
    @State private var isLinkingApple = false
    @State private var appleLinkMessage: String?
    @State private var isAdvancedSettingsExpanded = false

    private let tealColor = Color(hex: "#0f766e") ?? .teal

    var body: some View {
        Form {
            if let user = authManager.currentUser {
                accountInfoSection(user)
            }

            if let user = authManager.currentUser {
                accountSecuritySection(user)
            }

            Section("使用说明") {
                NavigationLink {
                    UsageGuideScreen()
                } label: {
                    settingsDestinationRow(
                        title: "如何使用 Health AI",
                        subtitle: "查看首页、AI 洞察、趋势、报告和数据上传的完整说明。",
                        icon: "book.pages.fill"
                    )
                }

                Text("建议第一次使用时先看一遍说明，再开始同步 Apple 健康或上传文件。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("协议与隐私") {
                NavigationLink {
                    LegalDocumentScreen(document: .terms)
                } label: {
                    settingsDestinationRow(
                        title: "用户协议",
                        subtitle: "了解 Health AI 的服务说明、使用边界与账号规则。",
                        icon: "doc.text.fill"
                    )
                }

                NavigationLink {
                    LegalDocumentScreen(document: .privacy)
                } label: {
                    settingsDestinationRow(
                        title: "隐私政策",
                        subtitle: "查看我们会收集什么数据、如何使用以及如何保护你的隐私。",
                        icon: "lock.doc.fill"
                    )
                }

                NavigationLink {
                    PrivacyDataRequestScreen(
                        supportEmail: settings.supportEmailAddress,
                        supportTeamName: settings.supportTeamName
                    )
                } label: {
                    settingsDestinationRow(
                        title: "隐私与数据申请",
                        subtitle: "需要导出或删除数据时，可通过邮件向 \(settings.supportTeamName) 提交申请。",
                        icon: "envelope.badge.fill"
                    )
                }
            }

            Section("关于") {
                settingsDestinationRow(
                    title: "应用版本",
                    subtitle: "Version \(appVersionString)",
                    icon: "info.circle.fill"
                )
                settingsDestinationRow(
                    title: "构建号",
                    subtitle: appBuildString,
                    icon: "hammer.fill"
                )
                settingsDestinationRow(
                    title: "支持邮箱",
                    subtitle: settings.supportEmailAddress,
                    icon: "envelope.fill"
                )
            }

            if currentUserCapabilities.canSeeAdvancedSettings {
                Section("高级设置") {
                    DisclosureGroup(isExpanded: $isAdvancedSettingsExpanded) {
                        VStack(alignment: .leading, spacing: 22) {
                            modelSelectionPanel
                            Divider()
                            serverAddressPanel
                            Divider()
                            quickSwitchPanel
                            Divider()
                            discoveryPanel
                            Divider()
                            syncPanel
                        }
                        .padding(.top, 12)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("网络、同步与诊断")
                                .font(.subheadline.weight(.semibold))
                            Text("普通使用一般不需要调整，排查连接或同步问题时再展开。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showLogoutConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("退出登录")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            Task {
                await loadSyncStatus()
                await checkAllServers()
                await loadModelStatus()
            }
        }
        .onReceive(discovery.$discoveredServers) { servers in
            settings.rememberDiscoveredServerURLs(servers.map(\.urlString))
        }
        .onDisappear { discovery.stopScanning() }
        .navigationTitle("设置")
        .alert("确认退出？", isPresented: $showLogoutConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出登录", role: .destructive) {
                authManager.logout()
            }
        } message: {
            Text("退出后需要重新验证身份登录")
        }
    }

    private var currentUserCapabilities: UserCapabilities {
        authManager.currentUser?.capabilities ?? UserCapabilities()
    }

    private var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知版本"
    }

    private var appBuildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知构建"
    }

    private func accountInfoSection(_ user: UserInfo) -> some View {
        Section("账号信息") {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#0f766e") ?? .teal, Color(hex: "#0d5263") ?? .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Text(String(user.displayName.prefix(1)))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName)
                        .font(.subheadline.weight(.semibold))
                    if let phone = user.phoneNumber {
                        Text(maskPhoneNumber(phone))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let email = user.email, email.isEmpty == false {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)

            if !user.authProviders.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(user.authProviders) { provider in
                            StatusBadge(
                                text: providerLabel(provider.provider),
                                tint: provider.provider == .apple ? .black : (provider.provider == .phone ? .blue : tealColor)
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func accountSecuritySection(_ user: UserInfo) -> some View {
        Section("账号安全") {
            if user.hasAppleLinked {
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                        .foregroundStyle(.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple 账号已绑定")
                            .font(.subheadline.weight(.medium))
                        Text(user.email ?? "后续可直接使用 Apple 登录当前账号")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("绑定 Apple 后，你在不同设备或不同网络节点上登录时会更稳定，也更不容易出现账号分裂。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleLink(result)
                }
                .signInWithAppleButtonStyle(.black)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black)
                        .overlay {
                            HStack(spacing: 8) {
                                Image(systemName: "apple.logo")
                                    .font(.subheadline.weight(.semibold))
                                Text("继续使用 Apple 绑定")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                        }
                        .allowsHitTesting(false)
                }
                .frame(height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(isLinkingApple)

                if isLinkingApple {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("正在绑定 Apple 账号...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let appleLinkMessage {
                Text(appleLinkMessage)
                    .font(.caption)
                    .foregroundStyle(user.hasAppleLinked ? .green : .secondary)
            }
        }
    }

    private func settingsDestinationRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tealColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var modelSelectionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI 模型选择")
                .font(.subheadline.weight(.semibold))

            if isLoadingModelStatus && modelStatus == nil {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("正在检测...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let status = modelStatus {
                ForEach(status.providers) { provider in
                    Button {
                        guard provider.isConfigured, !isSwitchingProvider else { return }
                        Task { await switchProvider(to: provider.name) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: provider.isPrimary && provider.isConfigured ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(provider.isPrimary && provider.isConfigured ? tealColor : (provider.isConfigured ? Color.secondary : Color.gray.opacity(0.3)))
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(provider.label)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(provider.isConfigured ? .primary : .tertiary)
                                    if provider.isPrimary && provider.isConfigured {
                                        Text("使用中")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(tealColor, in: Capsule())
                                    }
                                }
                                Text(provider.model ?? "未配置")
                                    .font(.caption)
                                    .foregroundStyle(provider.model == nil ? .tertiary : .secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!provider.isConfigured)
                }
            } else {
                Button("检测 AI 模型") {
                    Task { await loadModelStatus() }
                }
                .font(.subheadline)
            }

            Text("这里只影响当前账号的 AI 优先模型。普通使用时保持默认即可。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var serverAddressPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("服务地址")
                .font(.subheadline.weight(.semibold))

            HStack {
                TextField(AppSettingsStore.currentRemoteServerURL, text: $settings.serverURLString)
                    .appURLTextEntry()

                if checkingServers.contains(settings.trimmedServerURLString) {
                    ProgressView().scaleEffect(0.7)
                } else if let reachable = serverStatuses[settings.trimmedServerURLString] {
                    Circle()
                        .fill(reachable ? .green : .red)
                        .frame(width: 10, height: 10)
                }
            }

            HStack(spacing: 12) {
                Button("检测连接") {
                    Task { await checkServer(settings.trimmedServerURLString) }
                }
                Button("保存当前服务器") {
                    settings.saveCurrentServer()
                }
            }
            .buttonStyle(.bordered)

            Text("默认推荐 \(AppSettingsStore.currentRemoteServerURL)。需要排查网络时再切换到其他地址。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var quickSwitchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快速切换")
                .font(.subheadline.weight(.semibold))

            ForEach(AppSettingsStore.builtInServers) { server in
                serverSwitchRow(name: server.name, url: server.url)
            }

            ForEach(settings.savedServers.filter { saved in
                !AppSettingsStore.builtInServers.map(\.url).contains(saved.url)
            }) { server in
                serverSwitchRow(name: server.name, url: server.url)
            }

            Button {
                Task { await checkAllServers() }
            } label: {
                Label("检测所有服务器", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var discoveryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("局域网服务发现")
                .font(.subheadline.weight(.semibold))

            if discovery.isScanning {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("正在扫描局域网...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(discovery.discoveredServers) { server in
                Button {
                    settings.rememberDiscoveredServerURLs([server.urlString])
                    settings.serverURLString = server.urlString
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(server.isRecentlyActive ? .green : .orange)
                                    .frame(width: 8, height: 8)
                                Text(server.name)
                                    .font(.subheadline.weight(.medium))
                            }
                            Text(server.urlString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if settings.serverURLString == server.urlString {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if discovery.discoveredServers.isEmpty && !discovery.isScanning {
                Text("未发现局域网服务")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                if discovery.isScanning {
                    discovery.stopScanning()
                } else {
                    discovery.startScanning()
                    Task { await discovery.scanSubnet() }
                }
            } label: {
                Label(
                    discovery.isScanning ? "停止扫描" : "扫描局域网",
                    systemImage: discovery.isScanning ? "stop.circle" : "antenna.radiowaves.left.and.right"
                )
            }
        }
    }

    private var syncPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("数据同步")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                Circle()
                    .fill(syncStatusColor)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(syncStatusText)
                        .font(.subheadline.weight(.medium))
                    if let status = syncStatus {
                        Text("\(status.peers.count) 个节点")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let status = syncStatus, !status.peers.isEmpty {
                ForEach(status.peers) { peer in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(peer.name)
                                .font(.caption.weight(.medium))
                            Text(peer.url)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let lastSync = peer.lastSyncAt {
                            Text(formatRelativeTime(lastSync))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("未同步")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            if let syncMessage {
                Text(syncMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if let error = syncError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await triggerManualSync() }
            } label: {
                HStack {
                    if isSyncing {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Label(isSyncing ? "同步中..." : "立即同步", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(isSyncing)
        }
    }

    private var developerAccountSection: some View {
        Section("内测账号管理") {
            if currentUserCapabilities.canSwitchAccounts {
                if isLoadingUsers {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("加载中...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if !availableUsers.isEmpty {
                    ForEach(availableUsers) { user in
                        Button {
                            guard user.id != currentUserId, !isSwitchingUser else { return }
                            Task { await performSwitchUser(to: user.id) }
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(user.id == currentUserId
                                            ? LinearGradient(colors: [tealColor, Color(hex: "#0d5263") ?? .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            : LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        )
                                        .frame(width: 36, height: 36)
                                    Text(String((user.displayName ?? "U").prefix(1)))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(user.id == currentUserId ? .white : .secondary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(user.displayName ?? "未命名")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if user.id == currentUserId {
                                            Text("当前")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(tealColor, in: Capsule())
                                        }
                                    }
                                    if let createdAt = user.createdAt {
                                        Text("创建于 \(createdAt.prefix(10))")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(user.id == currentUserId || isSwitchingUser)
                    }
                }
            }

            if currentUserCapabilities.canCreateTestUsers {
                Button {
                    Task { await createTestUser() }
                } label: {
                    HStack(spacing: 6) {
                        if isCreatingTestUser {
                            ProgressView().scaleEffect(0.7)
                        }
                        Label("创建测试账号", systemImage: "person.badge.plus")
                    }
                    .font(.subheadline)
                }
                .disabled(isCreatingTestUser)
            }

            Text("这里只用于主测试账号切换或生成新的内测账号。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Account Switching

    private func loadUsers() async {
        guard currentUserCapabilities.canSwitchAccounts || currentUserCapabilities.canCreateTestUsers else {
            availableUsers = []
            currentUserId = authManager.currentUser?.id
            canSwitchUser = false
            return
        }
        guard !isLoadingUsers else { return }
        isLoadingUsers = true
        defer { isLoadingUsers = false }
        do {
            let client = try settings.makeClient(token: authManager.token)
            let response = try await client.fetchUsers()
            availableUsers = response.users
            currentUserId = response.currentUserId
            canSwitchUser = currentUserCapabilities.canSwitchAccounts || (response.canSwitchUser ?? false)
        } catch {
            // Silently fail
        }
    }

    private func performSwitchUser(to targetUserId: String) async {
        guard !isSwitchingUser else { return }
        isSwitchingUser = true
        defer { isSwitchingUser = false }
        do {
            let client = try settings.makeClient(token: authManager.token)
            let response = try await client.switchUser(SwitchUserRequest(targetUserId: targetUserId))
            authManager.switchUser(token: response.token, user: response.user)
            settings.authToken = response.token
            currentUserId = response.user.id
            settings.markHealthDataChanged()
        } catch {
            // Could show error
        }
    }

    private func createTestUser() async {
        guard !isCreatingTestUser else { return }
        isCreatingTestUser = true
        defer { isCreatingTestUser = false }
        do {
            let client = try settings.makeClient(token: authManager.token)
            let randomDeviceId = UUID().uuidString
            let response = try await client.deviceLogin(
                DeviceLoginRequest(deviceId: randomDeviceId, deviceLabel: "测试账号")
            )
            // Switch to the new user
            authManager.switchUser(token: response.token, user: response.user)
            settings.authToken = response.token
            currentUserId = response.user.id
            settings.markHealthDataChanged()
            // Reload user list
            await loadUsers()
        } catch {
            // Could show error
        }
    }

    private func handleAppleLink(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .failure(error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            appleLinkMessage = error.localizedDescription

        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                appleLinkMessage = "Apple 绑定返回格式无效，请重试。"
                return
            }

            Task {
                isLinkingApple = true
                defer { isLinkingApple = false }

                do {
                    let payload = try AppleAuthorizationPayload(credential: credential)
                    try await authManager.linkAppleIdentity(payload, using: settings)
                    appleLinkMessage = "Apple 账号已成功绑定到当前 HealthAI 账号。"
                } catch {
                    appleLinkMessage = friendlyAppleLinkMessage(for: error)
                }
            }
        }
    }

    private func friendlyAppleLinkMessage(for error: Error) -> String {
        if case let HealthAPIClientError.server(statusCode, _) = error {
            if statusCode >= 500 {
                return "Apple 绑定服务暂时不可用，请稍后再试。"
            }
            if statusCode == 401 {
                return "Apple 授权已失效或返回无效，请重新尝试。"
            }
        }

        if error is HealthAPIClientError {
            return "当前无法完成 Apple 绑定，请稍后再试。"
        }

        return error.localizedDescription
    }

    private func providerLabel(_ provider: AuthProviderKind) -> String {
        switch provider {
        case .device:
            return "设备"
        case .phone:
            return "手机号"
        case .apple:
            return "Apple"
        }
    }

    // MARK: - AI Model Status

    private func loadModelStatus() async {
        guard !isLoadingModelStatus else { return }
        isLoadingModelStatus = true
        defer { isLoadingModelStatus = false }
        if let client = try? settings.makeClient(token: authManager.token) {
            modelStatus = try? await client.fetchModelStatus()
        }
    }

    private func switchProvider(to provider: String) async {
        guard !isSwitchingProvider else { return }
        isSwitchingProvider = true
        defer { isSwitchingProvider = false }
        if let client = try? settings.makeClient(token: authManager.token) {
            if let updated = try? await client.setPreferredProvider(provider) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    modelStatus = updated
                }
            }
        }
    }

    // MARK: - Server switch row

    @ViewBuilder
    private func serverSwitchRow(name: String, url: String) -> some View {
        Button {
            settings.serverURLString = url
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

                // Connection status
                if checkingServers.contains(url) {
                    ProgressView().scaleEffect(0.6)
                } else if let reachable = serverStatuses[url] {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(reachable ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(reachable ? "在线" : "离线")
                            .font(.caption2)
                            .foregroundStyle(reachable ? .green : .red)
                    }
                }

                // Active indicator
                if settings.trimmedServerURLString == url {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(tealColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Server health check

    private func checkServer(_ urlString: String) async {
        checkingServers.insert(urlString)
        defer { checkingServers.remove(urlString) }

        let healthURL = urlString.hasSuffix("/")
            ? urlString + "api/health"
            : urlString + "/api/health"

        guard let url = URL(string: healthURL) else {
            serverStatuses[urlString] = false
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let reachable = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            serverStatuses[urlString] = reachable
        } catch {
            serverStatuses[urlString] = false
        }
    }

    private func checkAllServers() async {
        let urls = Set(
            AppSettingsStore.builtInServers.map(\.url)
            + settings.savedServers.map(\.url)
            + [settings.trimmedServerURLString]
        )
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { await checkServer(url) }
            }
        }
    }

    private func maskPhoneNumber(_ phone: String) -> String {
        guard phone.count >= 7 else { return phone }
        let start = phone.prefix(3)
        let end = phone.suffix(4)
        return "\(start)****\(end)"
    }

    // MARK: - Sync helpers

    private var syncStatusColor: Color {
        guard let status = syncStatus else { return .gray }
        if status.peers.isEmpty { return .gray }
        let recentSync = status.recentLogs.first { $0.status == "success" }
        if recentSync != nil { return .green }
        return .orange
    }

    private var syncStatusText: String {
        guard let status = syncStatus else { return "加载中..." }
        if status.peers.isEmpty { return "无已知节点" }
        let successLogs = status.recentLogs.filter { $0.status == "success" }
        if let latest = successLogs.first {
            return "已同步 · \(formatRelativeTime(latest.finishedAt))"
        }
        return "\(status.peers.count) 个节点待同步"
    }

    private func loadSyncStatus() async {
        do {
            let client = try settings.makeClient(token: authManager.token)
            syncStatus = try await client.fetchSyncStatus()
            syncError = nil
        } catch {
            // Silently fail — sync status is informational
        }
    }

    private func triggerManualSync() async {
        isSyncing = true
        syncError = nil
        syncMessage = nil
        do {
            let client = try settings.makeClient(token: authManager.token)
            let response = try await client.triggerSync(peerURLs: knownPeerURLs())
            // Reload full sync status after trigger completes
            await loadSyncStatus()
            syncMessage = response.message
            if response.successfulPeers == 0 {
                syncError = response.failedPeers > 0 ? response.message : nil
            }
        } catch {
            syncError = error.localizedDescription
        }
        isSyncing = false
    }

    private func knownPeerURLs() -> [String] {
        let current = normalizedServerURL(settings.trimmedServerURLString)
        let candidates = Set(
            discovery.discoveredServers.map(\.urlString)
            + settings.recentDiscoveredServerURLs
            + settings.savedServers.map(\.url)
            + AppSettingsStore.builtInServers.map(\.url)
        )

        return candidates
            .map(normalizedServerURL)
            .filter { !$0.isEmpty && $0 != current }
            .sorted()
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

    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterBasic = ISO8601DateFormatter()

    private func formatRelativeTime(_ isoString: String) -> String {
        guard let date = Self.isoFormatterFractional.date(from: isoString) ?? Self.isoFormatterBasic.date(from: isoString) else {
            return isoString
        }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        return "\(Int(interval / 86400))天前"
    }
}

private struct UsageGuideSection: Identifiable {
    let id: String
    let icon: String
    let title: String
    let summary: String
    let bullets: [String]
}

enum LegalDocumentType {
    case terms
    case privacy

    var title: String {
        switch self {
        case .terms: return "用户协议"
        case .privacy: return "隐私政策"
        }
    }

    var subtitle: String {
        switch self {
        case .terms: return "请在使用前了解服务边界与账号规则。"
        case .privacy: return "请了解我们收集哪些数据、如何使用与保护。"
        }
    }
}

private struct LegalSection: Identifiable {
    let id: String
    let heading: String
    let bullets: [String]
}

private let termsSections: [LegalSection] = [
    LegalSection(
        id: "positioning",
        heading: "1. 服务定位与声明",
        bullets: [
            "Health AI 由 Health AI团队 提供，用于健康数据整理、趋势解释和生活方式建议。",
            "Health AI 不提供医疗诊断、处方或急救服务，不能替代专业医生意见。",
            "如遇到明显不适或紧急情况，请及时就医。"
        ]
    ),
    LegalSection(
        id: "account",
        heading: "2. 账号与登录方式",
        bullets: [
            "你可通过 Apple 登录，或选择“本机快速进入”开始使用。",
            "请妥善保管你的设备与账号信息，避免他人未经授权访问。",
            "如发现账号异常，可联系 \(AppSettingsStore.supportTeamName)（\(AppSettingsStore.supportEmailAddress)）。"
        ]
    ),
    LegalSection(
        id: "data-scope",
        heading: "3. 数据授权边界",
        bullets: [
            "你可选择同步 Apple 健康数据，或手动上传体检与健康相关文件。",
            "我们仅在实现趋势分析、报告生成、AI 洞察和问题排查所必需范围内使用数据。",
            "你应确认上传数据来源合法且不侵犯他人权益。",
            "你可随时停止上传或关闭 Apple 健康授权，但历史已处理数据仍按隐私政策管理。"
        ]
    ),
    LegalSection(
        id: "responsibility",
        heading: "4. 使用限制与责任",
        bullets: [
            "不得利用本服务进行违法违规用途，或尝试破坏系统安全。",
            "你需对自己提供的数据真实性与完整性负责。",
            "因网络、设备或第三方服务波动导致的中断，我们会尽力修复与优化。",
            "若你通过分享、截图等方式公开健康信息，由你自行承担相应后果。"
        ]
    ),
    LegalSection(
        id: "minor",
        heading: "5. 未成年人使用说明",
        bullets: [
            "本应用主要面向 18 周岁及以上用户。",
            "未满 18 周岁用户建议在监护人指导下使用，并由监护人共同确认数据上传与授权行为。",
            "监护人如发现未成年人存在不当使用，可通过 \(AppSettingsStore.supportEmailAddress) 联系我们处理。"
        ]
    ),
    LegalSection(
        id: "change",
        heading: "6. 服务变更、中断与联系",
        bullets: [
            "我们可能根据功能迭代对协议内容进行更新。",
            "重要更新会通过应用内页面或版本说明提示。",
            "我们可能因维护、升级或合规要求临时调整部分功能。",
            "联系邮箱：\(AppSettingsStore.supportEmailAddress)"
        ]
    )
]

private let privacySections: [LegalSection] = [
    LegalSection(
        id: "collect",
        heading: "1. 我们收集的数据类型",
        bullets: [
            "账号标识信息：如 Apple 授权标识、昵称、邮箱（如授权返回）。",
            "健康与健身数据：来自 Apple 健康同步或你主动上传的数据。",
            "上传文件与报告内容：用于解析体检、检验及相关健康信息。",
            "设备基础诊断信息：用于定位连接与稳定性问题。",
            "最小必要日志：如接口状态、错误类别和时间戳，用于故障排查。"
        ]
    ),
    LegalSection(
        id: "usage",
        heading: "2. 数据使用目的",
        bullets: [
            "完成登录识别与账号安全验证。",
            "生成趋势分析、健康报告与 AI 洞察。",
            "执行同步、上传处理与异常排查。",
            "我们不会出售你的个人信息，也不会将健康数据用于广告定向。",
            "不会基于你的健康数据向第三方投放个性化广告。"
        ]
    ),
    LegalSection(
        id: "healthkit",
        heading: "3. Apple 健康（HealthKit）说明",
        bullets: [
            "你可自主选择是否授权 Apple 健康数据同步。",
            "关闭授权后，后续不会继续读取相应数据。",
            "历史数据的导出或删除，可通过邮箱申请。",
            "Apple 健康授权与撤销可在系统“健康”与“设置”中管理。"
        ]
    ),
    LegalSection(
        id: "sharing",
        heading: "4. 数据共享与第三方",
        bullets: [
            "除实现服务必需或法律法规要求外，我们不会向无关第三方共享你的个人健康数据。",
            "如需使用第三方能力（如云服务、消息推送），会遵循最小必要原则并要求对方履行保护义务。",
            "我们不会在未告知的情况下，将你的健康数据用于商业出售。"
        ]
    ),
    LegalSection(
        id: "security",
        heading: "5. 存储与保护",
        bullets: [
            "我们会采用合理安全措施保护数据，尽量降低未授权访问风险。",
            "任何系统都无法承诺绝对安全，我们会持续改进防护能力。",
            "若发生严重安全事件，我们会按法律法规要求处理与通知。"
        ]
    ),
    LegalSection(
        id: "retention",
        heading: "6. 数据保留与删除",
        bullets: [
            "我们会在实现产品功能所需期限内保留你的相关数据。",
            "当你提交删除申请并通过核验后，我们会在合理期限内处理并反馈结果。",
            "法律法规另有规定的，按监管要求执行。"
        ]
    ),
    LegalSection(
        id: "rights",
        heading: "7. 你的权利与申请方式",
        bullets: [
            "你可申请访问、更正、导出或删除你的个人数据。",
            "申请方式：发送邮件至 \(AppSettingsStore.supportEmailAddress)。",
            "建议在邮件中提供账号信息、设备与具体诉求，以便核验与处理。"
        ]
    ),
    LegalSection(
        id: "update",
        heading: "8. 政策更新",
        bullets: [
            "当隐私政策发生重要变化时，我们会通过应用内页面、版本说明或其他适当方式提示。",
            "更新后的政策发布后生效；若你继续使用应用，视为你已阅读并理解最新版本。"
        ]
    )
]

struct LegalDocumentScreen: View {
    let document: LegalDocumentType

    private var sections: [LegalSection] {
        switch document {
        case .terms: return termsSections
        case .privacy: return privacySections
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard(
                    title: document.title,
                    subtitle: document.subtitle
                ) {
                    Text("主体：\(AppSettingsStore.supportTeamName) ｜ 联系邮箱：\(AppSettingsStore.supportEmailAddress)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(sections) { section in
                    SectionCard(title: section.heading, subtitle: "") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(section.bullets, id: \.self) { bullet in
                                Label(bullet, systemImage: "checkmark.circle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(3)
                            }
                        }
                    }
                }

                Text("生效日期：2026-04-13")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(16)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.99, blue: 0.97),
                    Color(red: 0.95, green: 0.96, blue: 0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private let usageGuideSections: [UsageGuideSection] = [
    UsageGuideSection(
        id: "overview",
        icon: "heart.text.square.fill",
        title: "首页概览",
        summary: "首页会优先告诉你最近最值得关注的积极变化、提醒和下一步建议。",
        bullets: [
            "优先看最近是否有明显改善、回升或波动。",
            "首页给的是趋势解释，不是医疗诊断结论。",
            "如果某些模块暂无数据，会提示你补充而不是展示他人数据。"
        ]
    ),
    UsageGuideSection(
        id: "ai",
        icon: "brain.head.profile",
        title: "AI 洞察",
        summary: "AI 会基于你已有的健康数据，帮助你解释趋势、理解重点并给出生活方式建议。",
        bullets: [
            "更适合回答“最近发生了什么”和“我下一步该怎么做”。",
            "AI 会尽量引用你已有的数据，而不是泛泛而谈。",
            "请把它当作健康管理助手，而不是医生诊断意见。"
        ]
    ),
    UsageGuideSection(
        id: "trends",
        icon: "chart.line.uptrend.xyaxis",
        title: "趋势与报告",
        summary: "趋势页适合看连续变化，报告页适合回顾一个阶段的整体总结。",
        bullets: [
            "趋势页更适合盯住体重、运动、睡眠和恢复等连续数据。",
            "报告页会汇总一段时间内的重要变化和建议。",
            "如果你更关心长期变化，建议结合趋势页和报告页一起看。"
        ]
    ),
    UsageGuideSection(
        id: "data",
        icon: "square.and.arrow.down.on.square.fill",
        title: "数据上传与隐私",
        summary: "你可以同步 Apple 健康，也可以手动上传体检、化验单或其他健康文件。",
        bullets: [
            "上传的数据会用于趋势分析、报告生成和 AI 洞察。",
            "如果需要导出或删除数据，可通过邮箱提交申请。",
            "Health AI团队 会尽力保护你的隐私，不会出售你的个人健康信息。"
        ]
    )
]

private struct UsageGuideScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionCard(title: "如何使用 Health AI", subtitle: "先看整体，再根据需要深入趋势、报告和数据管理。") {
                    Text("Health AI 更适合帮你整理健康数据、理解趋势和安排下一步行动。它不会替代医生，也不会给出处方级建议。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }

                ForEach(usageGuideSections) { section in
                    SectionCard(title: section.title, subtitle: section.summary) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(section.summary, systemImage: section.icon)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)

                            ForEach(section.bullets, id: \.self) { bullet in
                                Label(bullet, systemImage: "checkmark.circle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.99, blue: 0.97),
                    Color(red: 0.95, green: 0.96, blue: 0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("使用说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyDataRequestScreen: View {
    let supportEmail: String
    let supportTeamName: String

    private var mailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Health AI 数据申请"),
            URLQueryItem(name: "body", value: "您好，\n\n我希望申请以下事项：\n- [ ] 导出我的数据\n- [ ] 删除我的数据\n\n我的账号信息：\n- 昵称：\n- 登录邮箱/手机号：\n- 设备与版本：\n\n补充说明：\n")
        ]
        return components.url
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionCard(title: "隐私与数据申请", subtitle: "如果你需要导出或删除数据，可通过邮件向 \(supportTeamName) 申请。") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("申请邮箱：\(supportEmail)", systemImage: "envelope.fill")
                        Label("支持导出数据申请", systemImage: "square.and.arrow.up.fill")
                        Label("支持删除数据申请", systemImage: "trash.fill")
                        Label("提交后请尽量附上你的账号信息与设备版本，便于我们核实处理。", systemImage: "person.text.rectangle.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                SectionCard(title: "建议邮件里包含什么", subtitle: "信息越完整，处理会越快。") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach([
                            "你的昵称、登录邮箱或手机号",
                            "希望导出还是删除数据",
                            "使用中的设备型号与 App 版本",
                            "如果是删除申请，可补充是否希望同步删除上传文件与报告"
                        ], id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let mailURL {
                    Link(destination: mailURL) {
                        Text("发送邮件申请")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color(hex: "#0f766e") ?? .teal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }

                NavigationLink {
                    LegalDocumentScreen(document: .privacy)
                } label: {
                    Label("查看完整隐私政策", systemImage: "lock.doc.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color(hex: "#0f766e") ?? .teal)
            }
            .padding(16)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.99, blue: 0.97),
                    Color(red: 0.95, green: 0.96, blue: 0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("隐私与数据申请")
        .navigationBarTitleDisplayMode(.inline)
    }
}
