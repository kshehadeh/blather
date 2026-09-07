import SwiftUI

struct ConnectionStatusToolbar: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Menu {
            ForEach(appModel.connections) { connection in
                Button {
                    SettingsWindowController.show(tab: .accounts, network: connection.network)
                } label: {
                    Label {
                        Text(connection.network.title)
                        if let label = connection.accountLabel {
                            Text(label)
                        } else {
                            Text(connection.state.rawValue.capitalized)
                        }
                    } icon: {
                        Image(systemName: connection.network.systemImage)
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

    private var toolbarTitle: String {
        let count = appModel.connectedCount
        if count == 0 { return "No accounts" }
        if count == 1 { return "1 account" }
        return "\(count) accounts"
    }
}
