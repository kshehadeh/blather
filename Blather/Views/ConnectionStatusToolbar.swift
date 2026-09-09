import SwiftUI

struct ConnectionStatusToolbar: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Menu {
            ForEach(appModel.connections) { connection in
                Button {
                    SettingsWindowController.show(
                        tab: .accounts,
                        network: connection.network,
                        accountId: connection.id
                    )
                } label: {
                    Label {
                        Text(itemTitle(for: connection))
                    } icon: {
                        NetworkIcon(network: connection.network)
                    }
                }
            }
            Divider()
            Button("Manage Accounts…") {
                SettingsWindowController.show(tab: .accounts)
            }
        } label: {
            Label {
                Text(toolbarTitle)
            } icon: {
                Image(systemName: "person.crop.circle")
            }
        }
        .help("Connected accounts")
    }

    private func itemTitle(for connection: ConnectionInfo) -> String {
        let detail = connection.accountLabel ?? connection.state.rawValue.capitalized
        return "\(connection.network.title) — \(detail)"
    }

    private var toolbarTitle: String {
        let count = appModel.connectedCount
        if count == 0 { return "No accounts" }
        if count == 1 { return "1 account" }
        return "\(count) accounts"
    }
}
