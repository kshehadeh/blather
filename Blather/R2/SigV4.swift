import CryptoKit
import Foundation

enum SigV4 {
    static func signedHeaders(
        method: String,
        url: URL,
        region: String,
        service: String,
        accessKeyId: String,
        secretAccessKey: String,
        extraHeaders: [String: String] = [:],
        body: Data?,
        now: Date = Date()
    ) -> [String: String] {
        let amzDate = dateStamp(now, format: "yyyyMMdd'T'HHmmss'Z'")
        let shortDate = dateStamp(now, format: "yyyyMMdd")
        let payloadHash = sha256Hex(body ?? Data())
        var headers = extraHeaders
        headers["host"] = url.host ?? ""
        headers["x-amz-date"] = amzDate
        headers["x-amz-content-sha256"] = payloadHash

        let signedHeaderNames = headers.keys.sorted().map { $0.lowercased() }.joined(separator: ";")
        let canonicalHeaders = headers.keys.sorted().map { "\($0.lowercased()):\(headers[$0]!.trimmingCharacters(in: .whitespaces))\n" }.joined()
        let canonicalRequest = [
            method,
            canonicalURI(url),
            canonicalQuery(url),
            canonicalHeaders,
            signedHeaderNames,
            payloadHash,
        ].joined(separator: "\n")

        let scope = "\(shortDate)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        let signingKey = awsSigningKey(secret: secretAccessKey, date: shortDate, region: region, service: service)
        let signature = hmacHex(signingKey, Data(stringToSign.utf8))
        headers["Authorization"] =
            "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(scope), SignedHeaders=\(signedHeaderNames), Signature=\(signature)"
        return headers
    }

    static func presignedGET(
        url: URL,
        region: String,
        service: String,
        accessKeyId: String,
        secretAccessKey: String,
        expires: Int,
        now: Date = Date()
    ) -> URL {
        let amzDate = dateStamp(now, format: "yyyyMMdd'T'HHmmss'Z'")
        let shortDate = dateStamp(now, format: "yyyyMMdd")
        let scope = "\(shortDate)/\(region)/\(service)/aws4_request"
        let host = url.host ?? ""
        var items = [
            URLQueryItem(name: "X-Amz-Algorithm", value: "AWS4-HMAC-SHA256"),
            URLQueryItem(name: "X-Amz-Credential", value: "\(accessKeyId)/\(scope)"),
            URLQueryItem(name: "X-Amz-Date", value: amzDate),
            URLQueryItem(name: "X-Amz-Expires", value: String(expires)),
            URLQueryItem(name: "X-Amz-SignedHeaders", value: "host"),
        ]
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = items
        let canonicalRequest = [
            "GET",
            canonicalURI(url),
            canonicalQuery(components.url!),
            "host:\(host)\n",
            "host",
            "UNSIGNED-PAYLOAD",
        ].joined(separator: "\n")
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")
        let signingKey = awsSigningKey(secret: secretAccessKey, date: shortDate, region: region, service: service)
        let signature = hmacHex(signingKey, Data(stringToSign.utf8))
        items.append(URLQueryItem(name: "X-Amz-Signature", value: signature))
        components.queryItems = items
        return components.url!
    }

    private static func canonicalURI(_ url: URL) -> String {
        let path = url.path.isEmpty ? "/" : url.path
        return path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }

    private static func canonicalQuery(_ url: URL) -> String {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, !items.isEmpty else {
            return ""
        }
        return items
            .sorted { $0.name < $1.name }
            .map { "\(encode($0.name))=\(encode($0.value ?? ""))" }
            .joined(separator: "&")
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func awsSigningKey(secret: String, date: String, region: String, service: String) -> Data {
        let kDate = hmac(Data("AWS4\(secret)".utf8), Data(date.utf8))
        let kRegion = hmac(kDate, Data(region.utf8))
        let kService = hmac(kRegion, Data(service.utf8))
        return hmac(kService, Data("aws4_request".utf8))
    }

    private static func hmac(_ key: Data, _ message: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key))
        return Data(mac)
    }

    private static func hmacHex(_ key: Data, _ message: Data) -> String {
        hmac(key, message).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func dateStamp(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
