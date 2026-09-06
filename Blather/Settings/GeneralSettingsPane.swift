import AppKit
import SwiftUI

struct GeneralSettingsPane: View {
    private var dataDirectory: String {
        AppPaths.dataDirectory.path
    }

    var body: some View {
        Form {
            Section("Data") {
                LabeledContent("Data folder") {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                            .font(.system(size: 14))
                        Text(dataDirectory)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                HStack(spacing: 8) {
                    Button("Reveal in Finder") {
                        let url = URL(fileURLWithPath: dataDirectory, isDirectory: true)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .controlSize(.small)
                }

                Text("Drafts, history, and source media live here. Secrets stay in Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}
