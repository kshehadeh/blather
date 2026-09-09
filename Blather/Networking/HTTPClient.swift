import Foundation

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

enum ProviderHTTP {
    static var client: any HTTPClient = URLSessionHTTPClient()

    static func fetchJSON(
        network: Network,
        url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> Any? {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await client.data(for: request)
        } catch {
            throw ProviderError(network: network, "\(network.rawValue): network request failed", retryable: true)
        }
        let parsed: Any? = data.isEmpty ? nil : (try? JSONSerialization.jsonObject(with: data)) ?? String(data: data, encoding: .utf8)
        if !(200..<300).contains(response.statusCode) {
            throw ProviderError(
                network: network,
                JSONValue.message(from: parsed, fallback: "\(network.rawValue): HTTP \(response.statusCode)"),
                retryable: response.statusCode >= 500 || response.statusCode == 429,
                status: response.statusCode
            )
        }
        return parsed
    }

    static func form(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}

enum JSONValue {
    static func object(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    static func string(_ value: Any?, _ path: String...) -> String? {
        var current: Any? = value
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        if let string = current as? String { return string }
        if let number = current as? NSNumber { return number.stringValue }
        return nil
    }

    static func message(from body: Any?, fallback: String) -> String {
        if let object = body as? [String: Any] {
            // OAuth 2 error responses (RFC 6749): {"error": "invalid_request", "error_description": "..."}
            if let code = object["error"] as? String, !code.isEmpty {
                if let description = object["error_description"] as? String, !description.isEmpty {
                    return Redaction.redact("\(code): \(description)")
                }
                return Redaction.redact(code)
            }
            let nested = object["error"] as? [String: Any]
            let firstError = (object["errors"] as? [[String: Any]])?.first
            let candidates: [Any?] = [
                nested?["message"],
                object["detail"],
                object["title"],
                object["message"],
                firstError?["message"],
            ]
            for candidate in candidates {
                if let text = candidate as? String, !text.isEmpty {
                    return Redaction.redact(text)
                }
            }
        }
        if let text = body as? String, !text.isEmpty {
            return Redaction.redact(String(text.prefix(300)))
        }
        return fallback
    }
}

enum ProviderErrors {
    static func sanitize(network: Network, _ error: Error) -> String {
        if let provider = error as? ProviderError {
            return Redaction.redact(provider.message)
        }
        return Redaction.redact("\(network.rawValue): \(error.localizedDescription)")
    }
}

enum MultipartForm {
    static func body(fields: [String: String], fileName: String, fileType: String, fileData: Data) -> (data: Data, contentType: String) {
        let boundary = "BlatherBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var data = Data()
        for (name, value) in fields {
            data.append("--\(boundary)\r\n")
            data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            data.append("\(value)\r\n")
        }
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"media\"; filename=\"\(fileName)\"\r\n")
        data.append("Content-Type: \(fileType)\r\n\r\n")
        data.append(fileData)
        data.append("\r\n--\(boundary)--\r\n")
        return (data, "multipart/form-data; boundary=\(boundary)")
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
