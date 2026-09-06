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
    let network: Network
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var pds = "https://bsky.social"
    @State private var handle = ""
    @State private var appPassword = ""
    @State private var showingHelp = false

    var body: some View {
        let connection = appModel.connection(for: network)
        let caps = Capabilities.capabilities(for: network)

        Section {
            LabeledContent("Status") {
                Text(connection.state.rawValue.capitalized)
                    .foregroundStyle(connection.state == .error ? .red : .secondary)
            }
            if let label = connection.accountLabel {
                LabeledContent("Account", value: label)
            }
            if let error = connection.error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            Text("\(caps.maxChars) characters, up to \(caps.maxImages) images\(caps.allowsVideo ? ", video" : "")\(caps.requiresMedia ? ", media required" : "")")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(caps.notes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if connection.state == .disconnected {
                connectFields
            } else {
                Button("Disconnect", role: .destructive) {
                    appModel.disconnect(network: network)
                }
            }
        } header: {
            Label(network.title, systemImage: network.systemImage)
        }
        .sheet(isPresented: $showingHelp) {
            MetaCredentialsHelp(network: network)
        }
    }

    @ViewBuilder
    private var connectFields: some View {
        switch network {
        case .x:
            TextField("Client ID", text: $clientId)
            Button("Connect") {
                appModel.connectX(clientId: clientId.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .disabled(clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appModel.isBusy)
        case .bluesky:
            TextField("PDS", text: $pds)
            TextField("Handle", text: $handle)
            SecureField("App password", text: $appPassword)
            Button("Connect") {
                appModel.connectBluesky(
                    pds: pds.trimmingCharacters(in: .whitespacesAndNewlines),
                    handle: handle.trimmingCharacters(in: .whitespacesAndNewlines),
                    appPassword: appPassword
                )
            }
            .disabled(handle.isEmpty || appPassword.isEmpty || appModel.isBusy)
        case .threads, .instagram:
            TextField("App ID", text: $clientId)
            SecureField("App Secret", text: $clientSecret)
            Button("Where do I find the App ID and App Secret?") {
                showingHelp = true
            }
            .buttonStyle(.link)
            Button("Connect") {
                if network == .threads {
                    appModel.connectThreads(clientId: clientId, clientSecret: clientSecret)
                } else {
                    appModel.connectInstagram(clientId: clientId, clientSecret: clientSecret)
                }
            }
            .disabled(clientId.isEmpty || clientSecret.isEmpty || appModel.isBusy)
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
