import Foundation
import Network

@MainActor
final class ServerDiscoveryService: ObservableObject {
    struct DiscoveredServer: Identifiable, Equatable, Codable {
        var id: String { baseURL }
        let service: String
        let name: String
        let ip: String
        let port: Int
        let version: String
        let serverId: String?
        let baseURL: String
        var lastSeen: Date

        var urlString: String { baseURL }

        var isRecentlyActive: Bool {
            Date().timeIntervalSince(lastSeen) < 15
        }
    }

    @Published private(set) var discoveredServers: [DiscoveredServer] = []
    @Published private(set) var isScanning = false

    private var listener: NWListener?
    private var connection: NWConnection?
    private var udpGroup: NWConnectionGroup?

    func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        listenForBroadcasts()
        Task { await scanKnownServers() }
    }

    func stopScanning() {
        isScanning = false
        listener?.cancel()
        listener = nil
        connection?.cancel()
        connection = nil
        udpGroup?.cancel()
        udpGroup = nil
    }

    private func listenForBroadcasts() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .wifi

        do {
            let listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: 41234))
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                self?.startReceiving(on: connection)
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[Discovery] Listening for broadcasts on port 41234")
                case .failed(let error):
                    print("[Discovery] Listener failed: \(error)")
                default:
                    break
                }
            }

            listener.start(queue: .main)
        } catch {
            print("[Discovery] Failed to create listener: \(error)")
            Task { await scanSubnet() }
        }
    }

    nonisolated private func startReceiving(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data = data, let json = try? JSONDecoder().decode(BroadcastMessage.self, from: data) {
                Task { @MainActor in
                    self?.addOrUpdateServer(from: json)
                }
            }
            if error == nil {
                self?.startReceiving(on: connection)
            }
        }
    }

    private struct BroadcastMessage: Decodable {
        let service: String
        let name: String
        let ip: String
        let port: Int
        let version: String
        let serverId: String?
        let scheme: String?
        let baseURL: String?

        enum CodingKeys: String, CodingKey {
            case service
            case name
            case ip
            case port
            case version
            case serverId
            case legacyServerId = "server_id"
            case scheme
            case baseURL
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            service = try container.decode(String.self, forKey: .service)
            name = try container.decode(String.self, forKey: .name)
            ip = try container.decode(String.self, forKey: .ip)
            port = try container.decode(Int.self, forKey: .port)
            version = try container.decode(String.self, forKey: .version)
            serverId = try container.decodeIfPresent(String.self, forKey: .serverId)
                ?? container.decodeIfPresent(String.self, forKey: .legacyServerId)
            scheme = try container.decodeIfPresent(String.self, forKey: .scheme)
            baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        }
    }

    private func addOrUpdateServer(from msg: BroadcastMessage) {
        addOrUpdateServer(from: msg, fallbackBaseURL: nil)
    }

    private func addOrUpdateServer(from msg: BroadcastMessage, fallbackBaseURL: String?) {
        guard msg.service == "vital-command", let server = makeDiscoveredServer(from: msg, fallbackBaseURL: fallbackBaseURL) else { return }
        addOrUpdateServer(server)
    }

    private func addOrUpdateServer(_ server: DiscoveredServer) {
        if let idx = discoveredServers.firstIndex(where: { $0.id == server.id }) {
            discoveredServers[idx] = server
        } else {
            discoveredServers.append(server)
        }

        discoveredServers.removeAll { !$0.isRecentlyActive && Date().timeIntervalSince($0.lastSeen) > 30 }
    }

    private func makeDiscoveredServer(from msg: BroadcastMessage, fallbackBaseURL: String?) -> DiscoveredServer? {
        guard msg.service == "vital-command" else { return nil }
        guard let baseURL = normalizedBaseURL(msg.baseURL ?? fallbackBaseURL ?? "\(msg.scheme ?? "http")://\(msg.ip):\(msg.port)/") else {
            return nil
        }

        return DiscoveredServer(
            service: msg.service,
            name: msg.name,
            ip: msg.ip,
            port: msg.port,
            version: msg.version,
            serverId: msg.serverId,
            baseURL: baseURL,
            lastSeen: Date()
        )
    }

    /// Fallback: scan common ports on the local subnet (batched to limit concurrency)
    func scanSubnet() async {
        await scanKnownServers()

        guard let ip = getWiFiAddress() else { return }
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return }
        let subnet = parts[0...2].joined(separator: ".")
        let allTargets = (1...254).flatMap { host -> [(String, Int)] in
            let ip = "\(subnet).\(host)"
            return [(ip, 3000), (ip, 3001)]
        }
        let batchSize = 20

        for batchStart in stride(from: 0, to: allTargets.count, by: batchSize) {
            let batch = Array(allTargets[batchStart..<min(batchStart + batchSize, allTargets.count)])
            await withTaskGroup(of: DiscoveredServer?.self) { group in
                for (targetIP, targetPort) in batch {
                    group.addTask {
                        await self.probeServer(urlString: "http://\(targetIP):\(targetPort)/")
                    }
                }
                for await result in group {
                    if let server = result {
                        addOrUpdateServer(server)
                    }
                }
            }
        }
    }

    private func scanKnownServers() async {
        let knownURLs = Set(AppSettingsStore.builtInServers.map(\.url))

        for urlString in knownURLs {
            if let server = await probeServer(urlString: urlString) {
                addOrUpdateServer(server)
            }
        }
    }

    private func probeServer(ip: String, port: Int) async -> DiscoveredServer? {
        await probeServer(urlString: "http://\(ip):\(port)/")
    }

    private func probeServer(urlString: String) async -> DiscoveredServer? {
        guard
            let baseURL = normalizedBaseURL(urlString),
            let url = URL(string: "\(baseURL)api/discover")
        else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            let msg = try JSONDecoder().decode(BroadcastMessage.self, from: data)
            guard msg.service == "vital-command" else { return nil }
            return makeDiscoveredServer(from: msg, fallbackBaseURL: baseURL)
        } catch {
            return nil
        }
    }

    private func normalizedBaseURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/"
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString
    }

    private func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }
}
