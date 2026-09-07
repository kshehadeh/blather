import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    static let shared: AppModel = {
        do {
            return AppModel(database: try AppDatabase.openDefault())
        } catch {
            let model = AppModel(database: try! AppDatabase.inMemory())
            model.statusMessage = "Could not open ~/.blather: \(error.localizedDescription)"
            return model
        }
    }()

    var selectedSidebar: SidebarItem = .compose
    var showInspector = true
    var confirmDiscard = false

    var session = DraftSession()
    var drafts: [Draft] = []
    var history: [PublishAttempt] = []
    var connections: [ConnectionInfo] = []
    private var connectionsById: [String: ConnectionInfo] = [:]

    var statusMessage: String?
    var isBusy = false
    var publishProgress: PublishProgress?
    let database: AppDatabase
    private var permalinkBackfillTask: Task<Void, Never>?

    init(database: AppDatabase) {
        self.database = database
        seedMockAccountsIfNeeded()
        reload()
    }

    func reload() {
        drafts = (try? database.drafts.list()) ?? []
        history = (try? database.attempts.list()) ?? []
        let allConnections = (try? database.connections.list(includeRemoved: true)) ?? []
        connectionsById = Dictionary(uniqueKeysWithValues: allConnections.map { ($0.id, $0) })
        connections = allConnections.filter { !$0.isRemoved }
        backfillHistoryPermalinks()
    }

    func backfillHistoryPermalinks() {
        guard permalinkBackfillTask == nil else { return }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        let database = database
        permalinkBackfillTask = Task {
            defer { permalinkBackfillTask = nil }
            let changed = await PublishOrchestrator.backfillMissingPostURLs(database: database)
            if changed {
                history = (try? database.attempts.list()) ?? history
            }
        }
    }

    var connectedCount: Int {
        connections.filter { $0.state == .connected }.count
    }

    func connection(accountId: String) -> ConnectionInfo? {
        connectionsById[accountId]
    }

    func accounts(for network: Network) -> [ConnectionInfo] {
        connections.filter { $0.network == network }
    }

    func newDraft() {
        resetComposer()
        selectedSidebar = .compose
        statusMessage = nil
    }

    func resetComposer() {
        session = DraftSession()
    }

    func saveDraft() {
        do {
            let payload = sessionSnapshot()
            if let id = session.draftId {
                _ = try database.drafts.update(
                    id: id,
                    text: payload.text,
                    mediaIds: payload.mediaIds,
                    accountIds: payload.accountIds,
                    networks: payload.networks,
                    overrides: payload.overrides
                )
                statusMessage = "Draft updated"
            } else {
                let draft = try database.drafts.create(
                    text: payload.text,
                    mediaIds: payload.mediaIds,
                    accountIds: payload.accountIds,
                    networks: payload.networks,
                    overrides: payload.overrides
                )
                session.draftId = draft.id
                statusMessage = "Draft saved"
            }
            reload()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func publish() {
        let accounts = session.accountIds.compactMap(connection(accountId:))
        let progress = startPublishProgress(accounts: accounts)
        isBusy = true
        Task {
            defer { finishPublishProgress() }
            do {
                saveDraft()
                guard let id = session.draftId else {
                    failPublishProgress("Could not save draft")
                    return
                }
                let attempts = try await PublishOrchestrator.publishDraft(id: id, database: database) { attempt in
                    progress.update(attempt)
                }
                reload()
                let failed = attempts.filter { $0.status == .failed }.count
                if failed == 0 {
                    resetComposer()
                } else {
                    session.lastAttempts = attempts
                }
                statusMessage = failed == 0
                    ? "Published everywhere"
                    : "\(attempts.count - failed) succeeded, \(failed) failed (see History to retry)"
            } catch {
                failPublishProgress(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }
    }

    func retryAttempt(id: String) {
        let attempt = try? database.attempts.get(id)
        let accounts = attempt?.accountId.flatMap(connection(accountId:)).map { [$0] } ?? []
        let progress = startPublishProgress(accounts: accounts)
        isBusy = true
        Task {
            defer { finishPublishProgress() }
            do {
                _ = try await PublishOrchestrator.retryAttempt(id: id, database: database) { attempt in
                    progress.update(attempt)
                }
                reload()
                statusMessage = "Retry finished"
            } catch {
                failPublishProgress(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }
    }

    func dismissPublishProgress() {
        publishProgress = nil
    }

    @discardableResult
    private func startPublishProgress(accounts: [ConnectionInfo]) -> PublishProgress {
        let progress = PublishProgress(accounts: accounts)
        publishProgress = progress
        return progress
    }

    private func finishPublishProgress() {
        isBusy = false
        publishProgress?.finish()
    }

    private func failPublishProgress(_ message: String) {
        if let publishProgress {
            publishProgress.fail(message)
        } else {
            statusMessage = message
        }
    }

    func chooseMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MediaStore.allowedContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.title = "Add Media"
        guard panel.runModal() == .OK else { return }
        addMedia(urls: panel.urls)
    }

    func addMedia(urls: [URL]) {
        isBusy = true
        defer { isBusy = false }
        do {
            for url in urls {
                let item = try MediaStore.importFile(from: url, into: database)
                session.media.append(item)
            }
            if !urls.isEmpty {
                statusMessage = urls.count == 1 ? "Added \(urls[0].lastPathComponent)" : "Added \(urls.count) files"
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func pasteMedia() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            addMedia(urls: urls)
            return
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            for image in images {
                guard let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:])
                else { continue }
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(Time.newId()).png")
                do {
                    try png.write(to: temp)
                    addMedia(urls: [temp])
                    try? FileManager.default.removeItem(at: temp)
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    func removeMedia(id: String) {
        try? MediaStore.delete(id: id, from: database)
        session.media.removeAll { $0.id == id }
        for network in Network.allCases {
            if var override = session.overrides[network], let ids = override.mediaIds {
                override.mediaIds = ids.filter { $0 != id }
                session.overrides[network] = override
            }
        }
    }

    func connectX(clientId: String, accountId: String? = nil) {
        let database = database
        Task {
            await runConnect {
                try await ConnectService.connectX(clientId: clientId, accountId: accountId, database: database)
            }
        }
    }

    func connectBluesky(pds: String, handle: String, appPassword: String, accountId: String? = nil) {
        let database = database
        Task {
            await runConnect {
                try await ConnectService.connectBluesky(
                    pds: pds,
                    handle: handle,
                    appPassword: appPassword,
                    accountId: accountId,
                    database: database
                )
            }
        }
    }

    func connectThreads(clientId: String, clientSecret: String, accountId: String? = nil) {
        let database = database
        Task {
            await runConnect {
                try await ConnectService.connectThreads(
                    clientId: clientId,
                    clientSecret: clientSecret,
                    accountId: accountId,
                    database: database
                )
            }
        }
    }

    func connectInstagram(clientId: String, clientSecret: String, accountId: String? = nil) {
        let database = database
        Task {
            await runConnect {
                try await ConnectService.connectInstagram(
                    clientId: clientId,
                    clientSecret: clientSecret,
                    accountId: accountId,
                    database: database
                )
            }
        }
    }

    func disconnect(accountId: String) {
        do {
            let account = connection(accountId: accountId)
            try ConnectService.disconnect(accountId: accountId, database: database)
            reload()
            statusMessage = "\(account?.accountLabel ?? account?.network.title ?? "Account") removed"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func accountSettings(accountId: String?, network: Network) -> AccountConnectSettings {
        accountId.map { AccountSettings.load(accountId: $0, database: database) }
            ?? AccountSettings.empty(network: network)
    }

    func saveAccount(
        network: Network,
        accountId: String?,
        clientId: String,
        clientSecret: String,
        pds: String,
        handle: String,
        appPassword: String,
        forceReconnect: Bool = false
    ) {
        let stored = accountSettings(accountId: accountId, network: network)
        let account = accountId.flatMap(connection(accountId:))
        let storedAppPassword = Credentials.read(BasicCredentials.self, ref: account?.credentialRef)?.secret
        let storedClientSecret = accountId
            .flatMap { TokenAccess.loadTokens(accountId: $0, database: database) }?
            .meta?["clientSecret"]
        switch AccountSettings.plan(
            network: network,
            clientId: clientId,
            clientSecret: clientSecret,
            pds: pds,
            handle: handle,
            appPassword: appPassword,
            stored: stored,
            storedAppPassword: storedAppPassword,
            storedClientSecret: storedClientSecret,
            forceReconnect: forceReconnect
        ) {
        case .noOp:
            statusMessage = "No changes to save"
        case .reconnectBluesky(let pds, let handle, let appPassword):
            connectBluesky(pds: pds, handle: handle, appPassword: appPassword, accountId: accountId)
        case .reconnectX(let clientId):
            connectX(clientId: clientId, accountId: accountId)
        case .reconnectThreads(let clientId, let clientSecret):
            connectThreads(clientId: clientId, clientSecret: clientSecret, accountId: accountId)
        case .reconnectInstagram(let clientId, let clientSecret):
            connectInstagram(clientId: clientId, clientSecret: clientSecret, accountId: accountId)
        }
    }

    func runHealthChecks() {
        isBusy = true
        Task {
            defer { isBusy = false }
            await ConnectService.runHealthChecks(database: database)
            reload()
            statusMessage = "Health checks completed"
        }
    }

    func saveR2(
        accountId: String,
        bucket: String,
        strategy: String,
        publicBaseUrl: String,
        accessKeyId: String,
        secretAccessKey: String,
        jurisdiction: String = ""
    ) {
        do {
            let parsed = R2Endpoint.parse(accountId: accountId, jurisdiction: jurisdiction)
            let trimmedKey = accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedSecret = secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPublic = publicBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            var settings = StoredR2Settings(
                accountId: parsed.accountId,
                bucket: R2Endpoint.normalizeBucket(bucket),
                publicUrlStrategy: strategy,
                publicBaseUrl: trimmedPublic.isEmpty ? nil : trimmedPublic,
                credentialRef: nil,
                jurisdiction: parsed.jurisdiction
            )
            if !trimmedKey.isEmpty, !trimmedSecret.isEmpty {
                let existing = try database.r2.get()
                Credentials.delete(ref: existing?.credentialRef)
                let ref = Credentials.makeRef(kind: "r2", owner: "r2")
                try Credentials.store(ref, value: R2Credentials(accessKeyId: trimmedKey, secretAccessKey: trimmedSecret))
                settings.credentialRef = ref
            }
            try database.r2.save(settings)
            R2.overrideStager = nil
            statusMessage = "R2 settings saved"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func testR2() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await R2.stager(database: database).testConnection()
                statusMessage = "Connection OK"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func removeR2() {
        do {
            if let existing = try database.r2.get() {
                Credentials.delete(ref: existing.credentialRef)
            }
            try database.r2.clear()
            R2.overrideStager = nil
            statusMessage = "R2 settings removed"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    var r2: R2SettingsView {
        (try? database.r2.view()) ?? R2SettingsView(configured: false, hasCredentials: false)
    }

    private func runConnect(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
            reload()
            statusMessage = "Connected"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func moveMedia(index: Int, by offset: Int) {
        let target = index + offset
        guard session.media.indices.contains(index), session.media.indices.contains(target) else { return }
        session.media.swapAt(index, target)
    }

    func discardDraft() {
        if let id = session.draftId {
            try? database.drafts.remove(id)
        }
        resetComposer()
        statusMessage = "Discarded"
        confirmDiscard = false
        reload()
    }

    func openDraft(_ draft: Draft) {
        let mediaIds = Set(draft.mediaIds + draft.overrides.values.flatMap { $0.mediaIds ?? [] })
        let media = (try? database.media.byIds(Array(mediaIds))) ?? []
        let accounts = (try? database.connections.list(includeRemoved: true)) ?? []
        session = DraftSession(draft: draft, media: media, accounts: accounts)
        selectedSidebar = .compose
    }

    private func sessionSnapshot() -> (
        text: String,
        mediaIds: [String],
        accountIds: [String],
        networks: [Network],
        overrides: [Network: NetworkOverride]
    ) {
        let accountIds = session.accountIds.sorted()
        let networks = Network.allCases.filter { session.networks.contains($0) }
        return (
            session.text,
            session.media.map(\.id),
            accountIds,
            networks,
            session.showsDestinationOverrides ? session.overrides : [:]
        )
    }

    private func seedMockAccountsIfNeeded() {
        guard AdapterRegistry.useMocks,
              ((try? database.connections.list(includeRemoved: true)) ?? []).isEmpty
        else { return }
        for network in Network.allCases {
            try? database.connections.upsert(
                accountId: "mock-\(network.rawValue)",
                network: network,
                providerAccountId: "mock-\(network.rawValue)",
                state: .connected,
                accountLabel: "@mock-\(network.rawValue)",
                meta: [:]
            )
        }
        try? database.connections.upsert(
            accountId: "mock-x-2",
            network: .x,
            providerAccountId: "mock-x-2",
            state: .connected,
            accountLabel: "@mock-x-2",
            meta: [:]
        )
    }
}

@Observable
final class DraftSession {
    var draftId: String?
    var text: String = ""
    var media: [MediaItem] = []
    var accountIds: Set<String> = []
    private var accountNetworks: [String: Network] = [:]
    var overrides: [Network: NetworkOverride] = [:]
    var lastAttempts: [PublishAttempt] = []

    init() {}

    init(draft: Draft, media: [MediaItem], accounts: [ConnectionInfo]) {
        draftId = draft.id
        text = draft.text
        self.media = media
        accountIds = Set(draft.accountIds)
        accountNetworks = Dictionary(
            uniqueKeysWithValues: accounts
                .filter { accountIds.contains($0.id) }
                .map { ($0.id, $0.network) }
        )
        overrides = networks.count > 1 ? draft.overrides : [:]
    }

    var hasChanges: Bool {
        draftId != nil
            || !text.isEmpty
            || !media.isEmpty
            || !accountIds.isEmpty
            || !overrides.isEmpty
            || !lastAttempts.isEmpty
    }

    var showsDestinationOverrides: Bool { networks.count > 1 }

    var networks: Set<Network> {
        Set(accountIds.compactMap { accountNetworks[$0] })
    }

    func setAccount(_ account: ConnectionInfo, enabled: Bool) {
        if enabled {
            accountIds.insert(account.id)
            accountNetworks[account.id] = account.network
            return
        }
        accountIds.remove(account.id)
        accountNetworks[account.id] = nil
        if !networks.contains(account.network) {
            overrides[account.network] = nil
        }
        if !showsDestinationOverrides {
            overrides.removeAll()
        }
    }

    func resolvedContent(for network: Network) -> ResolvedContent {
        let override = showsDestinationOverrides ? overrides[network] : nil
        let ids = override?.mediaIds ?? media.map(\.id)
        let resolvedMedia = ids.compactMap { id in media.first { $0.id == id } }
        return ResolvedContent(text: override?.text ?? text, media: resolvedMedia)
    }

    func warnings(for network: Network) -> [String] {
        let caps = Capabilities.capabilities(for: network)
        let resolved = resolvedContent(for: network)
        var warnings: [String] = []
        if resolved.text.count > caps.maxChars {
            warnings.append("Text over limit: \(resolved.text.count)/\(caps.maxChars)")
        }
        let images = resolved.media.filter { $0.kind == .image }
        let videos = resolved.media.filter { $0.kind == .video }
        for image in images {
            if let maxBytes = caps.maxImageBytes, image.size > maxBytes {
                let mb = maxBytes / 1_000_000
                if caps.autoOptimizeImages {
                    warnings.append("\(image.name) will be converted to a JPEG under the \(mb)MB image limit")
                } else {
                    warnings.append("\(image.name) exceeds the \(mb)MB image limit")
                }
            }
        }
        if caps.requiresMedia, resolved.media.isEmpty {
            warnings.append("Media required")
        }
        if images.count > caps.maxImages {
            warnings.append("Too many images (max \(caps.maxImages))")
        }
        if videos.count > 1 {
            warnings.append("Only one video allowed")
        }
        if !images.isEmpty, !videos.isEmpty, !caps.allowsMixedMedia {
            warnings.append("Cannot mix images and video")
        }
        return warnings
    }
}
