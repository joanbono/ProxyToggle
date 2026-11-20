import Foundation

struct ProxyProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var config: ProxyConfig
}

/// Saved profiles and app settings, kept as JSON outside the app bundle and
/// data container so they survive reinstalls and are readable by proxyctl.
struct ProfileStore: Codable {
    static let url = URL(fileURLWithPath: "/var/mobile/Library/Application Support/ProxyToggle/profiles.json")

    var profiles: [ProxyProfile] = []
    var selectedID: UUID?
    var scope: ProxyScope = .allNetworks

    var selectedProfile: ProxyProfile? { profiles.first { $0.id == selectedID } }

    func profile(named name: String) -> ProxyProfile? {
        profiles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Returns nil when no store has been written yet.
    static func load() throws -> ProfileStore? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ProfileStore.self, from: Data(contentsOf: url))
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.url, options: .atomic)
    }
}
