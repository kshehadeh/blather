import SwiftUI

@main
struct BlatherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel = AppModel.shared

    var body: some Scene {
        WindowGroup {
            MainSplitView()
                .environment(appModel)
                .frame(minWidth: 900, minHeight: 700)
        }
        .defaultSize(width: 1280, height: 900)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .commands {
            AppCommands()
        }
    }
}
