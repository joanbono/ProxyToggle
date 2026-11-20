import Foundation
import CFNetwork

struct ProxyConfig: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case manual
        case pac
    }

    var kind: Kind = .manual
    var host = ""
    var port = 8080
    var pacURL = ""
    var exceptions = ["*.local", "169.254/16"]

    var summary: String {
        switch kind {
        case .manual: return "\(host):\(port)"
        case .pac: return "PAC \(pacURL)"
        }
    }

    var validationError: String? {
        switch kind {
        case .manual:
            if host.trimmingCharacters(in: .whitespaces).isEmpty { return "Host is empty" }
            if !(1...65535).contains(port) { return "Port must be 1-65535" }
        case .pac:
            if URL(string: pacURL)?.scheme == nil { return "PAC URL is invalid" }
        }
        return nil
    }
}

enum ProxyScope: String, Codable, CaseIterable {
    case allNetworks
    case currentNetwork
}

/// A saved network: iOS 17 keeps one SystemConfiguration Set per Wi-Fi SSID.
struct NetworkEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let isCurrent: Bool
    let summary: String

    var isProxied: Bool { summary != ProxyManager.offSummary }
}

enum ProxyManager {
    enum Failure: LocalizedError {
        case invalid(String)
        case noServices

        var errorDescription: String? {
            switch self {
            case .invalid(let reason): return reason
            case .noServices: return "No Wi-Fi or Ethernet service found in the selected networks"
            }
        }
    }

    static let offSummary = "Off"

    private static let sessionName = "ProxyToggle"
    private static let proxiedHardware: Set<String> = ["AirPort", "Ethernet"]
    private static let managedKeys = [
        "HTTPEnable", "HTTPProxy", "HTTPPort",
        "HTTPSEnable", "HTTPSProxy", "HTTPSPort",
        "ProxyAutoConfigEnable", "ProxyAutoConfigURLString",
    ]

    private struct Snapshot {
        let currentSetID: String?
        let sets: [String: [String: Any]]
        let services: [String: [String: Any]]

        init(_ prefs: SCPreferencesSession) {
            currentSetID = (prefs.value("CurrentSet") as? String)?.components(separatedBy: "/").last
            sets = prefs.value("Sets") as? [String: [String: Any]] ?? [:]
            services = prefs.value("NetworkServices") as? [String: [String: Any]] ?? [:]
        }

        /// Wi-Fi first, then Ethernet; cellular and VPN services are skipped.
        func proxiedServiceIDs(inSet setID: String) -> [String] {
            let network = sets[setID]?["Network"] as? [String: Any]
            let links = network?["Service"] as? [String: [String: Any]] ?? [:]
            let ids = links.compactMap { key, link in
                (link["__LINK__"] as? String)?.components(separatedBy: "/").last ?? key
            }
            return ids
                .filter { proxiedHardware.contains(hardware(of: $0)) }
                .sorted { (hardware(of: $0) == "AirPort" ? 0 : 1, $0) < (hardware(of: $1) == "AirPort" ? 0 : 1, $1) }
        }

        func hardware(of serviceID: String) -> String {
            (services[serviceID]?["Interface"] as? [String: Any])?["Hardware"] as? String ?? ""
        }

        func proxies(of serviceID: String) -> [String: Any] {
            services[serviceID]?["Proxies"] as? [String: Any] ?? [:]
        }
    }

    static func networks() throws -> [NetworkEntry] {
        let snapshot = Snapshot(try SCPreferencesSession(name: sessionName))
        return snapshot.sets.keys.map { setID in
            let name = snapshot.sets[setID]?["UserDefinedName"] as? String ?? setID
            let summary = snapshot.proxiedServiceIDs(inSet: setID).first
                .map { describe(snapshot.proxies(of: $0)) } ?? offSummary
            return NetworkEntry(id: setID, name: name, isCurrent: setID == snapshot.currentSetID, summary: summary)
        }
        .sorted { ($0.isCurrent ? 0 : 1, $0.name.lowercased()) < ($1.isCurrent ? 0 : 1, $1.name.lowercased()) }
    }

    /// Writes `config` (or clears the proxy when nil) and tells configd to apply it.
    /// Returns the number of network services updated.
    @discardableResult
    static func apply(_ config: ProxyConfig?, scope: ProxyScope) throws -> Int {
        if let reason = config?.validationError { throw Failure.invalid(reason) }

        let prefs = try SCPreferencesSession(name: sessionName)
        try prefs.lock()
        defer { prefs.unlock() }

        let snapshot = Snapshot(prefs)
        let setIDs = scope == .allNetworks ? Array(snapshot.sets.keys) : [snapshot.currentSetID].compactMap { $0 }
        let serviceIDs = Set(setIDs.flatMap { snapshot.proxiedServiceIDs(inSet: $0) })
        guard !serviceIDs.isEmpty else { throw Failure.noServices }

        for id in serviceIDs {
            try prefs.setValue(merge(snapshot.proxies(of: id), with: config), atPath: "/NetworkServices/\(id)/Proxies")
        }
        try prefs.commit()
        try prefs.apply()
        return serviceIDs.count
    }

    /// The proxy CFNetwork is using right now.
    static func effectiveProxy() -> String {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return offSummary
        }
        return describe(settings)
    }

    private static func merge(_ existing: [String: Any], with config: ProxyConfig?) -> [String: Any] {
        var proxies = existing
        managedKeys.forEach { proxies.removeValue(forKey: $0) }
        proxies["FTPPassive"] = proxies["FTPPassive"] ?? 1

        guard let config else { return proxies }
        switch config.kind {
        case .manual:
            let host = config.host.trimmingCharacters(in: .whitespaces)
            proxies["HTTPEnable"] = 1
            proxies["HTTPProxy"] = host
            proxies["HTTPPort"] = config.port
            proxies["HTTPSEnable"] = 1
            proxies["HTTPSProxy"] = host
            proxies["HTTPSPort"] = config.port
        case .pac:
            proxies["ProxyAutoConfigEnable"] = 1
            proxies["ProxyAutoConfigURLString"] = config.pacURL
        }
        proxies["ExceptionsList"] = config.exceptions
        return proxies
    }

    private static func describe(_ proxies: [String: Any]) -> String {
        if proxies["ProxyAutoConfigEnable"] as? Int == 1, let url = proxies["ProxyAutoConfigURLString"] as? String {
            return "PAC \(url)"
        }
        if proxies["HTTPEnable"] as? Int == 1, let host = proxies["HTTPProxy"] as? String {
            return "\(host):\(proxies["HTTPPort"] as? Int ?? 0)"
        }
        if proxies["HTTPSEnable"] as? Int == 1, let host = proxies["HTTPSProxy"] as? String {
            return "\(host):\(proxies["HTTPSPort"] as? Int ?? 0)"
        }
        return offSummary
    }
}
