import SwiftUI

struct MediaStagingSettingsPane: View {
    @Environment(AppModel.self) private var appModel
    @State private var accountId = ""
    @State private var bucket = ""
    @State private var strategy = "presigned"
    @State private var publicBaseUrl = ""
    @State private var accessKeyId = ""
    @State private var secretAccessKey = ""
    @State private var jurisdiction = ""

    var body: some View {
        let r2 = appModel.r2
        Form {
            Section {
                Text("Threads and Instagram need media at a public HTTPS URL while publishing. Blather stages files in your Cloudflare R2 bucket, then removes them.")
                    .foregroundStyle(.secondary)
            }

            Section("Cloudflare R2") {
                LabeledContent("Status", value: r2.configured ? "Configured" : "Not configured")
                TextField("Account ID", text: $accountId)
                TextField("Bucket", text: $bucket)
                Picker("Jurisdiction", selection: $jurisdiction) {
                    Text("Automatic (default)").tag("")
                    Text("European Union (eu)").tag("eu")
                    Text("United States (us)").tag("us")
                    Text("FedRAMP").tag("fedramp")
                }
                .pickerStyle(.menu)
                Text("Only change this if you chose Specify jurisdiction when creating the bucket. A location hint is not a jurisdiction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Media URL strategy", selection: $strategy) {
                    Text("Presigned URLs, bucket stays private").tag("presigned")
                    Text("Public R2 bucket URL").tag("public")
                }
                .pickerStyle(.menu)
                TextField("Public R2 bucket URL", text: $publicBaseUrl)
                TextField(r2.hasCredentials ? "Access key ID (leave blank to keep)" : "R2 access key ID", text: $accessKeyId)
                SecureField(r2.hasCredentials ? "Secret (leave blank to keep)" : "R2 secret access key", text: $secretAccessKey)
                Text("Never stored in the local database.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Save") {
                        appModel.saveR2(
                            accountId: accountId,
                            bucket: bucket,
                            strategy: strategy,
                            publicBaseUrl: publicBaseUrl,
                            accessKeyId: accessKeyId,
                            secretAccessKey: secretAccessKey,
                            jurisdiction: jurisdiction
                        )
                        let saved = appModel.r2
                        accountId = saved.accountId ?? accountId
                        bucket = saved.bucket ?? bucket
                        jurisdiction = saved.jurisdiction ?? ""
                        accessKeyId = ""
                        secretAccessKey = ""
                    }
                    .disabled(accountId.isEmpty || bucket.isEmpty || appModel.isBusy)
                    Button("Test connection") {
                        appModel.testR2()
                    }
                    .disabled(!r2.configured || appModel.isBusy)
                    Button("Remove", role: .destructive) {
                        appModel.removeR2()
                        accountId = ""
                        bucket = ""
                        publicBaseUrl = ""
                        accessKeyId = ""
                        secretAccessKey = ""
                        jurisdiction = ""
                    }
                    .disabled(!r2.configured || appModel.isBusy)
                }

                if let message = appModel.statusMessage {
                    Text(message)
                        .foregroundStyle(.secondary)
                }

                Text("R2 staging objects older than 24 hours are swept at startup.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .onAppear {
            accountId = r2.accountId ?? accountId
            bucket = r2.bucket ?? bucket
            strategy = r2.publicUrlStrategy ?? strategy
            publicBaseUrl = r2.publicBaseUrl ?? publicBaseUrl
            jurisdiction = r2.jurisdiction ?? jurisdiction
        }
    }
}
