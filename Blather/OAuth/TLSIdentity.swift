import Foundation
import Security

enum TLSIdentity {
    static let password = "blather-oauth-tls"

    static func loadOrCreate() throws -> SecIdentity {
        let dir = AppPaths.dataDirectory.appendingPathComponent("oauth-tls", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p12 = dir.appendingPathComponent("identity.p12")
        if FileManager.default.fileExists(atPath: p12.path),
           let identity = importPKCS12(url: p12)
        {
            return identity
        }
        try generate(into: dir)
        guard let identity = importPKCS12(url: p12) else {
            throw OAuthServerError.tlsIdentityFailed
        }
        return identity
    }

    private static func generate(into dir: URL) throws {
        let cert = dir.appendingPathComponent("cert.pem")
        let key = dir.appendingPathComponent("key.pem")
        let p12 = dir.appendingPathComponent("identity.p12")
        let openssl = "/usr/bin/openssl"
        try run(openssl, [
            "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "3650", "-nodes",
            "-keyout", key.path, "-out", cert.path,
            "-subj", "/CN=127.0.0.1",
            "-addext", "subjectAltName=IP:127.0.0.1",
        ])
        try run(openssl, [
            "pkcs12", "-export",
            "-in", cert.path,
            "-inkey", key.path,
            "-out", p12.path,
            "-passout", "pass:\(password)",
        ])
    }

    private static func importPKCS12(url: URL) -> SecIdentity? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let identity = array.first?[kSecImportItemIdentity as String]
        else { return nil }
        return (identity as! SecIdentity)
    }

    private static func run(_ launchPath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw OAuthServerError.tlsIdentityFailed
        }
    }
}
