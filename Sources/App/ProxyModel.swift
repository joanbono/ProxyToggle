import Foundation
import SwiftUI

@MainActor
final class ProxyModel: ObservableObject {
    @Published var profiles: [ProxyProfile] = [] { didSet { save() } }
    @Published var selectedID: UUID? { didSet { save() } }
    @Published var scope: ProxyScope = .allNetworks { didSet { save() } }
    @Published private(set) var networks: [NetworkEntry] = []
    @Published private(set) var effective = ProxyManager.offSummary
    @Published private(set) var lastResult: String?
    @Published var errorMessage: String?

    private var loading = true

    init() {
        var store: ProfileStore
        do {
            store = try ProfileStore.load() ?? Self.migrateUserDefaults()
        } catch {
            store = ProfileStore()
            errorMessage = "Could not read \(ProfileStore.url.path): \(error.localizedDescription)"
        }
        if store.profiles.isEmpty {
            store.profiles = [ProxyProfile(name: "Burp", config: ProxyConfig(host: "192.168.1.10", port: 8080))]
        }
        profiles = store.profiles
        selectedID = store.selectedID ?? store.profiles.first?.id
        scope = store.scope
        loading = false
        save()
        refresh()
    }

    /// Profiles from 1.0 lived in UserDefaults.
    private static func migrateUserDefaults() -> ProfileStore {
        let defaults = UserDefaults.standard
        var store = ProfileStore()
        if let data = defaults.data(forKey: "profiles"),
           let saved = try? JSONDecoder().decode([ProxyProfile].self, from: data) {
            store.profiles = saved
        }
        store.selectedID = defaults.string(forKey: "selectedProfile").flatMap(UUID.init)
        store.scope = defaults.string(forKey: "scope").flatMap(ProxyScope.init) ?? .allNetworks
        return store
    }

    var selectedProfile: ProxyProfile? { profiles.first { $0.id == selectedID } }
    var currentNetwork: NetworkEntry? { networks.first { $0.isCurrent } }
    var isOn: Bool { effective != ProxyManager.offSummary }

    func refresh() {
        effective = ProxyManager.effectiveProxy()
        do {
            networks = try ProxyManager.networks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard let profile = selectedProfile else {
                errorMessage = "Select a profile first"
                return
            }
            apply(profile.config, label: profile.name)
        } else {
            apply(nil, label: "Off")
        }
    }

    func select(_ profile: ProxyProfile) {
        selectedID = profile.id
        if isOn { apply(profile.config, label: profile.name) }
    }

    func upsert(_ profile: ProxyProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            if profile.id == selectedID, isOn { apply(profile.config, label: profile.name) }
        } else {
            profiles.append(profile)
        }
    }

    func delete(_ profile: ProxyProfile) {
        profiles.removeAll { $0.id == profile.id }
        if selectedID == profile.id { selectedID = profiles.first?.id }
    }

    func turnOffEverywhere() {
        apply(nil, scope: .allNetworks, label: "Off")
    }

    /// proxytoggle://on[?profile=Name], proxytoggle://off, proxytoggle://toggle
    func handle(_ url: URL) {
        guard url.scheme == "proxytoggle" else { return }
        refresh()
        switch url.host {
        case "on":
            let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "profile" }?.value
            if let name, let profile = ProfileStore(profiles: profiles).profile(named: name) {
                selectedID = profile.id
            }
            setEnabled(true)
        case "off":
            setEnabled(false)
        case "toggle":
            setEnabled(!isOn)
        default:
            errorMessage = "Unknown action: \(url.absoluteString)"
        }
    }

    private func apply(_ config: ProxyConfig?, scope: ProxyScope? = nil, label: String) {
        do {
            let count = try ProxyManager.apply(config, scope: scope ?? self.scope)
            lastResult = "\(label) applied to \(count) service\(count == 1 ? "" : "s")"
        } catch {
            errorMessage = error.localizedDescription
        }
        // configd publishes the new state asynchronously.
        refresh()
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            refresh()
        }
    }

    private func save() {
        guard !loading else { return }
        do {
            try ProfileStore(profiles: profiles, selectedID: selectedID, scope: scope).save()
        } catch {
            errorMessage = "Could not save profiles: \(error.localizedDescription)"
        }
    }
}
