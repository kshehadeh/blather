import SwiftUI

struct MainSplitView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        NavigationSplitView {
            List(selection: $appModel.selectedSidebar) {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                        .accessibilityIdentifier("sidebar-\(item.rawValue)")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
            .scrollEdgeEffectStyleSoftIfAvailable()
        } detail: {
            switch appModel.selectedSidebar {
            case .compose:
                ComposerView()
            case .history:
                HistoryView()
            }
        }
        .inspector(isPresented: $appModel.showInspector) {
            DestinationInspector()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .navigationTitle(appModel.selectedSidebar.title)
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appModel.newDraft()
                } label: {
                    Label("New Draft", systemImage: "square.and.pencil")
                }
                .help("New Draft")

                Button {
                    appModel.saveDraft()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .help("Save Draft")
                .disabled(appModel.selectedSidebar != .compose)

                Button {
                    appModel.publish()
                } label: {
                    Label("Publish", systemImage: "paperplane")
                }
                .help("Publish")
                .disabled(appModel.session.accountIds.isEmpty || appModel.selectedSidebar != .compose || appModel.isBusy)

                Button {
                    appModel.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Toggle Inspector")
            }

            ToolbarItem(placement: .automatic) {
                ConnectionStatusToolbar()
            }
        }
        .sheet(item: $appModel.publishProgress) { progress in
            PublishProgressSheet(progress: progress) {
                appModel.dismissPublishProgress()
            }
        }
        .confirmationDialog(
            "Discard this draft?",
            isPresented: $appModel.confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                appModel.discardDraft()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current text, media, and destination choices will be cleared.")
        }
    }
}

extension View {
    @ViewBuilder
    func scrollEdgeEffectStyleSoftIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}
