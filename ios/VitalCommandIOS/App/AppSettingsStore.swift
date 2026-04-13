import Foundation
import SwiftUI
import VitalCommandMobileCore

enum AppTab: Hashable {
    case home
    case plan
    case reports
    case data

    init?(demoValue: String?) {
        switch demoValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "home":
            self = .home
        case "plan":
            self = .plan
        case "reports", "report":
            self = .reports
        case "data":
            self = .data
        default:
            return nil
        }
    }
}

enum HomeDestination {
    case medicalInsight
    case geneticInsight
    case dietInsight
}

@MainActor
final class AppSettingsStore: ObservableObject {
    struct BuiltInServerOption: Identifiable, Equatable {
        let url: String
        let name: String
        let detail: String

        var id: String { url }
    }

    static let publicPrimaryServerURL = "https://app.wellai.online/"
    static let publicBackupServerURL = "https://backup.wellai.online/"
    static let remoteServerAURL = "http://10.8.144.16:3001/"
    static let remoteServerBURL = "http://10.8.130.244:3001/"
    static let currentRemoteServerURL = remoteServerAURL
    static let defaultSimulatorServerURL = "http://127.0.0.1:3000/"
    static let supportEmailAddress = "yao.ma@qq.com"
    static let supportTeamName = "Health AI团队"
    static let builtInServers: [BuiltInServerOption] = [
        BuiltInServerOption(
            url: publicPrimaryServerURL,
            name: "公网主站",
            detail: "默认推荐，适合移动网络和外网访问"
        ),
        BuiltInServerOption(
            url: publicBackupServerURL,
            name: "公网备站",
            detail: "主站切换时使用"
        ),
        BuiltInServerOption(
            url: remoteServerAURL,
            name: "远端服务器 A",
            detail: "10.8.144.16（主）"
        ),
        BuiltInServerOption(
            url: remoteServerBURL,
            name: "远端服务器 B",
            detail: "10.8.130.244（备）"
        )
    ]
    @Published var serverURLString: String {
        didSet {
            UserDefaults.standard.set(serverURLString, forKey: Self.serverURLKey)
        }
    }
    @Published private(set) var dataRefreshVersion = 0
    @Published var selectedTab: AppTab = .home
    @Published var pendingHomeDestination: HomeDestination?
    var authToken: String?

    static let serverURLKey = "vital-command.server-url"
    static let savedServersKey = "vital-command.saved-servers"
    static let discoveredServersKey = "vital-command.discovered-servers"

    struct SavedServer: Codable, Identifiable, Equatable {
        var id: String { url }
        let url: String
        let name: String
        let addedAt: Date
    }

