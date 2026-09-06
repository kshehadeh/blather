import Foundation
import Network
import Security

enum OAuthServerError: Error, LocalizedError {
    case portInUse
    case tlsIdentityFailed
    case timeout
    case denied(String)
    case missingCode
    case invalidState
    case missingConfig
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .portInUse:
            "Port 3000 is in use. Quit the other program using it, then try connecting again."
        case .tlsIdentityFailed:
            "Could not create a local HTTPS certificate for OAuth."
        case .timeout:
            "Timed out waiting for the browser to finish connecting."
        case .denied(let message): message
        case .missingCode: "missing code or state"
        case .invalidState: "Invalid or expired OAuth state"
        case .missingConfig: "missing app configuration"
        case .failed(let message): message
        }
    }
}

final class OAuthCallbackServer: @unchecked Sendable {
    static let port: UInt16 = 3000
    static let origin = "https://127.0.0.1:3000"

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.blather.oauth")
    private var onRequest: ((URL) async -> String)?

    func start(handler: @escaping (URL) async -> String) throws {
        onRequest = handler
        let identity = try TLSIdentity.loadOrCreate()
        let tls = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create(identity) else {
            throw OAuthServerError.tlsIdentityFailed
        }
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.acceptLocalOnly = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)
        } catch {
            throw OAuthServerError.portInUse
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        let started = DispatchSemaphore(value: 0)
        var failed = false
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                started.signal()
            case .failed:
                failed = true
                started.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)
        _ = started.wait(timeout: .now() + 2)
        if failed {
            listener.cancel()
            throw OAuthServerError.portInUse
        }
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        onRequest = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            Task {
                let html = await self.respond(to: request)
                let response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: \(html.utf8.count)\r\n\r\n\(html)".utf8)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func respond(to request: String) async -> String {
        let first = request.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = first.split(separator: " ")
        guard parts.count >= 2, let url = URL(string: "\(Self.origin)\(parts[1])") else {
            return oauthResultHTML(network: "Blather", error: "Invalid OAuth callback")
        }
        if let onRequest {
            return await onRequest(url)
        }
        return oauthResultHTML(network: "Blather", error: "No OAuth flow is active")
    }
}

func oauthResultHTML(network: String, error: String?) -> String {
    let title = error == nil ? "Connection complete" : "Connection failed"
    let detail = error == nil
        ? "\(network) is connected. Return to Blather to continue."
        : "\(network): \(error ?? "")"
    func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
    return """
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>\(escape(title))</title></head>
      <body><main><h1>\(escape(title))</h1><p>\(escape(detail))</p></main></body>
    </html>
    """
}
