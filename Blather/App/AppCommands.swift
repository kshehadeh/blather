import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                SettingsWindowController.show(tab: .accounts)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Check for Updates…") {
                UpdaterManager.shared.checkForUpdates()
            }
            .disabled(!UpdaterManager.shared.canCheckForUpdates)
        }

        CommandGroup(replacing: .newItem) {
            Button("New Draft") {
                AppModel.shared.newDraft()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("Save Draft") {
                AppModel.shared.saveDraft()
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Publish") {
                AppModel.shared.publish()
            }
            .keyboardShortcut(.return, modifiers: .command)

            Divider()

            Button("Discard Draft") {
                AppModel.shared.confirmDiscard = true
            }

            Divider()

            Button("Add Media…") {
                AppModel.shared.chooseMedia()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandMenu("View") {
            Button("Compose") {
                AppModel.shared.selectedSidebar = .compose
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("History") {
                AppModel.shared.selectedSidebar = .history
            }
            .keyboardShortcut("2", modifiers: .command)

            Divider()

            Button(AppModel.shared.showInspector ? "Hide Inspector" : "Show Inspector") {
                AppModel.shared.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
