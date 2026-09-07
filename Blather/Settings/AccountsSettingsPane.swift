import SwiftUI

struct AccountsSettingsPane: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Form {
            Section {
                Text("Connect every account you want to publish to. Secrets stay in the macOS Keychain.")
                    .foregroundStyle(.secondary)
                Button("Run health checks") {
                    appModel.runHealthChecks()
                }
                .disabled(appModel.isBusy)
            }

            if let message = appModel.statusMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Network.allCases) { network in
                NetworkAccountsSection(network: network)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

private struct NetworkAccountsSection: View {
    @Environment(AppModel.self) private var appModel
    @State private var navigation = SettingsNavigation.shared
    let network: Network
    @State private var isExpanded = false
    @State private var isAdding = false
    @State private var initialized = false

    private var accounts: [ConnectionInfo] {
        var accounts = appModel.accounts(for: network)
        if let focusedAccountId = navigation.focusedAccountId,
           let focused = appModel.connection(accountId: focusedAccountId),
           focused.network == network,
           !accounts.contains(where: { $0.id == focused.id })
        {
            accounts.append(focused)
        }
        return accounts
    }

    var body: some View {
        Section {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    NetworkIcon(network: network)
                        .foregroundStyle(.secondary)
                    Text(network.title)
                    Spacer()
                    Text(accountSummary)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("account-section-\(network.rawValue)")

            if isExpanded {
                ForEach(accounts) { account in
                    AccountEditor(account: account, network: network)
                        .id("\(account.id)-\(navigation.focusedAccountId == account.id ? navigation.focusGeneration : 0)")
                }

                if isAdding {
                    AccountEditor(account: nil, network: network) {
                        withAnimation(.snappy) { isAdding = false }
                    }
                } else {
                    Button {
                        withAnimation(.snappy) { isAdding = true }
                    } label: {
                        Label("Add Account…", systemImage: "plus")
                    }
                    .disabled(appModel.isBusy)
                    .accessibilityIdentifier("add-account-\(network.rawValue)")
                }
            }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            isExpanded = navigation.focusedNetwork == network || accounts.isEmpty
        }
        .onChange(of: navigation.focusGeneration) { _, _ in
            guard let focused = navigation.focusedNetwork else { return }
            withAnimation(.snappy) {
                isExpanded = focused == network
                if focused == network, accounts.isEmpty {
                    isAdding = true
                }
            }
        }
        .onChange(of: accounts.map(\.id)) { oldValue, newValue in
            if isAdding, newValue.count > oldValue.count {
                isAdding = false
            }
        }
        .onChange(of: accounts.map(\.credentialRef)) { oldValue, newValue in
            if isAdding, oldValue != newValue {
                isAdding = false
            }
        }
    }

    private var accountSummary: String {
        if accounts.isEmpty { return "No accounts" }
        if accounts.count == 1 { return accounts[0].accountLabel ?? "1 account" }
        return "\(accounts.count) accounts"
    }
}

private struct AccountEditor: View {
    @Environment(AppModel.self) private var appModel
    let account: ConnectionInfo?
    let network: Network
    let onCancel: (() -> Void)?
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var pds = AccountSettings.defaultPDS
    @State private var handle = ""
    @State private var appPassword = ""
    @State private var showingHelp = false
    @State private var confirmRemove = false
    @State private var isExpanded: Bool
    @State private var storedSettings = AccountConnectSettings()

    init(account: ConnectionInfo?, network: Network, onCancel: (() -> Void)? = nil) {
        self.account = account
        self.network = network
        self.onCancel = onCancel
        _isExpanded = State(
            initialValue: account == nil
                || account?.state != .connected
                || SettingsNavigation.shared.focusedAccountId == account?.id
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(account?.accountLabel ?? "New \(network.title) account")
                    Spacer()
                    if let account {
                        ConnectionStateBadge(state: account.state)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                if let error = account?.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                credentialFields
                actionButtons
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingHelp) {
            MetaCredentialsHelp(network: network)
        }
        .confirmationDialog(removeTitle, isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Account", role: .destructive) {
                guard let account else { return }
                appModel.disconnect(accountId: account.id)
                clientSecret = ""
                appPassword = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes this account's stored credentials. Drafts and history are kept.")
        }
        .onAppear {
            reloadStoredSettings()
        }
        .onChange(of: account?.credentialRef) { _, _ in
            reloadStoredSettings()
        }
    }

    @ViewBuilder
    private var credentialFields: some View {
        let hasSecret = storedSettings.hasStoredSecret
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

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if account == nil || account?.state != .connected {
                Button(account == nil ? "Connect Account" : "Reconnect") {
                    save(forceReconnect: true)
                }
                .disabled(!canSave || appModel.isBusy)
                if account == nil {
                    Button("Cancel") {
                        onCancel?()
                    }
                }
            } else {
                Button("Save") {
                    save()
                }
                .disabled(!canSave || appModel.isBusy)
                .accessibilityIdentifier("save-account-\(account?.id ?? network.rawValue)")
                Button("Remove Account…", role: .destructive) {
                    confirmRemove = true
                }
                .disabled(appModel.isBusy)
                .accessibilityIdentifier("remove-account-\(account?.id ?? network.rawValue)")
            }
        }
    }

    private var canSave: Bool {
        switch network {
        case .x:
            return !trimmedClientId.isEmpty
        case .bluesky:
            return !trimmedHandle.isEmpty && (!appPassword.isEmpty || storedSettings.hasStoredSecret)
        case .threads, .instagram:
            return !trimmedClientId.isEmpty && (!clientSecret.isEmpty || storedSettings.hasStoredSecret)
        }
    }

    private var trimmedClientId: String {
        clientId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedHandle: String {
        handle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var removeTitle: String {
        "Remove \(account?.accountLabel ?? "this \(network.title) account")?"
    }

    private func save(forceReconnect: Bool = false) {
        appModel.saveAccount(
            network: network,
            accountId: account?.id,
            clientId: clientId,
            clientSecret: clientSecret,
            pds: pds,
            handle: handle,
            appPassword: appPassword,
            forceReconnect: forceReconnect
        )
        clientSecret = ""
        appPassword = ""
    }

    private func reloadStoredSettings() {
        clientSecret = ""
        appPassword = ""
        storedSettings = appModel.accountSettings(accountId: account?.id, network: network)
        switch network {
        case .x, .threads, .instagram:
            clientId = storedSettings.clientId
        case .bluesky:
            pds = storedSettings.pds
            handle = storedSettings.handle
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
