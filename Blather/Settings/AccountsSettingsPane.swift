import SwiftUI

struct AccountsSettingsPane: View {
    @Environment(AppModel.self) private var appModel
    @State private var notice: String?

    var body: some View {
        Form {
            Section {
                Text("Connect the networks you want to publish to. Secrets stay in the macOS Keychain.")
                    .foregroundStyle(.secondary)
                Button("Run health checks") {
                    appModel.runHealthChecks()
                }
                .disabled(appModel.isBusy)
            }

            if let message = appModel.statusMessage ?? notice {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Network.allCases) { network in
                AccountSection(network: network)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

private struct AccountSection: View {
    @Environment(AppModel.self) private var appModel
    @State private var navigation = SettingsNavigation.shared
    let network: Network
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var pds = AccountSettings.defaultPDS
    @State private var handle = ""
    @State private var appPassword = ""
    @State private var showingHelp = false
    @State private var confirmRemove = false
    @State private var isExpanded = false
    @State private var hasInitializedExpansion = false

    private var connection: ConnectionInfo {
        appModel.connection(for: network)
    }

    private var isDisconnected: Bool {
        connection.state == .disconnected
    }

    private var settingsIdentity: String {
        "\(connection.state.rawValue)|\(connection.credentialRef ?? "")"
    }

    var body: some View {
        Section {
            headerRow

            if isExpanded {
                if let label = connection.accountLabel {
                    LabeledContent("Account", value: label)
                }
                if let error = connection.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                credentialFields

                if isDisconnected {
                    connectButton
                } else {
                    HStack(spacing: 8) {
                        Button("Save") {
                            save()
                        }
                        .disabled(!canSave || appModel.isBusy)
                        .accessibilityIdentifier("save-account-\(network.rawValue)")
                        Button("Remove Account…", role: .destructive) {
                            confirmRemove = true
                        }
                        .disabled(appModel.isBusy)
                        .accessibilityIdentifier("remove-account-\(network.rawValue)")
                    }
                }
            }
        }
        .sheet(isPresented: $showingHelp) {
            MetaCredentialsHelp(network: network)
        }
        .confirmationDialog(removeTitle, isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Account", role: .destructive) {
                appModel.disconnect(network: network)
                clientSecret = ""
                appPassword = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the stored credentials. Drafts and history are kept.")
        }
        .onAppear {
            if navigation.focusedNetwork != nil {
                applyFocusedNetwork(animated: false)
            } else if !hasInitializedExpansion {
                isExpanded = connection.state != .connected
            }
            hasInitializedExpansion = true
            applyStoredSettings(connection)
        }
        .onChange(of: navigation.focusGeneration) { _, _ in
            applyFocusedNetwork(animated: true)
        }
        .onChange(of: settingsIdentity) { _, _ in
            applyStoredSettings(appModel.connection(for: network))
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Button(action: toggleExpanded) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    NetworkIcon(network: network)
                        .foregroundStyle(.secondary)
                    Text(network.title)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("account-section-\(network.rawValue)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .imageScale(.small)
                .help(capabilityHelp)
                .accessibilityLabel("About \(network.title)")
                .accessibilityHint(capabilityHelp)

            Button(action: toggleExpanded) {
                HStack(spacing: 8) {
                    Spacer(minLength: 8)
                    if connection.state == .connected, let label = connection.accountLabel, !label.isEmpty {
                        Text(label)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    ConnectionStateBadge(state: connection.state)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleExpanded() {
        withAnimation(.snappy) { isExpanded.toggle() }
    }

    private func applyFocusedNetwork(animated: Bool) {
        guard let focused = navigation.focusedNetwork else { return }
        let shouldExpand = network == focused
        if animated {
            withAnimation(.snappy) { isExpanded = shouldExpand }
        } else {
            isExpanded = shouldExpand
        }
    }

    private var capabilityHelp: String {
        let caps = Capabilities.capabilities(for: network)
        var parts = [
            "\(caps.maxChars) characters, up to \(caps.maxImages) images\(caps.allowsVideo ? ", video" : "")\(caps.requiresMedia ? ", media required" : "")",
        ]
        parts.append(contentsOf: caps.notes)
        return parts.joined(separator: "\n\n")
    }

    @ViewBuilder
    private var credentialFields: some View {
        let hasSecret = !isDisconnected && appModel.accountSettings(for: network).hasStoredSecret
        switch network {
        case .x:
            TextField("Client ID", text: $clientId)
        case .bluesky:
            TextField("PDS", text: $pds)
            TextField("Handle", text: $handle)
            StoredSecretField("App password", text: $appPassword, hasStoredSecret: hasSecret)
        case .threads, .instagram:
            TextField("App ID", text: $clientId)
            StoredSecretField("App Secret", text: $clientSecret, hasStoredSecret: hasSecret)
            Button("Where do I find the App ID and App Secret?") {
                showingHelp = true
            }
            .buttonStyle(.link)
        }
    }

    @ViewBuilder
    private var connectButton: some View {
        switch network {
        case .x:
            Button("Connect") {
                appModel.connectX(clientId: clientId.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .disabled(trimmedClientId.isEmpty || appModel.isBusy)
        case .bluesky:
            Button("Connect") {
                appModel.connectBluesky(
                    pds: pds.trimmingCharacters(in: .whitespacesAndNewlines),
                    handle: handle.trimmingCharacters(in: .whitespacesAndNewlines),
                    appPassword: appPassword
                )
            }
            .disabled(trimmedHandle.isEmpty || appPassword.isEmpty || appModel.isBusy)
        case .threads, .instagram:
            Button("Connect") {
                if network == .threads {
                    appModel.connectThreads(clientId: clientId, clientSecret: clientSecret)
                } else {
                    appModel.connectInstagram(clientId: clientId, clientSecret: clientSecret)
                }
            }
            .disabled(trimmedClientId.isEmpty || clientSecret.isEmpty || appModel.isBusy)
        }
    }

    private var canSave: Bool {
        let hasSecret = appModel.accountSettings(for: network).hasStoredSecret
        switch network {
        case .x:
            return !trimmedClientId.isEmpty
        case .bluesky:
            return !trimmedHandle.isEmpty && (!appPassword.isEmpty || hasSecret)
        case .threads, .instagram:
            return !trimmedClientId.isEmpty && (!clientSecret.isEmpty || hasSecret)
        }
    }

    private var trimmedClientId: String {
        clientId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedHandle: String {
        handle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var removeTitle: String {
        if let label = connection.accountLabel, !label.isEmpty {
            return "Remove the connected \(network.title) account \(label)?"
        }
        return "Remove the connected \(network.title) account?"
    }

    private func save() {
        appModel.saveAccount(
            network: network,
            clientId: clientId,
            clientSecret: clientSecret,
            pds: pds,
            handle: handle,
            appPassword: appPassword
        )
        clientSecret = ""
        appPassword = ""
    }

    private func applyStoredSettings(_ connection: ConnectionInfo) {
        clientSecret = ""
        appPassword = ""
        guard connection.state != .disconnected else { return }
        let settings = appModel.accountSettings(for: network)
        switch network {
        case .x, .threads, .instagram:
            if !settings.clientId.isEmpty {
                clientId = settings.clientId
            }
        case .bluesky:
            pds = settings.pds
            if !settings.handle.isEmpty {
                handle = settings.handle
            }
        }
    }
}

private struct ConnectionStateBadge: View {
    let state: ConnectionState

    var body: some View {
        Text(state.rawValue.capitalized)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch state {
        case .connected: .green
        case .disconnected: .secondary
        case .error: .red
        }
    }

    private var background: Color {
        switch state {
        case .connected: Color.green.opacity(0.15)
        case .disconnected: Color.secondary.opacity(0.12)
        case .error: Color.red.opacity(0.15)
        }
    }
}

private struct MetaCredentialsHelp: View {
    let network: Network
    @Environment(\.dismiss) private var dismiss

    private var callbackURL: String {
        "\(OAuthCallbackServer.origin)/api/connect/\(network.rawValue)/callback"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Find your \(network.title) app credentials")
                .font(.title2.bold())
            Text("These values are in the Meta for Developers console, not your \(network.title) account settings.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                labeled(1, "Go to Meta for Developers, My Apps, then select the app configured for \(network.title).")
                labeled(2, "In the left navigation, open App settings, then Basic.")
                labeled(3, "Copy App ID. For App Secret, select Show, then copy the revealed value.")
                labeled(4, "Paste both values here. Also ensure this OAuth redirect URI is configured: \(callbackURL)")
            }
            Link("Open Meta for Developers", destination: URL(string: "https://developers.facebook.com/apps/")!)
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func labeled(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .monospacedDigit()
            Text(text)
        }
        .font(.body)
    }
}
