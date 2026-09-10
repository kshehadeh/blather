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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
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
            AccountSetupHelp(network: network)
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
            guidedTextField(
                "Client ID",
                text: $clientId,
                guidance: AccountFieldGuidance.xClientId
            )
        case .bluesky:
            guidedTextField(
                "PDS",
                text: $pds,
                guidance: AccountFieldGuidance.blueskyPDS
            )
            guidedTextField(
                "Handle",
                text: $handle,
                guidance: AccountFieldGuidance.blueskyHandle
            )
            guidedSecretField(
                "App password",
                text: $appPassword,
                hasStoredSecret: hasSecret,
                guidance: AccountFieldGuidance.blueskyAppPassword
            )
        case .threads, .instagram:
            guidedTextField(
                "App ID",
                text: $clientId,
                guidance: AccountFieldGuidance.metaAppId(for: network)
            )
            guidedSecretField(
                "App Secret",
                text: $clientSecret,
                hasStoredSecret: hasSecret,
                guidance: AccountFieldGuidance.metaAppSecret(for: network)
            )
        case .linkedin:
            guidedTextField(
                "Client ID",
                text: $clientId,
                guidance: AccountFieldGuidance.linkedinClientId
            )
            guidedSecretField(
                "Client Secret",
                text: $clientSecret,
                hasStoredSecret: hasSecret,
                guidance: AccountFieldGuidance.linkedinClientSecret
            )
        }
        Button(setupHelpButtonTitle) {
            showingHelp = true
        }
        .buttonStyle(.link)
        .accessibilityIdentifier("account-help-\(network.rawValue)")
    }

    private func guidedTextField(
        _ title: String,
        text: Binding<String>,
        guidance: AccountFieldGuidance
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField(title, text: text, prompt: Text(guidance.example))
            AccountFieldHint(guidance: guidance)
        }
    }

    private func guidedSecretField(
        _ title: String,
        text: Binding<String>,
        hasStoredSecret: Bool,
        guidance: AccountFieldGuidance
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            StoredSecretField(title, text: text, hasStoredSecret: hasStoredSecret)
            AccountFieldHint(guidance: guidance)
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
        case .threads, .instagram, .linkedin:
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

    private var setupHelpButtonTitle: String {
        switch network {
        case .x:
            "Where do I find the Client ID?"
        case .bluesky:
            "Where do I find my handle and app password?"
        case .threads, .instagram:
            "Where do I find the App ID and App Secret?"
        case .linkedin:
            "Where do I find the Client ID and Client Secret?"
        }
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
        case .x, .threads, .instagram, .linkedin:
            clientId = storedSettings.clientId
        case .bluesky:
            pds = storedSettings.pds
            handle = storedSettings.handle
        }
    }
}

struct AccountFieldGuidance: Equatable {
    var example: String
    var help: String

    static let xClientId = AccountFieldGuidance(
        example: "e.g. abc123ExampleClientId",
        help: "Copy the OAuth 2.0 Client ID from X Developer Portal. Do not use the API Key, App ID, client secret, or bearer token."
    )

    static let blueskyPDS = AccountFieldGuidance(
        example: "e.g. https://bsky.social",
        help: "Use https://bsky.social unless your account provider gave you a custom PDS server URL."
    )

    static let blueskyHandle = AccountFieldGuidance(
        example: "e.g. alice.bsky.social",
        help: "Enter the handle shown on your Bluesky profile without @, such as alice.bsky.social or alice.example.com. Do not enter an email address such as alice@example.com."
    )

    static let blueskyAppPassword = AccountFieldGuidance(
        example: "e.g. xxxx-xxxx-xxxx-xxxx",
        help: "Create an app password in Bluesky Settings, Privacy and security, App passwords. Do not use your normal account password."
    )

    static let linkedinClientId = AccountFieldGuidance(
        example: "e.g. 77abc123de456f",
        help: "Copy the Client ID from your LinkedIn developer app's Auth tab. Do not use an Access Token or your LinkedIn password."
    )

    static let linkedinClientSecret = AccountFieldGuidance(
        example: "Example: the secret shown beside your Client ID",
        help: "Reveal and copy the Client Secret from the same Auth tab. This is not an access token or your LinkedIn password."
    )

    static func metaAppId(for network: Network) -> AccountFieldGuidance {
        switch network {
        case .threads:
            AccountFieldGuidance(
                example: "e.g. 123456789012345",
                help: "Copy the App ID from the Meta developer app configured for the Threads API."
            )
        case .instagram:
            AccountFieldGuidance(
                example: "e.g. 123456789012345",
                help: "Copy the Instagram App ID from the Instagram product's API setup in Meta for Developers."
            )
        case .x, .bluesky, .linkedin:
            preconditionFailure("Meta guidance is only available for Threads and Instagram")
        }
    }