    @Published var savedServers: [SavedServer] {
        didSet {
            if let data = try? JSONEncoder().encode(savedServers) {
                UserDefaults.standard.set(data, forKey: Self.savedServersKey)
            }
        }
    }
    @Published private(set) var recentDiscoveredServerURLs: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(recentDiscoveredServerURLs) {
                UserDefaults.standard.set(data, forKey: Self.discoveredServersKey)
            }
        }
    }

    private static let legacyServerURLMap: [String: String] = [
        "http://10.8.140.209:3000": publicPrimaryServerURL,
        "http://10.8.140.209:3000/": publicPrimaryServerURL,
        "http://10.8.144.16:3001": remoteServerAURL,
        "http://10.8.130.244:3001": remoteServerBURL,
        "http://192.168.31.193:3000": publicPrimaryServerURL,
        "http://192.168.31.193:3000/": publicPrimaryServerURL,
        "https://app.wellai.online": publicPrimaryServerURL,
        "https://backup.wellai.online": publicBackupServerURL
    ]

    init() {
        if let demoTab = AppTab(demoValue: ProcessInfo.processInfo.environment["VC_DEFAULT_TAB"]) {
            self.selectedTab = demoTab
        }

        let storedValue = Self.migrateServerURL(
            UserDefaults.standard.string(forKey: Self.serverURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let storedValue {
            UserDefaults.standard.set(storedValue, forKey: Self.serverURLKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.serverURLKey)
        }

#if targetEnvironment(simulator)
        self.serverURLString = (storedValue?.isEmpty == false ? storedValue : Self.defaultSimulatorServerURL) ?? Self.defaultSimulatorServerURL
#else
        if let storedValue, storedValue.isEmpty == false, storedValue.contains("localhost") == false, storedValue.contains("127.0.0.1") == false {
            self.serverURLString = storedValue
        } else {
            self.serverURLString = Self.currentRemoteServerURL
        }
#endif

        if let data = UserDefaults.standard.data(forKey: Self.savedServersKey),
           let servers = try? JSONDecoder().decode([SavedServer].self, from: data) {
            self.savedServers = Self.migrateSavedServers(servers)
        } else {
            self.savedServers = []
        }

        if let data = UserDefaults.standard.data(forKey: Self.discoveredServersKey),
           let urls = try? JSONDecoder().decode([String].self, from: data) {
            self.recentDiscoveredServerURLs = urls.compactMap { HealthKitUploadTargetResolver.canonicalize($0) }
        } else {
            self.recentDiscoveredServerURLs = []
        }
    }

    var trimmedServerURLString: String {
        serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var dashboardReloadKey: String {
        "\(trimmedServerURLString)#\(dataRefreshVersion)"
    }

    var supportEmailAddress: String {
        Self.supportEmailAddress
    }

    var supportTeamName: String {
        Self.supportTeamName
    }

    var privacyPolicyURL: URL? {
        resolvedPublicWebBaseURL?.appending(path: "legal/privacy")
    }

    var termsOfServiceURL: URL? {
        resolvedPublicWebBaseURL?.appending(path: "legal/terms")
    }

    var supportMailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.supportEmailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Health AI 支持与隐私申请")
        ]
        return components.url
    }

    func cacheScope(userID: String?) -> String {
        let server = HealthKitUploadTargetResolver.canonicalize(trimmedServerURLString) ?? trimmedServerURLString
        let user = userID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? userID! : "anonymous"
        return "\(server)#\(user)"
    }

    func makeClient(token: String? = nil) throws -> HealthAPIClient {
        guard let url = URL(string: trimmedServerURLString), url.scheme?.hasPrefix("http") == true else {
            throw HealthAPIClientError.transport("请填写可访问的服务地址，例如 https://app.wellai.online/")
        }

        let effectiveToken = token ?? authToken
        return HealthAPIClient(configuration: AppServerConfiguration(baseURL: url), token: effectiveToken)
    }

    func markHealthDataChanged() {
        dataRefreshVersion += 1
    }

    func openHome(destination: HomeDestination? = nil) {
        pendingHomeDestination = destination
        selectedTab = .home
    }

    func saveCurrentServer(name: String? = nil) {
        let url = trimmedServerURLString
        guard !url.isEmpty else { return }
        if !savedServers.contains(where: { $0.url == url }) {
            savedServers.append(SavedServer(url: url, name: name ?? url, addedAt: Date()))
        }
    }

    func rememberDiscoveredServerURLs(_ urls: [String]) {
        let candidates =
            urls
            .compactMap { HealthKitUploadTargetResolver.canonicalize($0) }
            .filter { HealthKitUploadTargetResolver.isLikelyLAN(urlString: $0) }

        guard candidates.isEmpty == false else { return }

        var merged: [String] = []
        var seen = Set<String>()

        for url in candidates + recentDiscoveredServerURLs {
            guard seen.insert(url).inserted else { continue }
            merged.append(url)
        }

        recentDiscoveredServerURLs = Array(merged.prefix(12))
    }

    func healthKitUploadTargetURLs() -> [String] {
        return HealthKitUploadTargetResolver.prioritizeTargets(
            discoveredServerURLs: recentDiscoveredServerURLs,
            currentServerURL: trimmedServerURLString,
            savedServerURLs: savedServers.map(\.url),
            preferredServerURLs: Self.builtInServers.map(\.url)
        )
    }

    func removeSavedServer(_ server: SavedServer) {
        savedServers.removeAll { $0.id == server.id }
    }

    private static func migrateServerURL(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return nil
        }

        return legacyServerURLMap[raw] ?? raw
    }

    private static func migrateSavedServers(_ servers: [SavedServer]) -> [SavedServer] {
        var seen = Set<String>()
        var migrated: [SavedServer] = []

        for server in servers {
            let nextURL = migrateServerURL(server.url) ?? server.url
            guard seen.insert(nextURL).inserted else {
                continue
            }

            migrated.append(
                SavedServer(
                    url: nextURL,
                    name: server.name,
                    addedAt: server.addedAt
                )
            )
        }

        return migrated
    }

    private var resolvedPublicWebBaseURL: URL? {
        let rawValue = trimmedServerURLString
        guard let currentURL = URL(string: rawValue), let host = currentURL.host else {
            return URL(string: Self.publicPrimaryServerURL)
        }

        let normalizedHost = host.lowercased()
        let isLocalHost =
            normalizedHost == "localhost"
            || normalizedHost == "127.0.0.1"
            || normalizedHost.hasPrefix("10.")
            || normalizedHost.hasPrefix("192.168.")
            || normalizedHost.hasPrefix("172.16.")
            || normalizedHost.hasPrefix("172.17.")
            || normalizedHost.hasPrefix("172.18.")
            || normalizedHost.hasPrefix("172.19.")
            || normalizedHost.hasPrefix("172.2")
            || normalizedHost.hasSuffix(".local")

        if isLocalHost {
            return URL(string: Self.publicPrimaryServerURL)
        }

        let normalizedString = rawValue.hasSuffix("/") ? rawValue : rawValue + "/"
        return URL(string: normalizedString) ?? URL(string: Self.publicPrimaryServerURL)
    }
}
