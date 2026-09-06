import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updaterManager = UpdaterManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        updaterManager.start()
        do {
            try PublishOrchestrator.recoverInterrupted(database: AppModel.shared.database)
            Task {
                _ = await R2.cleanupOrphans(database: AppModel.shared.database)
            }
            AppModel.shared.reload()
        } catch {
            AppModel.shared.statusMessage = error.localizedDescription
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
