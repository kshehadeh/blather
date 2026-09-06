import AppKit
import SwiftUI

struct AboutSettingsPane: View {
    @ObservedObject private var updaterManager = UpdaterManager.shared

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (v?, b?): return "Version \(v) (\(b))"
        case let (v?, nil): return "Version \(v)"
        default: return "Version 0.1.0"
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Blather")
                            .font(.largeTitle.bold())
                        Text(versionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Compose once, publish to your own accounts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Privacy") {
                Text("Blather is local-only. There is no hosted backend and no telemetry. Provider credentials live in the macOS Keychain.")
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle(isOn: Binding(
                    get: { updaterManager.automaticallyChecksForUpdates },
                    set: { updaterManager.automaticallyChecksForUpdates = $0 }
                )) {
                    Text("Automatically check for updates")
                }
                .toggleStyle(.switch)

                Button("Check for Updates…") {
                    updaterManager.checkForUpdates()
                }
                .disabled(!updaterManager.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}