    static func metaAppSecret(for network: Network) -> AccountFieldGuidance {
        switch network {
        case .threads:
            AccountFieldGuidance(
                example: "Example: the secret shown beside your App ID",
                help: "Reveal and copy App Secret from the same Meta developer app. This is not an access token or your social account password."
            )
        case .instagram:
            AccountFieldGuidance(
                example: "Example: the secret shown beside your Instagram App ID",
                help: "Reveal and copy Instagram App Secret from the Instagram product setup. This is not an access token or your Instagram password."
            )
        case .x, .bluesky, .linkedin:
            preconditionFailure("Meta guidance is only available for Threads and Instagram")
        }
    }
}

private struct AccountFieldHint: View {
    let guidance: AccountFieldGuidance

    var body: some View {
        Text("\(guidance.example). \(guidance.help)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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

struct AccountSetupHelpContent: Equatable {
    var title: String
    var intro: String
    var steps: [String]
    var linkTitle: String
    var linkURL: URL

    static func forNetwork(_ network: Network) -> AccountSetupHelpContent {
        let callbackURL = "\(OAuthCallbackServer.origin)/api/connect/\(network.rawValue)/callback"
        switch network {
        case .x:
            return AccountSetupHelpContent(
                title: "Find your X Client ID",
                intro: "This value is in the X Developer Portal, not your X account settings.",
                steps: [
                    "Go to the X Developer Portal, create or select a project, then open the app you want Blather to use.",
                    "Open User authentication settings. Enable OAuth 2.0, set App permissions to Read and write, and choose a public or native app type.",
                    "Add this exact Callback URI / Redirect URL: \(callbackURL)",
                    "Open Keys and tokens, then copy the OAuth 2.0 Client ID. Do not use the API Key, App ID, Client Secret, or bearer token.",
                ],
                linkTitle: "Open X Developer Portal",
                linkURL: URL(string: "https://developer.x.com/")!
            )
        case .bluesky:
            return AccountSetupHelpContent(
                title: "Find your Bluesky credentials",
                intro: "Bluesky does not need a developer app. You need your handle and a dedicated app password.",
                steps: [
                    "Copy your handle from your Bluesky profile without the leading @, for example alice.bsky.social. Do not enter an email address.",
                    "In Bluesky, open Settings, Privacy and security, then App passwords.",
                    "Create an app password named something like Blather, then copy the generated password. Do not use your normal account password.",
                    "Paste the handle and app password here. Leave PDS as https://bsky.social unless your host gave you a custom PDS URL.",
                ],
                linkTitle: "Open Bluesky app passwords",
                linkURL: URL(string: "https://bsky.app/settings/app-passwords")!
            )
        case .threads, .instagram:
            let appIdSource: String
            let credentialNames: String
            if network == .instagram {
                appIdSource = "In the left navigation, open the Instagram product, then API setup with Instagram login."
                credentialNames = "Instagram App ID and Instagram App Secret"
            } else {
                appIdSource = "In the left navigation, open App settings, then Basic."
                credentialNames = "App ID and App Secret"
            }
            return AccountSetupHelpContent(
                title: "Find your \(network.title) app credentials",
                intro: "These values are in the Meta for Developers console, not your \(network.title) account settings.",
                steps: [
                    "Go to Meta for Developers, My Apps, then select the app configured for \(network.title).",
                    appIdSource,
                    "Copy \(credentialNames). For the secret, select Show, then copy the revealed value.",
                    "Paste both values here. Also ensure this OAuth redirect URI is configured: \(callbackURL)",
                ],
                linkTitle: "Open Meta for Developers",
                linkURL: URL(string: "https://developers.facebook.com/apps/")!
            )
        case .linkedin:
            return AccountSetupHelpContent(
                title: "Find your LinkedIn app credentials",
                intro: "These values are in the LinkedIn Developers portal, not your LinkedIn account settings.",
                steps: [
                    "Go to LinkedIn Developers and create an app. LinkedIn requires associating a LinkedIn Page; that Page is only the app's publisher, not a posting destination.",
                    "In the app's Products tab, add the Share on LinkedIn and Sign In with LinkedIn using OpenID Connect products.",
                    "Open the Auth tab, then copy the Client ID and reveal and copy the Client Secret.",
                    "Still in the Auth tab, add this exact Redirect URL: \(callbackURL), then paste both values here.",
                ],
                linkTitle: "Open LinkedIn Developers",
                linkURL: URL(string: "https://www.linkedin.com/developers/apps")!
            )
        }
    }
}

private struct AccountSetupHelp: View {
    let network: Network
    @Environment(\.dismiss) private var dismiss

    private var content: AccountSetupHelpContent {
        AccountSetupHelpContent.forNetwork(network)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(content.title)
                .font(.title2.bold())
            Text(content.intro)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(content.steps.enumerated()), id: \.offset) { index, step in
                    labeled(index + 1, step)
                }
            }
            Link(content.linkTitle, destination: content.linkURL)
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
