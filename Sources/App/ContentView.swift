import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ProxyModel
    @State private var editing: ProxyProfile?
    @State private var confirmTurnOff = false

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                profilesSection
                networksSection
            }
            .navigationTitle("ProxyToggle")
            .toolbar {
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .refreshable { model.refresh() }
            .sheet(item: $editing) { profile in
                ProfileEditor(profile: profile) { model.upsert($0) }
            }
            .alert("Error", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var statusSection: some View {
        Section {
            Toggle(isOn: Binding(get: { model.isOn }, set: { model.setEnabled($0) })) {
                HStack(spacing: 14) {
                    Image(systemName: model.isOn ? "network.badge.shield.half.filled" : "network")
                        .font(.title)
                        .foregroundStyle(model.isOn ? Color.green : Color.secondary)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.isOn ? "Proxy on" : "Proxy off")
                            .font(.headline)
                        Text(model.effective)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            .tint(.green)

            LabeledContent("Network", value: model.currentNetwork?.name ?? "Not connected")

            Picker("Apply to", selection: $model.scope) {
                Text("All networks").tag(ProxyScope.allNetworks)
                Text("Current network").tag(ProxyScope.currentNetwork)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Status")
        } footer: {
            if let result = model.lastResult { Text(result) }
        }
    }

    private var profilesSection: some View {
        Section("Profiles") {
            ForEach(model.profiles) { profile in
                Button { model.select(profile) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .foregroundStyle(.primary)
                            Text(profile.config.summary)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if profile.id == model.selectedID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { model.delete(profile) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { editing = profile } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
                .contextMenu {
                    Button { editing = profile } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { model.delete(profile) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Button {
                editing = ProxyProfile(name: "", config: ProxyConfig())
            } label: {
                Label("Add profile", systemImage: "plus")
            }
        }
    }

    private var networksSection: some View {
        Section {
            ForEach(model.networks) { network in
                HStack {
                    Image(systemName: "wifi")
                        .foregroundStyle(network.isCurrent ? Color.accentColor : Color.secondary)
                    Text(network.name)
                        .fontWeight(network.isCurrent ? .semibold : .regular)
                    Spacer()
                    Text(network.summary)
                        .font(.caption.monospaced())
                        .foregroundStyle(network.isProxied ? Color.green : Color.secondary)
                }
            }
            Button("Turn off on all networks", role: .destructive) { confirmTurnOff = true }
                .confirmationDialog("Remove the proxy from every saved network?",
                                    isPresented: $confirmTurnOff, titleVisibility: .visible) {
                    Button("Turn off everywhere", role: .destructive) { model.turnOffEverywhere() }
                }
        } header: {
            Text("Saved networks")
        } footer: {
            Text("iOS keeps a separate proxy per Wi-Fi network. \"All networks\" writes every one of them.")
        }
    }
}
