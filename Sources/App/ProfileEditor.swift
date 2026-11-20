import SwiftUI

struct ProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profile: ProxyProfile
    @State private var exceptions: String
    let onSave: (ProxyProfile) -> Void

    init(profile: ProxyProfile, onSave: @escaping (ProxyProfile) -> Void) {
        _profile = State(initialValue: profile)
        _exceptions = State(initialValue: profile.config.exceptions.joined(separator: ", "))
        self.onSave = onSave
    }

    private var validationError: String? {
        if profile.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Name is empty" }
        return profile.config.validationError
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $profile.name)
                    Picker("Type", selection: $profile.config.kind) {
                        Text("Manual").tag(ProxyConfig.Kind.manual)
                        Text("PAC").tag(ProxyConfig.Kind.pac)
                    }
                    .pickerStyle(.segmented)
                }

                switch profile.config.kind {
                case .manual:
                    Section("Server") {
                        TextField("Host", text: $profile.config.host)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                        TextField("Port", value: $profile.config.port, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .font(.body.monospaced())
                    }
                case .pac:
                    Section("PAC file") {
                        TextField("http://host/proxy.pac", text: $profile.config.pacURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                    }
                }

                Section {
                    TextField("*.local, 169.254/16", text: $exceptions, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text("Bypass")
                } footer: {
                    Text(validationError ?? "Comma-separated hosts that skip the proxy.")
                        .foregroundStyle(validationError == nil ? Color.secondary : Color.red)
                }
            }
            .navigationTitle(profile.name.isEmpty ? "New profile" : profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.config.exceptions = exceptions
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        onSave(profile)
                        dismiss()
                    }
                    .disabled(validationError != nil)
                }
            }
        }
    }
}
